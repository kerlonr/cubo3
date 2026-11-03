import asyncio
import uuid
from typing import Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.ao_vivo import hub
from app.auth.deps import Ctx, ctx, papel_na_empresa, so_dono, usuario_do_token
from app.auth.seguranca import ler_token, token_link
from app.catalogo.modelos import Arquivo
from app.config import config
from app.crud import obter
from app.db import get_db
from app.empresa.modelos import Impressora
from app.impressoes.modelos import Impressao
from app.impressoes.rotas import saida_impressao
from app.klipper import moonraker
from app.klipper.monitor import monitores
from app.klipper.servico import ja_registrado, registrar_trabalho

rotas = APIRouter(prefix="/api", tags=["klipper"])


def _com_moonraker(db: Session, c: Ctx, id: uuid.UUID) -> Impressora:
    imp = obter(db, c, Impressora, id, "Impressora")
    if not imp.moonraker_url:
        raise HTTPException(422, "Impressora sem endereço do Klipper (Moonraker)")
    return imp


@rotas.get("/impressoras/{id}/ao-vivo")
def ao_vivo_impressora(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = obter(db, c, Impressora, id, "Impressora")
    return monitores.estado(imp.id) or {"estado": "desconectada" if imp.moonraker_url else "sem_integracao"}


@rotas.get("/impressoras/{id}/console")
def console(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = obter(db, c, Impressora, id, "Impressora")
    return {"linhas": monitores.console(imp.id)}


@rotas.get("/impressoras/{id}/historico")
def historico(id: uuid.UUID, limite: int = 50, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    try:
        jobs = moonraker.listar_historico(imp.moonraker_url, imp.api_key, min(max(limite, 1), 200))
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")
    trazidos = set(db.scalars(select(Impressao.job_id).where(Impressao.impressora_id == imp.id)))
    saida = []
    for job in jobs:
        d = moonraker.trabalho_de_historico(job)
        saida.append({"job_id": d.job_id, "arquivo": d.arquivo, "status": d.status,
                      "fim": d.fim.isoformat() if d.fim else None, "duracao_s": d.duracao_s,
                      "gramas_total": d.gramas_total, "filamentos": d.filamentos, "ja_trazido": d.job_id in trazidos})
    return saida


@rotas.post("/impressoras/{id}/historico/{job_id}/trazer")
def trazer(id: uuid.UUID, job_id: str, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    if (existente := ja_registrado(db, imp.id, job_id)) is not None:
        return saida_impressao(db, existente)
    try:
        job = moonraker.buscar_job(imp.moonraker_url, imp.api_key, job_id)
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")
    i = registrar_trabalho(db, c.empresa_id, imp.id, moonraker.trabalho_de_historico(job), arquivada=True)
    db.commit()
    return saida_impressao(db, i)


ACOES = {"pausar": "/printer/print/pause", "continuar": "/printer/print/resume",
         "cancelar": "/printer/print/cancel", "emergencia": "/printer/emergency_stop",
         "reiniciar_firmware": "/printer/firmware_restart"}
AQUECEDORES = {"bico": ("extruder", 300), "mesa": ("heater_bed", 120)}
OCUPADA = {"printing", "paused"}
HOME = {"XYZ": "G28 X Y Z", "XY": "G28 X Y", "Z": "G28 Z"}
# Movimentos que estragam a peça: imprimindo, nenhum; pausada, só home/motores (perdem a posição da retomada).
# Mover/extrudar com a impressão pausada continuam liberados: é a troca de filamento.
BLOQUEADOS = {"printing": ({"home", "mover", "motores_off", "extrudar"},
                           "A impressora está imprimindo: pause a impressão antes de mover os eixos"),
              "paused": ({"home", "motores_off"},
                         "Com a impressão pausada, home e desligar motores perdem a posição da peça")}
LIMITES = {"ventoinha": (0, 100), "velocidade": (10, 300), "fluxo": (50, 150)}


def _entre(valor, minimo, maximo, nome):
    if valor is None or not minimo <= abs(valor) <= maximo:
        raise ValueError(f"{nome}: use um valor entre {minimo:g} e {maximo:g}")


class Comando(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False)
    acao: Literal["pausar", "continuar", "cancelar", "emergencia", "reiniciar_firmware", "temperatura", "home",
                  "mover", "motores_off", "extrudar", "ventoinha", "velocidade", "fluxo", "ajuste_z", "macro"]
    alvo: Literal["bico", "mesa"] | None = None
    valor: float | None = None
    eixos: Literal["XYZ", "XY", "Z"] = "XYZ"
    eixo: Literal["X", "Y", "Z"] | None = None
    distancia: float | None = None
    nome: str | None = Field(None, pattern=r"^[A-Za-z0-9_]+$")

    @model_validator(mode="after")
    def _validar(self):
        a = self.acao
        if a == "temperatura":
            if self.alvo is None or self.valor is None:
                raise ValueError("Informe o aquecedor (bico ou mesa) e a temperatura")
            if not 0 <= self.valor <= AQUECEDORES[self.alvo][1]:
                raise ValueError(f"Temperatura do {self.alvo} deve ficar entre 0 e {AQUECEDORES[self.alvo][1]} °C")
        elif a == "mover":
            if self.eixo is None:
                raise ValueError("Informe o eixo (X, Y ou Z)")
            _entre(self.distancia, 0.1, 100, "Distância (mm)")
        elif a == "extrudar":
            _entre(self.distancia, 0.1, 50, "Filamento (mm)")
        elif a in LIMITES:
            if self.valor is None or not LIMITES[a][0] <= self.valor <= LIMITES[a][1]:
                raise ValueError(f"Use um valor entre {LIMITES[a][0]} e {LIMITES[a][1]} %")
        elif a == "ajuste_z":
            _entre(self.valor, 0.005, 0.5, "Ajuste de Z (mm)")
        elif a == "macro" and not self.nome:
            raise ValueError("Informe a macro")
        return self

    def gcode(self) -> str:
        a = self.acao
        if a == "temperatura":
            return f"SET_HEATER_TEMPERATURE HEATER={AQUECEDORES[self.alvo][0]} TARGET={self.valor:g}"
        if a == "home":
            return HOME[self.eixos]
        if a == "mover":
            # G90 vai numa chamada separada (ver enviar_comando): se o Klipper recusar o G1, o resto do
            # script não roda e a impressora ficaria em modo relativo.
            return f"G91\nG1 {self.eixo}{self.distancia:g} F{600 if self.eixo == 'Z' else 6000}"
        if a == "motores_off":
            return "M84"
        if a == "extrudar":
            return f"M83\nG1 E{self.distancia:g} F300"
        if a == "ventoinha":
            return "M107" if self.valor == 0 else f"M106 S{int(self.valor * 255 / 100 + 0.5)}"
        if a == "velocidade":
            return f"M220 S{self.valor:g}"
        if a == "fluxo":
            return f"M221 S{self.valor:g}"
        if a == "ajuste_z":
            return f"SET_GCODE_OFFSET Z_ADJUST={self.valor:g} MOVE=1"
        return self.nome  # macro


class GcodeLivre(BaseModel):
    script: str = Field(min_length=1, max_length=500)


class ImprimirDaImpressora(BaseModel):
    nome: str = Field(min_length=1, max_length=255)


class Imprimir(BaseModel):
    impressora_id: uuid.UUID


def _executar(imp: Impressora, caminho: str, params: dict | None = None) -> dict:
    try:
        moonraker.comando(imp.moonraker_url, imp.api_key, caminho, params)
    except moonraker.ErroKlipper as e:
        raise HTTPException(400, f"Klipper: {e}")
    except httpx.HTTPError:
        raise HTTPException(502, "A impressora não respondeu")
    return {"ok": True}


def _livre(imp: Impressora) -> None:
    estado = (monitores.estado(imp.id) or {}).get("estado") or moonraker.estado_impressao(imp.moonraker_url, imp.api_key)
    if estado in OCUPADA:
        raise HTTPException(409, "A impressora está ocupada")


@rotas.post("/impressoras/{id}/comando")
def enviar_comando(id: uuid.UUID, dados: Comando, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    if dados.acao in ACOES:
        return _executar(imp, ACOES[dados.acao])
    if dados.acao in {"home", "mover", "motores_off", "extrudar"}:
        try:
            estado = (monitores.estado(imp.id) or {}).get("estado") or \
                moonraker.estado_impressao(imp.moonraker_url, imp.api_key)
        except (httpx.HTTPError, KeyError, ValueError):
            raise HTTPException(502, "A impressora não respondeu")
        bloqueio = BLOQUEADOS.get(estado)
        if bloqueio and dados.acao in bloqueio[0]:
            raise HTTPException(409, bloqueio[1])
    if dados.acao == "macro":
        try:
            existe = dados.nome in moonraker.listar_macros(imp.moonraker_url, imp.api_key)
        except (httpx.HTTPError, KeyError, ValueError):
            raise HTTPException(502, "A impressora não respondeu")
        if not existe:
            raise HTTPException(422, "Macro não existe nesta impressora")
    if dados.acao == "mover":
        try:
            return _executar(imp, "/printer/gcode/script", {"script": dados.gcode()})
        finally:  # volta ao modo absoluto mesmo se o G1 foi recusado
            try:
                moonraker.comando(imp.moonraker_url, imp.api_key, "/printer/gcode/script", {"script": "G90"})
            except Exception:
                pass
    return _executar(imp, "/printer/gcode/script", {"script": dados.gcode()})


@rotas.post("/impressoras/{id}/gcode")
def gcode_livre(id: uuid.UUID, dados: GcodeLivre, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    return _executar(_com_moonraker(db, c, id), "/printer/gcode/script", {"script": dados.script})


@rotas.get("/impressoras/{id}/arquivos")
def arquivos_da_impressora(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    try:
        lista = moonraker.listar_arquivos(imp.moonraker_url, imp.api_key)
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")
    saida = []
    for f in sorted(lista, key=lambda f: f.get("modified", 0), reverse=True):
        mini = sorted(f.get("thumbnails") or [], key=lambda t: t.get("width", 0) * t.get("height", 0))
        quando = moonraker._quando(f.get("modified"))
        saida.append({"nome": f["filename"], "tamanho": f.get("size"),
                      "modificado": quando.isoformat() if quando else None,
                      "tempo_estimado_s": f.get("estimated_time"), "gramas": f.get("filament_weight_total"),
                      "miniatura": mini[-1]["relative_path"] if mini else None})
    return saida


def _caminho_seguro(caminho: str) -> bool:
    # % ? # ficam de fora: '%2e%2e' viraria '..' do outro lado e '?'/'#' trocariam o arquivo pedido.
    return (".." not in caminho and not caminho.startswith(("/", "\\"))
            and not any(c in caminho for c in ":%?#\\"))


@rotas.get("/impressoras/{id}/arquivos/miniatura")
def miniatura_da_impressora(id: uuid.UUID, caminho: str, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    if not _caminho_seguro(caminho) or not caminho.lower().endswith(".png"):
        raise HTTPException(422, "Caminho de miniatura inválido")
    imp = _com_moonraker(db, c, id)
    conteudo = moonraker.baixar(imp.moonraker_url, imp.api_key, caminho)
    if conteudo is None:
        raise HTTPException(404, "Miniatura não encontrada")
    return Response(conteudo, media_type="image/png", headers={"Cache-Control": "private, max-age=86400"})


@rotas.post("/impressoras/{id}/arquivos/imprimir")
def imprimir_da_impressora(id: uuid.UUID, dados: ImprimirDaImpressora, c: Ctx = Depends(so_dono),
                           db: Session = Depends(get_db)):
    if not _caminho_seguro(dados.nome):
        raise HTTPException(422, "Nome de arquivo inválido")
    imp = _com_moonraker(db, c, id)
    try:
        _livre(imp)
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")
    return _executar(imp, "/printer/print/start", {"filename": dados.nome})


@rotas.get("/impressoras/{id}/macros")
def macros(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    try:
        return [{"nome": n} for n in sorted(moonraker.listar_macros(imp.moonraker_url, imp.api_key))]
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")


@rotas.post("/arquivos/{id}/imprimir")
def imprimir_arquivo(id: uuid.UUID, dados: Imprimir, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    a = obter(db, c, Arquivo, id, "Arquivo")
    if a.tipo != "gcode":
        raise HTTPException(422, "Só dá para imprimir arquivo .gcode")
    imp = _com_moonraker(db, c, dados.impressora_id)
    try:
        _livre(imp)
        moonraker.enviar_e_imprimir(imp.moonraker_url, imp.api_key, a.nome_original, config().arquivos_dir / a.caminho)
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")
    return {"ok": True, "arquivo": a.nome_original}


def _camera(imp: Impressora) -> dict:
    try:
        cam = moonraker.webcam(imp.moonraker_url, imp.api_key)
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")
    if cam is None:
        raise HTTPException(404, "Sem câmera")
    return cam


@rotas.get("/impressoras/{id}/camera/foto")
def camera_foto(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    cam = _camera(_com_moonraker(db, c, id))
    try:
        return Response(moonraker.foto(cam["foto"]), media_type="image/jpeg", headers={"Cache-Control": "no-store"})
    except httpx.HTTPError:
        raise HTTPException(502, "A câmera não respondeu")


@rotas.post("/impressoras/{id}/camera/link")
def camera_link(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    return {"url": f"/api/camera/{token_link('camera', imp.id)}", "validade_s": 60}


@rotas.get("/camera/{token}")
async def camera_video(token: str, db: Session = Depends(get_db)):
    imp = db.get(Impressora, uuid.UUID(ler_token(token, "camera")["sub"]))
    db.close()  # o vídeo pode ficar aberto por muito tempo: não segura conexão do banco
    if imp is None or imp.excluido or not imp.moonraker_url:
        raise HTTPException(404, "Impressora não encontrada")
    cam = await asyncio.to_thread(_camera, imp)
    try:
        tipo, pedacos, fechar = await moonraker.abrir_video(cam["video"])
    except Exception:
        raise HTTPException(502, "A câmera não respondeu")

    async def repassar():
        try:
            async for pedaco in pedacos:
                yield pedaco
        finally:  # cliente fechou a tela (ou a câmera caiu): solta a conexão com a impressora
            await fechar()

    return StreamingResponse(repassar(), media_type=tipo, headers={"Cache-Control": "no-store"})


@rotas.websocket("/ao-vivo")
async def ao_vivo(ws: WebSocket, token: str = "", empresa: str = "", db: Session = Depends(get_db)):
    try:
        usuario = usuario_do_token(db, token)
    except HTTPException:
        await ws.close(code=4401)
        return
    try:
        empresa_id = uuid.UUID(empresa)
        membro = papel_na_empresa(db, usuario.id, empresa_id) is not None
    except ValueError:
        membro = False
    db.close()  # não segura conexão do banco enquanto o WebSocket fica aberto
    if not membro:
        await ws.close(code=4403)
        return
    await ws.accept()
    par = hub.conectar(empresa_id)
    leitor = asyncio.create_task(ws.receive_text())
    try:
        for estado in monitores.estados_da_empresa(empresa_id):
            await ws.send_json(estado)
        while True:
            pega = asyncio.create_task(par[1].get())
            feitos, _ = await asyncio.wait({pega, leitor}, return_when=asyncio.FIRST_COMPLETED)
            if leitor in feitos:
                pega.cancel()
                if leitor.exception() is not None:
                    break
                leitor = asyncio.create_task(ws.receive_text())  # cliente mandou "ping": ignora
                continue
            await ws.send_json(pega.result())
    except WebSocketDisconnect:
        pass
    finally:
        leitor.cancel()
        hub.desconectar(empresa_id, par)

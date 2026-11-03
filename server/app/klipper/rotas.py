import asyncio
import uuid
from typing import Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, model_validator
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
         "cancelar": "/printer/print/cancel", "emergencia": "/printer/emergency_stop"}
AQUECEDORES = {"bico": ("extruder", 300), "mesa": ("heater_bed", 120)}
OCUPADA = {"printing", "paused"}


class Comando(BaseModel):
    acao: Literal["pausar", "continuar", "cancelar", "emergencia", "temperatura"]
    alvo: Literal["bico", "mesa"] | None = None
    valor: float | None = None

    @model_validator(mode="after")
    def _temperatura(self):
        if self.acao == "temperatura":
            if self.alvo is None or self.valor is None:
                raise ValueError("Informe o aquecedor (bico ou mesa) e a temperatura")
            if not 0 <= self.valor <= AQUECEDORES[self.alvo][1]:
                raise ValueError(f"Temperatura do {self.alvo} deve ficar entre 0 e {AQUECEDORES[self.alvo][1]} °C")
        return self


class Imprimir(BaseModel):
    impressora_id: uuid.UUID


@rotas.post("/impressoras/{id}/comando")
def enviar_comando(id: uuid.UUID, dados: Comando, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    if dados.acao == "temperatura":
        aquecedor = AQUECEDORES[dados.alvo][0]
        caminho, params = "/printer/gcode/script", {
            "script": f"SET_HEATER_TEMPERATURE HEATER={aquecedor} TARGET={dados.valor:g}"}
    else:
        caminho, params = ACOES[dados.acao], None
    try:
        moonraker.comando(imp.moonraker_url, imp.api_key, caminho, params)
    except httpx.HTTPError:
        raise HTTPException(502, "A impressora não respondeu")
    return {"ok": True}


@rotas.post("/arquivos/{id}/imprimir")
def imprimir_arquivo(id: uuid.UUID, dados: Imprimir, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    a = obter(db, c, Arquivo, id, "Arquivo")
    if a.tipo != "gcode":
        raise HTTPException(422, "Só dá para imprimir arquivo .gcode")
    imp = _com_moonraker(db, c, dados.impressora_id)
    try:
        estado = (monitores.estado(imp.id) or {}).get("estado") or moonraker.estado_impressao(imp.moonraker_url, imp.api_key)
        if estado in OCUPADA:
            raise HTTPException(409, "A impressora está ocupada")
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

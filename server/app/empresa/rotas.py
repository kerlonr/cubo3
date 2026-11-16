from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Response
from urllib.parse import urlsplit

from pydantic import BaseModel, Field, field_validator
from app.custos import MINIMO, TETO
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx, so_dono
from app.auth.modelos import Empresa
from app.crud import rotas_crud, serializar
from app.custos import ParamEmpresa, ParamImpressora, custo_hora_impressora
from app.db import get_db
from app.empresa.modelos import CanalVenda, Impressora
from app.pix import mascarar, normalizar_chave

D = Decimal


class ConfigEmpresa(BaseModel):
    eficiencia: Decimal = Field(ParamEmpresa.eficiencia, gt=0, le=TETO)
    mao_obra_hora: Decimal = Field(ParamEmpresa.mao_obra_hora, ge=0, le=TETO)
    kwh: Decimal = Field(ParamEmpresa.kwh, ge=0, le=TETO)
    reserva: Decimal = Field(ParamEmpresa.reserva, gt=0, le=TETO)
    margens: list[Annotated[Decimal, Field(ge=0, lt=100)]] = Field(
        default_factory=lambda: [D(m) for m in ParamEmpresa.margens], min_length=1, max_length=10)


def param_empresa(db: Session, empresa_id) -> ParamEmpresa:
    cfg = ConfigEmpresa(**(db.get(Empresa, empresa_id).config or {}))
    return ParamEmpresa(cfg.eficiencia, cfg.mao_obra_hora, cfg.kwh, cfg.reserva, tuple(cfg.margens))


def param_impressora(imp: Impressora | None) -> ParamImpressora:
    if imp is None:
        return ParamImpressora()
    return ParamImpressora(imp.preco, imp.adicionais, imp.manutencao_pct_ano, imp.vida_anos, imp.uso_pct, imp.potencia_w)


def impressora_padrao(db: Session, empresa_id, impressora_id=None) -> Impressora | None:
    if impressora_id:
        imp = db.get(Impressora, impressora_id)
        if imp is not None and imp.empresa_id == empresa_id:
            return imp
    return db.scalar(select(Impressora).where(Impressora.empresa_id == empresa_id, Impressora.excluido.is_(False))
                     .order_by(Impressora.criado_em))


class CanalEntrada(BaseModel):
    nome: str | None = Field(None, min_length=1, max_length=60)
    taxa_pct: Decimal | None = Field(None, ge=0, lt=100, le=TETO)
    taxa_fixa: Decimal | None = Field(None, ge=0, le=TETO)


class ImpressoraEntrada(BaseModel):
    nome: str | None = Field(None, min_length=1, max_length=80)
    modelo: str | None = Field(None, max_length=80)
    preco: Decimal | None = Field(None, ge=0, le=TETO)
    adicionais: Decimal | None = Field(None, ge=0, le=TETO)
    manutencao_pct_ano: Decimal | None = Field(None, ge=0, le=TETO)
    vida_anos: Decimal | None = Field(None, ge=MINIMO, le=TETO)
    uso_pct: Decimal | None = Field(None, ge=MINIMO, le=100)
    potencia_w: Decimal | None = Field(None, ge=0, le=TETO)
    moonraker_url: str | None = Field(None, max_length=255)
    api_key: str | None = Field(None, max_length=128)

    @field_validator("moonraker_url")
    @classmethod
    def _url_limpa(cls, v: str | None) -> str | None:
        """Só o endereço da impressora (http/https, host e porta): sem caminho, query ou credencial, que
        deixariam o servidor pedir outra coisa na rede."""
        if not v:
            return v
        u = urlsplit(v.strip())
        if u.scheme not in ("http", "https") or not u.hostname or u.username or u.password \
                or u.query or u.fragment or u.path not in ("", "/"):
            raise ValueError("Use só o endereço da impressora, ex.: http://192.168.1.110:7125")
        return f"{u.scheme}://{u.netloc}"


def saida_impressora(db: Session, imp: Impressora) -> dict:
    db.flush()  # aplica os padrões das colunas antes do cálculo
    hora = custo_hora_impressora(param_impressora(imp), param_empresa(db, imp.empresa_id))
    return {**serializar(imp, excluir=("api_key",)), "tem_api_key": bool(imp.api_key),
            "custo_hora": float(hora.quantize(D("0.0001")))}


rotas = APIRouter(prefix="/api/empresa", tags=["empresa"])


class PixEntrada(BaseModel):
    tipo: Literal["cpf", "cnpj", "email", "telefone", "aleatoria"]
    chave: str = Field(min_length=1, max_length=100)
    nome: str = Field(min_length=1, max_length=60)
    cidade: str = Field(min_length=1, max_length=60)


def _sem_cache(resposta: Response) -> None:
    resposta.headers["Cache-Control"] = "no-store"


@rotas.get("/pix")
def ler_pix(resposta: Response, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    _sem_cache(resposta)
    pix = db.get(Empresa, c.empresa_id).pix
    if not pix:
        return {"configurado": False}
    saida = {"configurado": True, "tipo": pix["tipo"], "nome": pix["nome"], "cidade": pix["cidade"],
             "chave_mascarada": mascarar(pix["tipo"], pix["chave"])}
    if c.papel == "dono":
        saida["chave"] = pix["chave"]
    return saida


@rotas.put("/pix")
def gravar_pix(dados: PixEntrada, resposta: Response, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    try:
        chave = normalizar_chave(dados.tipo, dados.chave)
    except ValueError as e:
        raise HTTPException(422, str(e)) from None
    db.get(Empresa, c.empresa_id).pix = {"tipo": dados.tipo, "chave": chave, "nome": dados.nome.strip(),
                                          "cidade": dados.cidade.strip()}
    db.commit()
    return ler_pix(resposta, c, db)


@rotas.delete("/pix")
def apagar_pix(c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    db.get(Empresa, c.empresa_id).pix = None
    db.commit()
    return {"ok": True}


@rotas.get("/config")
def ler_config(c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    p = param_empresa(db, c.empresa_id)
    return {"eficiencia": float(p.eficiencia), "mao_obra_hora": float(p.mao_obra_hora), "kwh": float(p.kwh),
            "reserva": float(p.reserva), "margens": [float(m) for m in p.margens]}


@rotas.put("/config")
def gravar_config(dados: ConfigEmpresa, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    db.get(Empresa, c.empresa_id).config = dados.model_dump(mode="json")
    db.commit()
    return ler_config(c, db)


rotas_canais = rotas_crud(CanalVenda, CanalEntrada, lambda db, o: serializar(o), "/canais", nome="Canal")


def _ao_salvar_impressora(db: Session, c: Ctx, imp: Impressora, criado: bool) -> None:
    if imp.moonraker_url:
        outra = db.scalar(select(Impressora.id).where(Impressora.moonraker_url == imp.moonraker_url,
                                                      Impressora.empresa_id != c.empresa_id,
                                                      Impressora.excluido.is_(False)).limit(1))
        if outra is not None:
            raise HTTPException(409, "Essa impressora já está cadastrada em outra empresa")
    _reiniciar_monitor(db, c, imp)


def _reiniciar_monitor(db: Session, c: Ctx, imp: Impressora, *_) -> None:
    from app.klipper.monitor import monitores  # import tardio: klipper depende de empresa
    monitores.reiniciar(imp)


rotas_impressoras = rotas_crud(Impressora, ImpressoraEntrada, saida_impressora, "/impressoras", nome="Impressora",
                               so_dono_escreve=True, ao_salvar=_ao_salvar_impressora, ao_excluir=_reiniciar_monitor)

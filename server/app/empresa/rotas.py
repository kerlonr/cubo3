from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx, so_dono
from app.auth.modelos import Empresa
from app.crud import rotas_crud, serializar
from app.custos import ParamEmpresa, ParamImpressora, custo_hora_impressora
from app.db import get_db
from app.empresa.modelos import CanalVenda, Impressora

D = Decimal


class ConfigEmpresa(BaseModel):
    eficiencia: Decimal = ParamEmpresa.eficiencia
    mao_obra_hora: Decimal = ParamEmpresa.mao_obra_hora
    kwh: Decimal = ParamEmpresa.kwh
    reserva: Decimal = ParamEmpresa.reserva
    margens: list[Decimal] = Field(default_factory=lambda: [D(m) for m in ParamEmpresa.margens], min_length=1)


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
    nome: str | None = Field(None, min_length=1)
    taxa_pct: Decimal | None = Field(None, ge=0, lt=100)
    taxa_fixa: Decimal | None = Field(None, ge=0)


class ImpressoraEntrada(BaseModel):
    nome: str | None = Field(None, min_length=1)
    modelo: str | None = None
    preco: Decimal | None = Field(None, ge=0)
    adicionais: Decimal | None = Field(None, ge=0)
    manutencao_pct_ano: Decimal | None = Field(None, ge=0)
    vida_anos: Decimal | None = Field(None, gt=0)
    uso_pct: Decimal | None = Field(None, gt=0, le=100)
    potencia_w: Decimal | None = Field(None, ge=0)
    moonraker_url: str | None = None
    api_key: str | None = None


def saida_impressora(db: Session, imp: Impressora) -> dict:
    db.flush()  # aplica os padrões das colunas antes do cálculo
    hora = custo_hora_impressora(param_impressora(imp), param_empresa(db, imp.empresa_id))
    return {**serializar(imp, excluir=("api_key",)), "tem_api_key": bool(imp.api_key),
            "custo_hora": float(hora.quantize(D("0.0001")))}


rotas = APIRouter(prefix="/api/empresa", tags=["empresa"])


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


def _reiniciar_monitor(db: Session, c: Ctx, imp: Impressora, *_) -> None:
    from app.klipper.monitor import monitores  # import tardio: klipper depende de empresa
    monitores.reiniciar(imp)


rotas_impressoras = rotas_crud(Impressora, ImpressoraEntrada, saida_impressora, "/impressoras", nome="Impressora",
                               ao_salvar=_reiniciar_monitor, ao_excluir=_reiniciar_monitor)

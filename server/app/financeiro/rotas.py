from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx
from app.config import config
from app.crud import rotas_crud, serializar
from app.db import get_db
from app.estoque.rotas import estoque
from app.financeiro import painel
from app.financeiro.modelos import Despesa


class DespesaEntrada(BaseModel):
    data: date | None = None
    categoria: Literal["filamento", "insumo", "desperdicio", "embalagem", "equipamento", "manutencao", "energia",
                       "ferramenta", "outros"] | None = None
    valor: Decimal | None = Field(None, gt=0)
    descricao: str | None = None


rotas_despesas = rotas_crud(Despesa, DespesaEntrada, lambda db, o: serializar(o), "/despesas", nome="Despesa")
rotas = APIRouter(prefix="/api", tags=["painel"])


def _periodo(inicio: date | None, fim: date | None) -> tuple[date, date]:
    hoje = datetime.now(ZoneInfo(config().fuso)).date()
    inicio = inicio or hoje.replace(day=1)
    fim = fim or (inicio.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
    if fim < inicio:
        raise HTTPException(422, "Fim antes do início")
    return inicio, fim


@rotas.get("/extrato")
def ver_extrato(inicio: date | None = None, fim: date | None = None, c: Ctx = Depends(ctx),
                db: Session = Depends(get_db)):
    """Tudo que entrou e saiu no período (padrão: mês atual), linha a linha, para conferir e corrigir."""
    inicio, fim = _periodo(inicio, fim)
    return painel.extrato(db, c.empresa_id, inicio, fim, config().fuso)


@rotas.get("/painel")
def ver_painel(inicio: date | None = None, fim: date | None = None, c: Ctx = Depends(ctx),
               db: Session = Depends(get_db)):
    inicio, fim = _periodo(inicio, fim)
    dados = painel.calcular(db, c.empresa_id, inicio, fim, config().fuso)
    e = estoque(c, db)
    dados["estoque_baixo"] = (
        [{"tipo": "filamento", "id": f["id"], "nome": f"{f['marca']} {f['material']} {f['cor_nome'] or ''}".strip(),
          "saldo": f["total_g"]} for f in e["filamentos"] if f["baixo"]]
        + [{"tipo": "insumo", "id": i["id"], "nome": i["nome"], "saldo": i["saldo"]} for i in e["insumos"] if i["baixo"]])
    return dados

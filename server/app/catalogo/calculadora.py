import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx
from app.catalogo.custo import custo_json
from app.crud import obter
from app.custos import ItemCusto, ItemFilamento, Receita, calcular_custo, lucro_venda, preco_com_canal, preco_com_margem
from app.db import get_db
from app.empresa.modelos import CanalVenda
from app.empresa.rotas import impressora_padrao, param_empresa, param_impressora
from app.estoque.modelos import Filamento, Insumo

D = Decimal


class FilamentoCalc(BaseModel):
    filamento_id: uuid.UUID | None = None
    preco_kg: Decimal = Field(D(0), ge=0)
    gramas: Decimal = Field(ge=0)


class InsumoCalc(BaseModel):
    insumo_id: uuid.UUID | None = None
    custo_unitario: Decimal = Field(D(0), ge=0)
    qtd: Decimal = Field(ge=0)
    embalagem: bool = False


class Calculo(BaseModel):
    filamentos: list[FilamentoCalc] = []
    horas: Decimal = Field(D(0), ge=0)
    mao_obra_min: Decimal = Field(D(0), ge=0)
    insumos: list[InsumoCalc] = []
    custo_envio: Decimal = Field(D(0), ge=0)
    impressora_id: uuid.UUID | None = None


rotas = APIRouter(prefix="/api", tags=["calculadora"])


@rotas.post("/calculadora")
def calcular(dados: Calculo, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    filamentos = [ItemFilamento(f.gramas, obter(db, c, Filamento, f.filamento_id, "Filamento").preco_kg
                                if f.filamento_id else f.preco_kg) for f in dados.filamentos]
    insumos, embalagem = [], []
    for i in dados.insumos:
        custo, emb = i.custo_unitario, i.embalagem
        if i.insumo_id:
            ins = obter(db, c, Insumo, i.insumo_id, "Insumo")
            custo, emb = ins.custo_unitario, ins.categoria == "embalagem"
        (embalagem if emb else insumos).append(ItemCusto(i.qtd, custo))
    emp = param_empresa(db, c.empresa_id)
    imp = param_impressora(impressora_padrao(db, c.empresa_id, dados.impressora_id))
    custo = calcular_custo(Receita(filamentos, dados.horas, dados.mao_obra_min, insumos, embalagem, dados.custo_envio),
                           imp, emp)
    margem_meio = emp.margens[len(emp.margens) // 2]
    por_canal = []
    for canal in db.scalars(select(CanalVenda).where(CanalVenda.empresa_id == c.empresa_id,
                                                     CanalVenda.excluido.is_(False)).order_by(CanalVenda.criado_em)):
        try:
            preco = preco_com_canal(custo.total, margem_meio, canal.taxa_pct, canal.taxa_fixa)
            lucro = float(lucro_venda(preco, custo.total, canal.taxa_pct, canal.taxa_fixa))
            preco = float(preco)
        except ValueError:
            preco = lucro = None
        por_canal.append({"canal_id": str(canal.id), "nome": canal.nome, "margem": float(margem_meio),
                          "preco": preco, "lucro": lucro})
    return {"custo": custo_json(custo),
            "precos": [{"margem": float(m), "preco": float(preco_com_margem(custo.total, m))} for m in emp.margens],
            "por_canal": por_canal}

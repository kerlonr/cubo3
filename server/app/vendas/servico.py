import uuid
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Literal

from fastapi import HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx
from app.catalogo.custo import custo_do_modelo
from app.catalogo.modelos import Modelo
from app.crud import faltando, obter
from app.custos import r2
from app.db import agora
from app.empresa.modelos import CanalVenda
from app.estoque.servico import custo_medio_peca, id_derivado, lancar, saldo
from app.vendas.modelos import Cliente, Pedido, PedidoItem

D = Decimal
Status = Literal["orcamento", "aprovado", "produzindo", "pronto", "entregue", "cancelado"]
FECHADOS = {"entregue", "cancelado"}


class ItemEntrada(BaseModel):
    id: uuid.UUID
    modelo_id: uuid.UUID | None = None
    descricao: str = Field(min_length=1)
    quantidade: Decimal = Field(gt=0)
    preco_unitario: Decimal = Field(ge=0)


class PedidoEntrada(BaseModel):
    cliente_id: uuid.UUID | None = None
    canal_id: uuid.UUID | None = None
    status: Status | None = None
    desconto: Decimal | None = Field(None, ge=0)
    frete_cobrado: Decimal | None = Field(None, ge=0)
    custo_envio: Decimal | None = Field(None, ge=0)
    pago: bool | None = None
    forma_pagamento: str | None = None
    obs: str | None = None
    data: datetime | None = None
    entregue_em: datetime | None = None  # o app manda o momento real da entrega (fila offline)
    itens: list[ItemEntrada] | None = None


def _itens(db: Session, p: Pedido) -> list[PedidoItem]:
    return list(db.scalars(select(PedidoItem).where(PedidoItem.pedido_id == p.id).order_by(PedidoItem.criado_em)))


def _assinatura(itens, com_preco: bool = True) -> set:
    return {(str(i.id), str(i.modelo_id), D(i.quantidade).normalize()) + ((D(i.preco_unitario).normalize(),) if com_preco else ())
            for i in itens}


def _custo_item(db: Session, empresa_id, modelo_id) -> Decimal:
    if modelo_id is None:
        return D(0)
    medio = custo_medio_peca(db, empresa_id, modelo_id)
    return medio if medio is not None else custo_do_modelo(db, empresa_id, db.get(Modelo, modelo_id)).total


def _entregar(db: Session, c: Ctx, p: Pedido, quando: datetime | None) -> list[str]:
    canal = db.get(CanalVenda, p.canal_id) if p.canal_id else None
    p.taxa_pct, p.taxa_fixa = (canal.taxa_pct, canal.taxa_fixa) if canal else (D(0), D(0))
    p.entregue_em = quando or agora()
    bruto, custo_itens, avisos = D(0), D(0), []
    for it in _itens(db, p):
        it.custo_unitario = _custo_item(db, c.empresa_id, it.modelo_id)
        bruto += D(it.quantidade) * D(it.preco_unitario)
        custo_itens += D(it.quantidade) * it.custo_unitario
        if it.modelo_id:
            lancar(db, c, id=id_derivado(it.id, "venda"), item_tipo="peca", item_id=it.modelo_id, tipo="venda",
                   quantidade=-D(it.quantidade), valor=it.custo_unitario * D(it.quantidade), pedido_id=p.id,
                   data=p.entregue_em)
            s = saldo(db, c.empresa_id, "peca", it.modelo_id)
            if s < 0:
                avisos.append(f"Estoque de {db.get(Modelo, it.modelo_id).nome} ficou em {s.normalize()}")
    _recalcular(db, p)
    return avisos


def _recalcular(db: Session, p: Pedido) -> None:
    """Valores congelados da entrega a partir dos itens (custo de cada item e taxas do canal já fixados)."""
    itens = _itens(db, p)
    bruto = sum((D(i.quantidade) * D(i.preco_unitario) for i in itens), D(0))
    custo_itens = sum((D(i.quantidade) * D(i.custo_unitario or 0) for i in itens), D(0))
    receita = bruto - D(p.desconto or 0) + D(p.frete_cobrado or 0)
    taxas = bruto * D(p.taxa_pct or 0) / 100 + D(p.taxa_fixa or 0)
    p.bruto, p.receita, p.custo_itens, p.taxas = r2(bruto), r2(receita), r2(custo_itens), r2(taxas)
    p.lucro = r2(receita - custo_itens - taxas - D(p.custo_envio or 0))


def _estornar(db: Session, c: Ctx, p: Pedido) -> None:
    for it in _itens(db, p):
        if it.modelo_id:
            lancar(db, c, id=id_derivado(it.id, "estorno"), item_tipo="peca", item_id=it.modelo_id, tipo="ajuste",
                   quantidade=D(it.quantidade), pedido_id=p.id)


def mudar_status(db: Session, c: Ctx, p: Pedido, status: str, quando: datetime | None = None) -> list[str]:
    if status == p.status:
        return []
    if p.status == "cancelado":
        raise HTTPException(409, "Pedido cancelado não muda mais de status")
    if p.status == "entregue" and status != "cancelado":
        raise HTTPException(409, "Pedido entregue só pode ser cancelado")
    avisos = _entregar(db, c, p, quando) if status == "entregue" else []
    if status == "cancelado" and p.status == "entregue":
        _estornar(db, c, p)
    p.status = status
    db.flush()
    return avisos


def salvar_pedido(db: Session, c: Ctx, id: uuid.UUID, dados: PedidoEntrada) -> tuple[Pedido, list[str]]:
    p = db.get(Pedido, id)
    if p is not None and p.empresa_id != c.empresa_id:
        raise HTTPException(404, "Pedido não encontrado")
    if dados.cliente_id:
        obter(db, c, Cliente, dados.cliente_id, "Cliente")
    if dados.canal_id:
        obter(db, c, CanalVenda, dados.canal_id, "Canal")
    for it in dados.itens or []:
        if it.modelo_id:
            obter(db, c, Modelo, it.modelo_id, "Modelo")
        dono_item = db.get(PedidoItem, it.id)
        if dono_item is not None and dono_item.pedido_id != id:
            raise HTTPException(409, "Item pertence a outro pedido")

    campos = dados.model_dump(exclude_unset=True, exclude={"status", "itens", "entregue_em"})
    if p is None:
        p = Pedido(id=id, empresa_id=c.empresa_id, status="orcamento")
        db.add(p)
    elif p.status == "cancelado":
        if dados.itens is not None and _assinatura(dados.itens) != _assinatura(_itens(db, p)):
            raise HTTPException(409, "Não dá para mudar os itens de um pedido cancelado")
        campos = {k: v for k, v in campos.items() if k in ("pago", "forma_pagamento", "cliente_id", "obs")}
    elif p.status == "entregue":
        # Entregue: preço, desconto e frete podem ser corrigidos (o estoque já baixou, então itens e
        # quantidades ficam). Os valores congelados são recalculados com o mesmo custo e as mesmas taxas.
        atuais = {str(i.id): i for i in _itens(db, p)}
        if dados.itens is not None:
            if _assinatura(dados.itens, False) != _assinatura(atuais.values(), False):
                raise HTTPException(409, "Pedido entregue: só dá para mudar preço, desconto e frete (não os itens)")
            for it in dados.itens:
                atuais[str(it.id)].preco_unitario = it.preco_unitario
        campos = {k: v for k, v in campos.items()
                  if k in ("pago", "forma_pagamento", "cliente_id", "obs", "desconto", "frete_cobrado", "custo_envio")}
        for k, v in campos.items():
            setattr(p, k, v)
        db.flush()
        _recalcular(db, p)
        campos = {}
    for k, v in campos.items():
        setattr(p, k, v)
    if dados.itens is not None and p.status not in FECHADOS:
        for velho in _itens(db, p):
            db.delete(velho)
        db.flush()
        for it in dados.itens:
            db.add(PedidoItem(empresa_id=c.empresa_id, pedido_id=id, **it.model_dump()))
    if falta := faltando(p):
        raise HTTPException(422, f"Campos obrigatórios: {', '.join(falta)}")
    db.flush()
    avisos = mudar_status(db, c, p, dados.status, dados.entregue_em) if dados.status else []
    return p, avisos


def vendidos_por_modelo(db: Session, empresa_id, periodo_dias: int | None = None) -> dict[uuid.UUID, tuple[Decimal, Decimal]]:
    """modelo_id → (quantidade vendida, lucro bruto dos itens) em pedidos entregues."""
    q = (select(PedidoItem.modelo_id, func.sum(PedidoItem.quantidade),
                func.sum((PedidoItem.preco_unitario - func.coalesce(PedidoItem.custo_unitario, 0)) * PedidoItem.quantidade))
         .join(Pedido, Pedido.id == PedidoItem.pedido_id)
         .where(Pedido.empresa_id == empresa_id, Pedido.status == "entregue", Pedido.excluido.is_(False),
                PedidoItem.modelo_id.is_not(None)))
    if periodo_dias:
        q = q.where(Pedido.entregue_em >= agora() - timedelta(days=periodo_dias))
    return {m: (D(q_), D(l)) for m, q_, l in db.execute(q.group_by(PedidoItem.modelo_id)).all()}

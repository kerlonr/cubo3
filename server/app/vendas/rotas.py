import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx
from app.catalogo.modelos import Modelo
from app.crud import obter, rotas_crud, serializar
from app.db import get_db
from app.vendas import servico
from app.vendas.modelos import Cliente, Pedido


class ClienteEntrada(BaseModel):
    nome: str | None = Field(None, min_length=1)
    telefone: str | None = None
    email: str | None = None
    obs: str | None = None


class NovoStatus(BaseModel):
    status: servico.Status


def saida_pedido(db: Session, p: Pedido, avisos: list[str] | None = None) -> dict:
    itens = []
    for it in servico._itens(db, p):
        m = db.get(Modelo, it.modelo_id) if it.modelo_id else None
        itens.append({**serializar(it), "modelo": {"id": str(m.id), "nome": m.nome, "excluido": m.excluido} if m else None})
    cl = db.get(Cliente, p.cliente_id) if p.cliente_id else None
    return {**serializar(p), "itens": itens, "cliente": {"id": str(cl.id), "nome": cl.nome, "telefone": cl.telefone} if cl else None,
            "avisos": avisos or []}


rotas_clientes = rotas_crud(Cliente, ClienteEntrada, lambda db, o: serializar(o), "/clientes", nome="Cliente")
rotas = APIRouter(prefix="/api", tags=["vendas"])


@rotas.get("/clientes/{id}/historico")
def historico(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    cl = obter(db, c, Cliente, id, "Cliente")
    pedidos = list(db.scalars(select(Pedido).where(Pedido.cliente_id == cl.id, Pedido.excluido.is_(False))
                              .order_by(Pedido.data.desc())))
    total = sum((p.receita for p in pedidos if p.status == "entregue"), 0)
    return {"cliente": serializar(cl), "pedidos": [saida_pedido(db, p) for p in pedidos], "total_comprado": float(total)}


@rotas.get("/pedidos")
def listar(status: str | None = None, cliente_id: uuid.UUID | None = None, c: Ctx = Depends(ctx),
           db: Session = Depends(get_db)):
    q = select(Pedido).where(Pedido.empresa_id == c.empresa_id, Pedido.excluido.is_(False))
    if status:
        q = q.where(Pedido.status == status)
    if cliente_id:
        q = q.where(Pedido.cliente_id == cliente_id)
    return [saida_pedido(db, p) for p in db.scalars(q.order_by(Pedido.data.desc()))]


@rotas.get("/pedidos/{id}")
def um(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    return saida_pedido(db, obter(db, c, Pedido, id, "Pedido"))


@rotas.put("/pedidos/{id}")
def salvar(id: uuid.UUID, dados: servico.PedidoEntrada, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    p, avisos = servico.salvar_pedido(db, c, id, dados)
    db.commit()
    return saida_pedido(db, p, avisos)


@rotas.post("/pedidos/{id}/status")
def status(id: uuid.UUID, dados: NovoStatus, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    p = obter(db, c, Pedido, id, "Pedido")
    avisos = servico.mudar_status(db, c, p, dados.status)
    db.commit()
    return saida_pedido(db, p, avisos)


@rotas.delete("/pedidos/{id}")
def excluir(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    p = obter(db, c, Pedido, id, "Pedido")
    if p.status == "entregue":
        servico.mudar_status(db, c, p, "cancelado")  # devolve as peças ao estoque antes de sumir
    p.excluido = True
    db.commit()
    return {"ok": True}

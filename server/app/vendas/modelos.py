import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import ForeignKey, Numeric, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, DaEmpresa, UtcDateTime, agora

Num = Numeric(12, 4)


class Cliente(DaEmpresa, Base):
    __tablename__ = "clientes"
    nome: Mapped[str] = mapped_column(String(120))
    telefone: Mapped[str | None] = mapped_column(String(30))
    email: Mapped[str | None] = mapped_column(String(254))
    obs: Mapped[str | None] = mapped_column(Text)


class Pedido(DaEmpresa, Base):
    __tablename__ = "pedidos"
    cliente_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    canal_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    status: Mapped[str] = mapped_column(String(12), default="orcamento", index=True)
    desconto: Mapped[Decimal] = mapped_column(Num, default=0)
    frete_cobrado: Mapped[Decimal] = mapped_column(Num, default=0)
    custo_envio: Mapped[Decimal] = mapped_column(Num, default=0)
    pago: Mapped[bool] = mapped_column(default=False)
    forma_pagamento: Mapped[str | None] = mapped_column(String(30))
    obs: Mapped[str | None] = mapped_column(Text)
    data: Mapped[datetime] = mapped_column(UtcDateTime, default=agora)
    entregue_em: Mapped[datetime | None] = mapped_column(UtcDateTime, index=True)
    # congelados na entrega
    taxa_pct: Mapped[Decimal | None] = mapped_column(Num)
    taxa_fixa: Mapped[Decimal | None] = mapped_column(Num)
    bruto: Mapped[Decimal | None] = mapped_column(Num)
    receita: Mapped[Decimal | None] = mapped_column(Num)
    custo_itens: Mapped[Decimal | None] = mapped_column(Num)
    taxas: Mapped[Decimal | None] = mapped_column(Num)
    lucro: Mapped[Decimal | None] = mapped_column(Num)


class PedidoItem(DaEmpresa, Base):
    __tablename__ = "pedido_itens"
    pedido_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("pedidos.id"), index=True)
    modelo_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    descricao: Mapped[str] = mapped_column(String(160))
    quantidade: Mapped[Decimal] = mapped_column(Num)
    preco_unitario: Mapped[Decimal] = mapped_column(Num)
    custo_unitario: Mapped[Decimal | None] = mapped_column(Num)

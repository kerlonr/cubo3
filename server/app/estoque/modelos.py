import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Date, ForeignKey, Numeric, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, DaEmpresa, UtcDateTime, agora

Num = Numeric(12, 4)


class Filamento(DaEmpresa, Base):
    __tablename__ = "filamentos"
    marca: Mapped[str] = mapped_column(String(60))
    material: Mapped[str] = mapped_column(String(30))
    cor_nome: Mapped[str | None] = mapped_column(String(40))
    cor_hex: Mapped[str | None] = mapped_column(String(9))
    diametro: Mapped[Decimal] = mapped_column(Num, default=Decimal("1.75"))
    densidade: Mapped[Decimal] = mapped_column(Num, default=Decimal("1.24"))
    preco_kg: Mapped[Decimal] = mapped_column(Num)
    peso_carretel_vazio_g: Mapped[Decimal | None] = mapped_column(Num)
    estoque_minimo_g: Mapped[Decimal] = mapped_column(Num, default=0)


class Carretel(DaEmpresa, Base):
    __tablename__ = "carreteis"
    filamento_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("filamentos.id"), index=True)
    peso_inicial_g: Mapped[Decimal] = mapped_column(Num)
    preco_pago: Mapped[Decimal] = mapped_column(Num)
    data_compra: Mapped[date] = mapped_column(Date)
    local: Mapped[str | None] = mapped_column(String(60))
    aberto: Mapped[bool] = mapped_column(default=False)
    arquivado: Mapped[bool] = mapped_column(default=False)

    @property
    def preco_kg_real(self) -> Decimal:
        peso = Decimal(self.peso_inicial_g or 0)
        return Decimal(self.preco_pago) / peso * 1000 if peso > 0 else Decimal(0)


class Insumo(DaEmpresa, Base):
    __tablename__ = "insumos"
    nome: Mapped[str] = mapped_column(String(80))
    unidade: Mapped[str] = mapped_column(String(10), default="un")
    categoria: Mapped[str] = mapped_column(String(10), default="insumo")
    custo_unitario: Mapped[Decimal] = mapped_column(Num, default=0)
    estoque_minimo: Mapped[Decimal] = mapped_column(Num, default=0)


class Movimento(DaEmpresa, Base):
    __tablename__ = "movimentos"
    item_tipo: Mapped[str] = mapped_column(String(10))
    item_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True)
    tipo: Mapped[str] = mapped_column(String(10))
    quantidade: Mapped[Decimal] = mapped_column(Num)
    valor: Mapped[Decimal | None] = mapped_column(Num)
    impressao_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    pedido_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    usuario_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    data: Mapped[datetime] = mapped_column(UtcDateTime, default=agora, index=True)

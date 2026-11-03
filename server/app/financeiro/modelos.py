from datetime import date
from decimal import Decimal

from sqlalchemy import Date, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, DaEmpresa


class Despesa(DaEmpresa, Base):
    __tablename__ = "despesas"
    data: Mapped[date] = mapped_column(Date, index=True)
    categoria: Mapped[str] = mapped_column(String(12), default="outros")
    valor: Mapped[Decimal] = mapped_column(Numeric(12, 4))
    descricao: Mapped[str | None] = mapped_column(String(200))

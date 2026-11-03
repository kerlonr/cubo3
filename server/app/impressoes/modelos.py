import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import JSON, Integer, Numeric, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, DaEmpresa, UtcDateTime


class Impressao(DaEmpresa, Base):
    __tablename__ = "impressoes"
    __table_args__ = (UniqueConstraint("impressora_id", "job_id"),)
    impressora_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    modelo_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    origem: Mapped[str] = mapped_column(String(10), default="manual")
    job_id: Mapped[str | None] = mapped_column(String(40))
    arquivo: Mapped[str | None] = mapped_column(String(255))
    inicio: Mapped[datetime | None] = mapped_column(UtcDateTime)
    fim: Mapped[datetime | None] = mapped_column(UtcDateTime, index=True)
    duracao_s: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(12), default="a_confirmar", index=True)
    situacao_klipper: Mapped[str | None] = mapped_column(String(20))
    finalidade: Mapped[str | None] = mapped_column(String(10))
    pecas_boas: Mapped[int] = mapped_column(Integer, default=0)
    estimativa: Mapped[dict] = mapped_column(JSON, default=dict)
    miniatura: Mapped[str | None] = mapped_column(String(255))
    custo_total: Mapped[Decimal | None] = mapped_column(Numeric(12, 4))
    custo_unitario: Mapped[Decimal | None] = mapped_column(Numeric(12, 4))
    confirmada_por: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    confirmada_em: Mapped[datetime | None] = mapped_column(UtcDateTime)

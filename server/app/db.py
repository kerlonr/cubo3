import os
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Uuid, create_engine, event
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, declared_attr, mapped_column, sessionmaker
from sqlalchemy.types import TypeDecorator


def agora() -> datetime:
    return datetime.now(timezone.utc)


class UtcDateTime(TypeDecorator):
    """Sempre grava e devolve datetime com fuso UTC (o SQLite perde o fuso)."""

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is not None and value.tzinfo is None:
            raise ValueError("datetime sem fuso")
        return value.astimezone(timezone.utc) if value is not None else None

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


class Base(DeclarativeBase):
    pass


class Registro:
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    criado_em: Mapped[datetime] = mapped_column(UtcDateTime, default=agora)
    atualizado_em: Mapped[datetime] = mapped_column(UtcDateTime, default=agora, onupdate=agora, index=True)
    excluido: Mapped[bool] = mapped_column(Boolean, default=False)


@event.listens_for(Base, "before_update", propagate=True)
def _atualizado_em_crescente(mapper, conexao, alvo) -> None:
    # O relógio pode repetir o mesmo instante (Windows ~15 ms); a versão base (X-Versao-Base) precisa que
    # cada gravação tenha um atualizado_em estritamente maior que o anterior.
    if not isinstance(alvo, Registro):
        return
    novo, anterior = agora(), alvo.atualizado_em
    alvo.atualizado_em = novo if anterior is None or novo > anterior else anterior + timedelta(microseconds=1)


class DaEmpresa(Registro):
    @declared_attr
    def empresa_id(cls) -> Mapped[uuid.UUID]:
        return mapped_column(Uuid, ForeignKey("empresas.id"), index=True)


_url = os.environ.get("DATABASE_URL", "sqlite+pysqlite:///./cubo3.db")
engine = create_engine(_url, connect_args={"check_same_thread": False} if _url.startswith("sqlite") else {})
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_db():
    with SessionLocal() as s:
        yield s

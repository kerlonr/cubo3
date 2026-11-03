import uuid

from sqlalchemy import JSON, ForeignKey, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, Registro


class Usuario(Registro, Base):
    __tablename__ = "usuarios"
    email: Mapped[str] = mapped_column(String(254), unique=True)
    nome: Mapped[str] = mapped_column(String(120))
    senha_hash: Mapped[str] = mapped_column(String(200))
    token_versao: Mapped[int] = mapped_column(default=0)
    trocar_senha: Mapped[bool] = mapped_column(default=False)


class Empresa(Registro, Base):
    __tablename__ = "empresas"
    nome: Mapped[str] = mapped_column(String(120))
    config: Mapped[dict] = mapped_column(JSON, default=dict)


class Membro(Registro, Base):
    __tablename__ = "membros"
    __table_args__ = (UniqueConstraint("usuario_id", "empresa_id"),)
    usuario_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("usuarios.id"), index=True)
    empresa_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("empresas.id"), index=True)
    papel: Mapped[str] = mapped_column(String(10))

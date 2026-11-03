import uuid
from decimal import Decimal

from sqlalchemy import JSON, ForeignKey, Integer, Numeric, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, DaEmpresa
from app.estoque.servico import ITENS


class Modelo(DaEmpresa, Base):
    __tablename__ = "modelos"
    nome: Mapped[str] = mapped_column(String(120))
    descricao: Mapped[str | None] = mapped_column(Text)
    categoria: Mapped[str | None] = mapped_column(String(60))
    tags: Mapped[list] = mapped_column(JSON, default=list)
    links: Mapped[list] = mapped_column(JSON, default=list)
    receita: Mapped[dict] = mapped_column(JSON, default=dict)
    impressora_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    preco_venda: Mapped[Decimal | None] = mapped_column(Numeric(12, 4))
    nomes_arquivo: Mapped[list] = mapped_column(JSON, default=list)
    capa_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)


class Arquivo(DaEmpresa, Base):
    __tablename__ = "arquivos"
    modelo_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("modelos.id"), index=True)
    nome_original: Mapped[str] = mapped_column(String(255))
    tipo: Mapped[str] = mapped_column(String(10))
    tamanho: Mapped[int] = mapped_column(Integer)
    caminho: Mapped[str] = mapped_column(String(255))


ITENS["peca"] = Modelo

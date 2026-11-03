from decimal import Decimal

from sqlalchemy import Numeric, String
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.auth.modelos import Empresa
from app.auth.servico import ao_criar_empresa
from app.custos import ParamImpressora
from app.db import Base, DaEmpresa

Dinheiro = Numeric(12, 4)
_p = ParamImpressora()


class CanalVenda(DaEmpresa, Base):
    __tablename__ = "canais_venda"
    nome: Mapped[str] = mapped_column(String(60))
    taxa_pct: Mapped[Decimal] = mapped_column(Dinheiro, default=0)
    taxa_fixa: Mapped[Decimal] = mapped_column(Dinheiro, default=0)


class Impressora(DaEmpresa, Base):
    __tablename__ = "impressoras"
    nome: Mapped[str] = mapped_column(String(80))
    modelo: Mapped[str | None] = mapped_column(String(80))
    preco: Mapped[Decimal] = mapped_column(Dinheiro, default=_p.preco)
    adicionais: Mapped[Decimal] = mapped_column(Dinheiro, default=_p.adicionais)
    manutencao_pct_ano: Mapped[Decimal] = mapped_column(Dinheiro, default=_p.manutencao_pct_ano)
    vida_anos: Mapped[Decimal] = mapped_column(Dinheiro, default=_p.vida_anos)
    uso_pct: Mapped[Decimal] = mapped_column(Dinheiro, default=_p.uso_pct)
    potencia_w: Mapped[Decimal] = mapped_column(Dinheiro, default=_p.potencia_w)
    moonraker_url: Mapped[str | None] = mapped_column(String(200))
    api_key: Mapped[str | None] = mapped_column(String(200))


def _canal_direto(db: Session, e: Empresa) -> None:
    db.add(CanalVenda(empresa_id=e.id, nome="Direto", taxa_pct=0, taxa_fixa=0))


ao_criar_empresa.append(_canal_direto)

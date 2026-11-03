from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, Registro


class _Coisa(Registro, Base):
    __tablename__ = "_teste_coisa"
    nome: Mapped[str] = mapped_column(default="x")


def test_saude(cliente):
    assert cliente.get("/api/saude").json() == {"ok": True}


def test_utc_datetime(db):
    c = _Coisa()
    db.add(c)
    db.commit()
    db.expire_all()
    relido = db.get(_Coisa, c.id)
    assert relido.criado_em.tzinfo is not None
    assert relido.excluido is False

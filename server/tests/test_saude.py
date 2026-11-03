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


def test_atualizado_em_sempre_cresce_mesmo_com_relogio_parado(db, monkeypatch):
    """Relógio de baixa resolução (Windows) repetia o mesmo horário e a versão base não via a 2ª edição."""
    from datetime import datetime, timezone
    from app import db as db_mod
    parado = datetime(2026, 11, 3, 12, 0, tzinfo=timezone.utc)

    class RelogioParado(datetime):
        @classmethod
        def now(cls, tz=None):
            return parado

    monkeypatch.setattr(db_mod, "datetime", RelogioParado)
    c = _Coisa(nome="a")
    db.add(c)
    db.commit()
    v1 = c.atualizado_em
    c.nome = "b"
    db.commit()
    assert c.atualizado_em > v1

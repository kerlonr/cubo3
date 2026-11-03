import os

os.environ.setdefault("JWT_SEGREDO", "segredo-de-teste-" + "x" * 40)

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app import db as db_mod
from app.main import criar_app


@pytest.fixture
def engine(tmp_path):
    url = os.environ.get("TEST_DATABASE_URL") or f"sqlite+pysqlite:///{tmp_path / 'teste.db'}"
    eng = create_engine(url, connect_args={"check_same_thread": False} if url.startswith("sqlite") else {})
    db_mod.Base.metadata.create_all(eng)
    yield eng
    db_mod.Base.metadata.drop_all(eng)
    eng.dispose()


@pytest.fixture
def fabrica(engine):
    return sessionmaker(bind=engine, expire_on_commit=False)


@pytest.fixture
def db(fabrica):
    with fabrica() as s:
        yield s


@pytest.fixture
def app(fabrica, tmp_path, monkeypatch):
    monkeypatch.setenv("ARQUIVOS_DIR", str(tmp_path / "arquivos"))
    from app.config import config
    config.cache_clear()

    def _get_db():
        with fabrica() as s:
            yield s

    aplicacao = criar_app()
    aplicacao.dependency_overrides[db_mod.get_db] = _get_db
    yield aplicacao
    config.cache_clear()


@pytest.fixture
def cliente(app):
    with TestClient(app) as c:
        yield c

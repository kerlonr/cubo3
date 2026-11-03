import os

os.environ["KLIPPER_ATIVO"] = "0"  # testes não abrem conexão com impressora real
os.environ.setdefault("JWT_SEGREDO", "segredo-de-teste-" + "x" * 40)

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from argon2 import PasswordHasher

from app import db as db_mod
from app.auth import seguranca
from app.main import criar_app

seguranca._ph = PasswordHasher(time_cost=1, memory_cost=8, parallelism=1)  # só para os testes ficarem rápidos


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


SENHA = "senha-forte-123"


def _headers(cliente, email, empresa_id, senha=SENHA):
    r = cliente.post("/api/auth/login", json={"email": email, "senha": senha})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['acesso']}", "X-Empresa": str(empresa_id)}


@pytest.fixture
def empresas(db):
    from app.auth.servico import adicionar_membro, criar_dono

    _, a = criar_dono(db, "dono@a.com", "Dono A", SENHA, "Empresa A")
    adicionar_membro(db, a.id, "membro@a.com", "Membro A", SENHA)
    _, b = criar_dono(db, "dono@b.com", "Dono B", SENHA, "Empresa B")
    db.commit()
    return {"a": a.id, "b": b.id}


@pytest.fixture
def empresa_a_id(empresas):
    return empresas["a"]


@pytest.fixture
def dono(cliente, empresas):
    return _headers(cliente, "dono@a.com", empresas["a"])


@pytest.fixture
def membro(cliente, empresas):
    return _headers(cliente, "membro@a.com", empresas["a"])


@pytest.fixture
def outro(cliente, empresas):
    return _headers(cliente, "dono@b.com", empresas["b"])

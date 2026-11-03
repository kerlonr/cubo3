import json

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def web(tmp_path, monkeypatch, fabrica):
    from app import db as db_mod
    from app.config import config
    from app.main import criar_app

    (tmp_path / "web").mkdir()
    (tmp_path / "web" / "index.html").write_text("<html>cubo</html>")
    (tmp_path / "web" / "main.dart.js").write_text("// js")
    (tmp_path / "segredo.txt").write_text("não pode vazar")
    (tmp_path / "apk").mkdir()
    monkeypatch.setenv("WEB_DIR", str(tmp_path / "web"))
    monkeypatch.setenv("APK_DIR", str(tmp_path / "apk"))
    config.cache_clear()
    app = criar_app()

    def _get_db():
        with fabrica() as s:
            yield s

    app.dependency_overrides[db_mod.get_db] = _get_db
    with TestClient(app) as c:
        yield c, tmp_path
    config.cache_clear()


def test_spa_e_arquivos(web):
    c, _ = web
    assert c.get("/catalogo/abc").text == "<html>cubo</html>"
    assert c.get("/").text == "<html>cubo</html>"
    assert c.get("/main.dart.js").text == "// js"
    assert c.get("/api/saude").json() == {"ok": True}


def test_api_inexistente_404_json(web):
    c, _ = web
    r = c.get("/api/inexistente")
    assert r.status_code == 404 and r.headers["content-type"].startswith("application/json")


def test_nao_sai_da_pasta_web(web):
    c, _ = web
    assert "vazar" not in c.get("/..%2Fsegredo.txt").text
    assert "vazar" not in c.get("/%2E%2E/segredo.txt").text


def test_versao_e_baixar(web):
    c, tmp = web
    assert c.get("/api/versao").status_code == 404
    assert c.get("/baixar").status_code == 404
    (tmp / "apk" / "cubo3-1.0.0.apk").write_bytes(b"APK")
    (tmp / "apk" / "versao.json").write_text(json.dumps({"versao": "1.0.0", "build": 1, "apk": "cubo3-1.0.0.apk"}))
    assert c.get("/api/versao").json() == {"versao": "1.0.0", "build": 1, "apk_url": "/baixar"}
    r = c.get("/baixar")
    assert r.content == b"APK" and "cubo3-1.0.0.apk" in r.headers["content-disposition"]

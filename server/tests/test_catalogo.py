import uuid

from test_estoque import criar_filamento


def criar_modelo(cliente, h, **dados):
    i = uuid.uuid4()
    r = cliente.put(f"/api/modelos/{i}", headers=h, json={"nome": "Vaso", **dados})
    assert r.status_code == 200, r.text
    return r.json()


def enviar(cliente, h, modelo_id, nome="peca.stl", conteudo=b"solid cubo"):
    return cliente.post(f"/api/modelos/{modelo_id}/arquivos", headers=h,
                        files={"arquivo": (nome, conteudo, "application/octet-stream")})


def test_calculadora_planilha(cliente, dono):
    r = cliente.post("/api/calculadora", headers=dono,
                     json={"filamentos": [{"preco_kg": 100, "gramas": 33}], "horas": 3, "mao_obra_min": 10})
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["custo"]["total"] == 6.32
    assert [p["preco"] for p in d["precos"]] == [7.90, 9.03, 12.64]
    assert d["por_canal"] == [{"canal_id": d["por_canal"][0]["canal_id"], "nome": "Direto", "margem": 30,
                               "preco": 9.03, "lucro": 2.71}]


def test_custo_do_modelo_igual_calculadora(cliente, dono):
    f = criar_filamento(cliente, dono)
    m = criar_modelo(cliente, dono, preco_venda=15,
                     receita={"filamentos": [{"filamento_id": f["id"], "gramas": 33}], "horas": 3, "mao_obra_min": 10})
    assert m["custo"]["total"] == 6.32
    assert m["lucro_unitario"] == 8.68
    assert (m["estoque"], m["vendidos"], m["arquivos"]) == (0, 0, [])


def test_upload_e_download(cliente, dono):
    m = criar_modelo(cliente, dono)
    a = enviar(cliente, dono, m["id"])
    assert a.status_code == 200, a.text
    assert (a.json()["tipo"], a.json()["tamanho"]) == ("stl", 10)
    r = cliente.get(f"/api/arquivos/{a.json()['id']}", headers=dono)
    assert r.content == b"solid cubo"
    assert "peca.stl" in r.headers["content-disposition"]
    foto = enviar(cliente, dono, m["id"], "capa.JPG", b"\xff\xd8jpg").json()
    m2 = cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()
    assert m2["capa_id"] == foto["id"] and len(m2["arquivos"]) == 2
    assert cliente.delete(f"/api/arquivos/{a.json()['id']}", headers=dono).status_code == 200
    assert cliente.get(f"/api/arquivos/{a.json()['id']}", headers=dono).status_code == 404


def test_upload_grande_413(cliente, dono, monkeypatch, tmp_path):
    from app.config import config
    m = criar_modelo(cliente, dono)
    monkeypatch.setenv("MAX_UPLOAD_MB", "1")
    config.cache_clear()
    r = enviar(cliente, dono, m["id"], conteudo=b"x" * (2 * 1024 * 1024))
    assert r.status_code == 413
    assert [p for p in (tmp_path / "arquivos").rglob("*") if p.is_file()] == []


def test_extensao_proibida_415(cliente, dono):
    m = criar_modelo(cliente, dono)
    assert enviar(cliente, dono, m["id"], "virus.exe").status_code == 415


def test_download_outra_empresa_404(cliente, dono, outro):
    m = criar_modelo(cliente, dono)
    a = enviar(cliente, dono, m["id"]).json()
    assert cliente.get(f"/api/arquivos/{a['id']}", headers=outro).status_code == 404
    assert cliente.delete(f"/api/arquivos/{a['id']}", headers=outro).status_code == 404
    assert enviar(cliente, outro, m["id"]).status_code == 404


def test_busca_e_tag(cliente, dono):
    criar_modelo(cliente, dono, nome="Vaso Espiral", tags=["decoração"], categoria="Casa")
    criar_modelo(cliente, dono, nome="Suporte Celular", tags=["útil"], categoria="Escritório")
    nomes = lambda **p: [m["nome"] for m in cliente.get("/api/modelos", headers=dono, params=p).json()]
    assert nomes(busca="vaso") == ["Vaso Espiral"]
    assert nomes(tag="útil") == ["Suporte Celular"]
    assert nomes(categoria="Casa") == ["Vaso Espiral"]
    assert nomes(ordem="nome") == ["Suporte Celular", "Vaso Espiral"]


def test_link_de_download_assinado(cliente, dono, outro):
    m = criar_modelo(cliente, dono)
    a = enviar(cliente, dono, m["id"]).json()
    r = cliente.post(f"/api/arquivos/{a['id']}/link", headers=dono)
    assert r.status_code == 200 and r.json()["url"].startswith("/api/download/")
    baixado = cliente.get(r.json()["url"])  # sem cabeçalho de login: o link é a autorização
    assert baixado.content == b"solid cubo" and "peca.stl" in baixado.headers["content-disposition"]
    assert cliente.post(f"/api/arquivos/{a['id']}/link", headers=outro).status_code == 404
    acesso = dono["Authorization"].removeprefix("Bearer ")
    assert cliente.get(f"/api/download/{acesso}").status_code == 401
    assert cliente.get("/api/download/lixo").status_code == 401

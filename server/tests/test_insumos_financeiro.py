"""Modelo com várias peças e insumos, capa ajustada, extrato do financeiro e correção de gastos."""
import uuid

from test_catalogo import criar_modelo, enviar
from test_estoque import criar_carretel, criar_filamento

RECEITA_PLANILHA = {"horas": 3, "mao_obra_min": 10}


def test_pecas_com_nome_e_tempo_sao_guardadas(cliente, dono):
    f = criar_filamento(cliente, dono)
    m = criar_modelo(cliente, dono, receita={**RECEITA_PLANILHA, "filamentos": [
        {"filamento_id": f["id"], "gramas": 20, "nome": "Case", "horas": 2},
        {"filamento_id": f["id"], "gramas": 13, "nome": "Keycap", "horas": 1}]})
    pecas = m["receita"]["filamentos"]
    assert [(p["nome"], p["horas"]) for p in pecas] == [("Case", "2"), ("Keycap", "1")]
    assert m["custo"]["total"] == 6.32  # 33 g e 3 h no total: mesmo caso da planilha


def test_insumo_avulso_entra_no_custo(cliente, dono):
    m = criar_modelo(cliente, dono, receita={**RECEITA_PLANILHA, "filamentos": [{"preco_kg": 100, "gramas": 33}],
                                             "insumos": [{"nome": "Switch", "custo_unitario": 1.5, "qtd": 1},
                                                         {"nome": "Argola", "custo_unitario": 0.25, "qtd": 2},
                                                         {"nome": "Saquinho", "custo_unitario": 0.4, "qtd": 1,
                                                          "embalagem": True}]})
    assert (m["custo"]["insumos"], m["custo"]["embalagem"]) == (2.0, 0.4)
    assert m["custo"]["total"] == 8.72
    calc = cliente.post("/api/calculadora", headers=dono, json={
        "filamentos": [{"preco_kg": 100, "gramas": 33}], **RECEITA_PLANILHA,
        "insumos": [{"custo_unitario": 1.5, "qtd": 1}, {"custo_unitario": 0.25, "qtd": 2},
                    {"custo_unitario": 0.4, "qtd": 1, "embalagem": True}]}).json()
    assert calc["custo"]["total"] == m["custo"]["total"]


def test_insumo_cadastrado_vale_mais_que_o_preco_copiado(cliente, dono):
    i = str(uuid.uuid4())
    assert cliente.put(f"/api/insumos/{i}", headers=dono, json={"nome": "Switch", "custo_unitario": 2}).status_code == 200
    m = criar_modelo(cliente, dono, receita={"insumos": [{"insumo_id": i, "custo_unitario": 1.5, "qtd": 1}]})
    assert m["custo"]["insumos"] == 2.0
    cliente.delete(f"/api/insumos/{i}", headers=dono)
    outro_id = str(uuid.uuid4())  # id que não existe (ou de outra empresa): usa o preço copiado
    m2 = criar_modelo(cliente, dono, receita={"insumos": [{"insumo_id": outro_id, "custo_unitario": 1.5, "qtd": 1}]})
    assert m2["custo"]["insumos"] == 1.5


def test_insumo_de_outra_empresa_nao_vaza_preco(cliente, dono, outro):
    i = str(uuid.uuid4())
    cliente.put(f"/api/insumos/{i}", headers=outro, json={"nome": "Caro", "custo_unitario": 99})
    m = criar_modelo(cliente, dono, receita={"insumos": [{"insumo_id": i, "qtd": 1}]})
    assert m["custo"]["insumos"] == 0


def test_capa_escolhida_e_ajuste(cliente, dono):
    m = criar_modelo(cliente, dono)
    f1 = enviar(cliente, dono, m["id"], "a.png", b"png1").json()
    f2 = enviar(cliente, dono, m["id"], "b.png", b"png2").json()
    stl = enviar(cliente, dono, m["id"], "c.stl").json()
    r = cliente.put(f"/api/modelos/{m['id']}", headers=dono,
                    json={"capa_id": f2["id"], "capa_ajuste": {"x": 0.5, "y": -0.25, "zoom": 1.5}})
    assert r.status_code == 200, r.text
    assert (r.json()["capa_url"], r.json()["capa_ajuste"]) == (f"/api/arquivos/{f2['id']}",
                                                               {"x": 0.5, "y": -0.25, "zoom": 1.5})
    assert f1["id"] != f2["id"]
    assert cliente.put(f"/api/modelos/{m['id']}", headers=dono, json={"capa_id": stl["id"]}).status_code == 422
    assert cliente.put(f"/api/modelos/{m['id']}", headers=dono,
                       json={"capa_ajuste": {"x": 2, "y": 0, "zoom": 1}}).status_code == 422


def test_capa_de_outro_modelo_recusada(cliente, dono, outro):
    m = criar_modelo(cliente, dono)
    m2 = criar_modelo(cliente, outro)
    foto_b = enviar(cliente, outro, m2["id"], "b.png", b"png").json()
    assert cliente.put(f"/api/modelos/{m['id']}", headers=dono, json={"capa_id": foto_b["id"]}).status_code == 422


def test_despesas_de_filamento_insumo_e_desperdicio(cliente, dono):
    for cat in ("filamento", "insumo", "desperdicio"):
        r = cliente.put(f"/api/despesas/{uuid.uuid4()}", headers=dono,
                        json={"data": "2026-11-05", "categoria": cat, "valor": 10})
        assert r.status_code == 200, r.text
    p = cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    assert p["gastos"] == 30


def test_extrato_bate_com_painel(cliente, dono):
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"], peso=1000, preco=120)
    cliente.put(f"/api/despesas/{uuid.uuid4()}", headers=dono,
                json={"data": "2026-11-03", "categoria": "insumo", "valor": 15, "descricao": "Argolas"})
    m = criar_modelo(cliente, dono, preco_venda=20)
    pid = str(uuid.uuid4())
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={
        "status": "entregue", "entregue_em": "2026-11-04T15:00:00Z", "pago": True,
        "itens": [{"id": str(uuid.uuid4()), "modelo_id": m["id"], "descricao": "Vaso", "quantidade": 2,
                   "preco_unitario": 20}]})
    assert r.status_code == 200, r.text
    # perda de 50 g no carretel de R$ 120/kg = R$ 6 (só informativo)
    cliente.put(f"/api/movimentos/{uuid.uuid4()}", headers=dono, json={
        "item_tipo": "carretel", "item_id": car["id"], "tipo": "perda", "quantidade": -50,
        "data": "2026-11-04T12:00:00Z"})

    e = cliente.get("/api/extrato?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    p = cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    assert (e["entrou"], e["saiu"]) == (p["receita"], p["gastos"]) == (40, 135)
    assert [l["tipo"] for l in e["linhas"]] == ["venda", "despesa", "compra"]
    compra = e["linhas"][2]
    assert (compra["categoria"], compra["item_id"], compra["valor"]) == ("filamento", car["id"], 120)
    assert (e["perdas_g"], e["perdas_valor"]) == (50, 6)
    assert e["linhas"][0]["pago"] is True


def test_extrato_isolado_por_empresa(cliente, dono, outro):
    cliente.put(f"/api/despesas/{uuid.uuid4()}", headers=outro, json={"data": "2026-11-03", "valor": 99})
    assert cliente.get("/api/extrato?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["linhas"] == []


def test_editar_carretel_corrige_gasto_e_saldo(cliente, dono):
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"], peso=1000, preco=100)
    r = cliente.put(f"/api/carreteis/{car['id']}", headers=dono,
                    json={"preco_pago": 89.9, "peso_inicial_g": 800, "data_compra": "2026-10-20"})
    assert r.status_code == 200, r.text
    assert r.json()["saldo_g"] == 800
    out = cliente.get("/api/painel?inicio=2026-10-01&fim=2026-10-31", headers=dono).json()
    nov = cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    assert (out["gastos"], nov["gastos"]) == (89.9, 0)


def test_excluir_carretel_tira_o_gasto(cliente, dono):
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"], preco=100)
    assert cliente.delete(f"/api/carreteis/{car['id']}", headers=dono).status_code == 200
    assert cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["gastos"] == 0


def test_excluir_movimento_manual(cliente, dono, outro):
    i = str(uuid.uuid4())
    cliente.put(f"/api/insumos/{i}", headers=dono, json={"nome": "Argola", "custo_unitario": 0.3})
    mid = str(uuid.uuid4())
    cliente.put(f"/api/movimentos/{mid}", headers=dono, json={
        "item_tipo": "insumo", "item_id": i, "tipo": "compra", "quantidade": 100, "valor": 30,
        "data": "2026-11-02T12:00:00Z"})
    assert cliente.delete(f"/api/movimentos/{mid}", headers=outro).status_code == 404
    assert cliente.delete(f"/api/movimentos/{mid}", headers=dono).status_code == 200
    assert cliente.get(f"/api/insumos/{i}", headers=dono).json()["saldo"] == 0
    assert cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["gastos"] == 0


def test_compra_do_carretel_so_muda_pelo_carretel(cliente, dono):
    f = criar_filamento(cliente, dono)
    criar_carretel(cliente, dono, f["id"])
    compra = cliente.get("/api/extrato?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["linhas"][0]
    assert cliente.delete(f"/api/movimentos/{compra['id']}", headers=dono).status_code == 409


def test_extrato_sem_periodo_pega_tudo_e_resume_por_mes_e_categoria(cliente, dono):
    """Sem inicio/fim o extrato é o geral: soma meses diferentes e separa os gastos por categoria."""
    import uuid
    from test_catalogo import criar_modelo
    from test_vendas import item, venda

    m = criar_modelo(cliente, dono)
    venda(cliente, dono, [item(m["id"], qtd=1, preco=100)], custo_envio=0, entregue_em="2026-09-10T15:00:00Z")
    venda(cliente, dono, [item(m["id"], qtd=1, preco=50)], custo_envio=0, entregue_em="2026-11-10T15:00:00Z")
    for data, categoria, valor in (("2026-09-05", "energia", 30), ("2026-11-05", "energia", 20),
                                   ("2026-11-06", "ferramenta", 70)):
        assert cliente.put(f"/api/despesas/{uuid.uuid4()}", headers=dono,
                           json={"data": data, "categoria": categoria, "valor": valor}).status_code == 200

    e = cliente.get("/api/extrato", headers=dono).json()
    assert (e["entrou"], e["saiu"], e["resultado"]) == (150, 120, 30)
    assert e["inicio"] == "2000-01-01"
    assert [(x["mes"], x["receita"], x["gastos"]) for x in e["por_mes"]] == [("2026-09", 100, 30), ("2026-11", 50, 90)]
    assert e["por_categoria"] == [{"categoria": "ferramenta", "valor": 70}, {"categoria": "energia", "valor": 50}]
    assert e["total_linhas"] == len(e["linhas"]) == 5

    setembro = cliente.get("/api/extrato?inicio=2026-09-01&fim=2026-09-30", headers=dono).json()
    assert (setembro["entrou"], setembro["saiu"]) == (100, 30)
    assert [x["mes"] for x in setembro["por_mes"]] == ["2026-09"]

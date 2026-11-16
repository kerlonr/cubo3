import uuid

from test_catalogo import criar_modelo


def produzir(cliente, h, modelo_id, qtd=1, custo=6.32):
    r = cliente.put(f"/api/movimentos/{uuid.uuid4()}", headers=h, json={
        "item_tipo": "peca", "item_id": modelo_id, "tipo": "producao", "quantidade": qtd, "valor": custo * qtd})
    assert r.status_code == 200, r.text


def canal(cliente, h, nome="Direto"):
    return [c for c in cliente.get("/api/canais", headers=h).json() if c["nome"] == nome][0]["id"]


def item(modelo_id, qtd=2, preco=12.64):
    return {"id": str(uuid.uuid4()), "modelo_id": modelo_id, "descricao": "Vaso", "quantidade": qtd,
            "preco_unitario": preco}


def venda(cliente, h, itens, id=None, **extra):
    corpo = {"canal_id": canal(cliente, h), "status": "entregue", "pago": True, "custo_envio": 5, "itens": itens, **extra}
    return cliente.put(f"/api/pedidos/{id or uuid.uuid4()}", headers=h, json=corpo)


def estoque(cliente, h, modelo_id):
    return cliente.get(f"/api/modelos/{modelo_id}", headers=h).json()["estoque"]


def test_venda_rapida_lucro(cliente, dono):
    m = criar_modelo(cliente, dono)
    produzir(cliente, dono, m["id"])
    r = venda(cliente, dono, [item(m["id"])])
    assert r.status_code == 200, r.text
    p = r.json()
    assert (p["status"], p["bruto"], p["receita"], p["custo_itens"], p["taxas"], p["lucro"]) == \
        ("entregue", 25.28, 25.28, 12.64, 0, 7.64)
    assert p["itens"][0]["custo_unitario"] == 6.32


def test_venda_sem_estoque_avisa(cliente, dono):
    m = criar_modelo(cliente, dono)
    produzir(cliente, dono, m["id"])
    p = venda(cliente, dono, [item(m["id"])]).json()
    assert estoque(cliente, dono, m["id"]) == -1
    assert len(p["avisos"]) == 1 and "Vaso" in p["avisos"][0]


def test_reenvio_da_venda_rapida_nao_duplica(cliente, dono):
    m = criar_modelo(cliente, dono)
    i, itens = uuid.uuid4(), [item(m["id"])]
    assert venda(cliente, dono, itens, id=i).status_code == 200
    assert venda(cliente, dono, itens, id=i).status_code == 200
    assert estoque(cliente, dono, m["id"]) == -2


def test_cancelar_estorna(cliente, dono):
    m = criar_modelo(cliente, dono)
    produzir(cliente, dono, m["id"])
    p = venda(cliente, dono, [item(m["id"])]).json()
    for _ in range(2):
        r = cliente.post(f"/api/pedidos/{p['id']}/status", headers=dono, json={"status": "cancelado"})
        assert r.status_code == 200
        assert estoque(cliente, dono, m["id"]) == 1
    # cancelado reabre (cancelou sem querer): entregar de novo baixa o estoque de novo
    r = cliente.post(f"/api/pedidos/{p['id']}/status", headers=dono, json={"status": "entregue"})
    assert r.status_code == 200 and estoque(cliente, dono, m["id"]) == -1  # 1 produzida, 2 vendidas de novo


def test_fluxo_de_status_baixa_so_na_entrega(cliente, dono):
    m = criar_modelo(cliente, dono)
    produzir(cliente, dono, m["id"], qtd=2)
    p = venda(cliente, dono, [item(m["id"])], status="orcamento").json()
    assert p["lucro"] is None and estoque(cliente, dono, m["id"]) == 2
    for s in ("aprovado", "produzindo", "pronto"):
        assert cliente.post(f"/api/pedidos/{p['id']}/status", headers=dono, json={"status": s}).status_code == 200
    assert estoque(cliente, dono, m["id"]) == 2
    r = cliente.post(f"/api/pedidos/{p['id']}/status", headers=dono, json={"status": "entregue"}).json()
    assert r["lucro"] == 7.64 and estoque(cliente, dono, m["id"]) == 0


def test_taxa_do_canal_congelada(cliente, dono):
    m = criar_modelo(cliente, dono)
    produzir(cliente, dono, m["id"], qtd=2)
    c = str(uuid.uuid4())
    cliente.put(f"/api/canais/{c}", headers=dono, json={"nome": "Shopee", "taxa_pct": 20, "taxa_fixa": 4})
    p = venda(cliente, dono, [item(m["id"])], canal_id=c).json()
    assert (p["taxas"], p["lucro"]) == (9.06, -1.42)
    cliente.put(f"/api/canais/{c}", headers=dono, json={"taxa_pct": 50})
    assert cliente.get(f"/api/pedidos/{p['id']}", headers=dono).json()["lucro"] == -1.42


def test_itens_de_pedido_entregue_podem_ser_corrigidos(cliente, dono):
    m = criar_modelo(cliente, dono)
    i = uuid.uuid4()
    venda(cliente, dono, [item(m["id"])], id=i)
    assert venda(cliente, dono, [item(m["id"], qtd=5)], id=i).status_code == 200
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == -5


def test_modelo_excluido_no_pedido(cliente, dono):
    m = criar_modelo(cliente, dono, nome="Luminária")
    p = venda(cliente, dono, [item(m["id"])]).json()
    cliente.delete(f"/api/modelos/{m['id']}", headers=dono)
    it = cliente.get(f"/api/pedidos/{p['id']}", headers=dono).json()["itens"][0]
    assert (it["descricao"], it["modelo"]["nome"], it["modelo"]["excluido"]) == ("Vaso", "Luminária", True)


def test_mais_vendidos(cliente, dono):
    x = criar_modelo(cliente, dono, nome="A Pouco")
    y = criar_modelo(cliente, dono, nome="B Muito")
    venda(cliente, dono, [item(x["id"], qtd=1)])
    venda(cliente, dono, [item(y["id"], qtd=3)])
    venda(cliente, dono, [item(x["id"], qtd=9)], status="orcamento")
    lista = cliente.get("/api/modelos", headers=dono, params={"ordem": "mais_vendidos"}).json()
    assert [(m["nome"], m["vendidos"]) for m in lista] == [("B Muito", 3), ("A Pouco", 1)]


def test_historico_cliente(cliente, dono):
    m = criar_modelo(cliente, dono)
    cl = str(uuid.uuid4())
    assert cliente.put(f"/api/clientes/{cl}", headers=dono, json={"nome": "Ana", "telefone": "55999"}).status_code == 200
    venda(cliente, dono, [item(m["id"], qtd=1, preco=10)], cliente_id=cl)
    venda(cliente, dono, [item(m["id"], qtd=1, preco=20)], cliente_id=cl, frete_cobrado=3)
    venda(cliente, dono, [item(m["id"], qtd=1, preco=99)], cliente_id=cl, status="orcamento")
    h = cliente.get(f"/api/clientes/{cl}/historico", headers=dono).json()
    assert (h["cliente"]["nome"], len(h["pedidos"]), h["total_comprado"]) == ("Ana", 3, 33)


def test_cliente_de_outra_empresa_404(cliente, dono, outro):
    m = criar_modelo(cliente, outro)
    cl = str(uuid.uuid4())
    cliente.put(f"/api/clientes/{cl}", headers=dono, json={"nome": "Ana"})
    assert venda(cliente, outro, [item(m["id"])], cliente_id=cl).status_code == 404
    assert cliente.get(f"/api/clientes/{cl}/historico", headers=outro).status_code == 404


def test_pedido_traz_telefone_do_cliente_para_o_whatsapp(cliente, dono):
    import uuid as _uuid
    cid = str(_uuid.uuid4())
    assert cliente.put(f"/api/clientes/{cid}", headers=dono, json={"nome": "Ana", "telefone": "54999998888"}).status_code == 200
    pid = str(_uuid.uuid4())
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"cliente_id": cid, "status": "orcamento", "itens": [
        {"id": str(_uuid.uuid4()), "descricao": "Vaso", "quantidade": 1, "preco_unitario": 30}]})
    assert r.status_code == 200, r.text
    assert r.json()["cliente"] == {"id": cid, "nome": "Ana", "telefone": "54999998888"}

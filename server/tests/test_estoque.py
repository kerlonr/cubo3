import uuid


def criar_filamento(cliente, h, **extra):
    i = uuid.uuid4()
    dados = {"marca": "GTMAX", "material": "PLA", "cor_nome": "Branco", "cor_hex": "#FFFFFF", "preco_kg": 100, **extra}
    r = cliente.put(f"/api/filamentos/{i}", headers=h, json=dados)
    assert r.status_code == 200, r.text
    return r.json()


def criar_carretel(cliente, h, filamento_id, peso=1000, preco=100):
    i = uuid.uuid4()
    r = cliente.put(f"/api/carreteis/{i}", headers=h, json={
        "filamento_id": filamento_id, "peso_inicial_g": peso, "preco_pago": preco, "data_compra": "2026-11-02"})
    assert r.status_code == 200, r.text
    return r.json()


def mov(cliente, h, item_id, tipo, qtd, item_tipo="carretel", id=None):
    return cliente.put(f"/api/movimentos/{id or uuid.uuid4()}", headers=h, json={
        "item_tipo": item_tipo, "item_id": item_id, "tipo": tipo, "quantidade": qtd})


def saldo(cliente, h, carretel_id):
    return cliente.get(f"/api/carreteis/{carretel_id}", headers=h).json()["saldo_g"]


def test_compra_automatica_e_consumo(cliente, dono):
    f = criar_filamento(cliente, dono)
    c = criar_carretel(cliente, dono, f["id"])
    assert c["saldo_g"] == 1000
    compras = cliente.get("/api/movimentos", headers=dono, params={"item_tipo": "carretel", "item_id": c["id"]}).json()
    assert [(m["tipo"], m["quantidade"], m["valor"]) for m in compras] == [("compra", 1000, 100)]
    assert mov(cliente, dono, c["id"], "consumo", -33).status_code == 200
    assert saldo(cliente, dono, c["id"]) == 967


def test_carretel_reenviado_nao_compra_de_novo(cliente, dono):
    f = criar_filamento(cliente, dono)
    c = criar_carretel(cliente, dono, f["id"])
    cliente.put(f"/api/carreteis/{c['id']}", headers=dono, json={"local": "Prateleira 2"})
    assert saldo(cliente, dono, c["id"]) == 1000


def test_pesagem(cliente, dono):
    f = criar_filamento(cliente, dono, peso_carretel_vazio_g=200)
    c = criar_carretel(cliente, dono, f["id"])
    mov(cliente, dono, c["id"], "consumo", -33)
    r = cliente.post(f"/api/carreteis/{c['id']}/pesagem", headers=dono,
                     json={"movimento_id": str(uuid.uuid4()), "peso_balanca_g": 900})
    assert r.status_code == 200, r.text
    assert r.json()["saldo_g"] == 700
    ajustes = [m for m in cliente.get("/api/movimentos", headers=dono, params={"item_id": c["id"]}).json()
               if m["tipo"] == "ajuste"]
    assert [a["quantidade"] for a in ajustes] == [-267]


def test_pesagem_sem_peso_vazio_422(cliente, dono):
    f = criar_filamento(cliente, dono)
    c = criar_carretel(cliente, dono, f["id"])
    r = cliente.post(f"/api/carreteis/{c['id']}/pesagem", headers=dono,
                     json={"movimento_id": str(uuid.uuid4()), "peso_balanca_g": 900})
    assert r.status_code == 422


def test_movimento_idempotente(cliente, dono):
    f = criar_filamento(cliente, dono)
    c = criar_carretel(cliente, dono, f["id"])
    i = uuid.uuid4()
    for _ in range(2):
        assert mov(cliente, dono, c["id"], "consumo", -50, id=i).status_code == 200
    assert saldo(cliente, dono, c["id"]) == 950


def test_sinal_invalido_422(cliente, dono):
    f = criar_filamento(cliente, dono)
    c = criar_carretel(cliente, dono, f["id"])
    assert mov(cliente, dono, c["id"], "consumo", 33).status_code == 422
    assert mov(cliente, dono, c["id"], "compra", -1).status_code == 422
    assert mov(cliente, dono, c["id"], "ajuste", 0).status_code == 422


def test_estoque_baixo(cliente, dono):
    f = criar_filamento(cliente, dono, estoque_minimo_g=500)
    criar_carretel(cliente, dono, f["id"], peso=400)
    i = uuid.uuid4()
    cliente.put(f"/api/insumos/{i}", headers=dono, json={"nome": "Ímã 6x2", "unidade": "un", "custo_unitario": 0.5,
                                                         "estoque_minimo": 10})
    mov(cliente, dono, str(i), "compra", 4, item_tipo="insumo")
    e = cliente.get("/api/estoque", headers=dono).json()
    assert [(x["total_g"], x["baixo"]) for x in e["filamentos"]] == [(400, True)]
    assert [(x["saldo"], x["baixo"]) for x in e["insumos"]] == [(4, True)]
    assert e["carreteis"][0]["saldo_g"] == 400


def test_filamento_excluido_resolve_no_carretel(cliente, dono):
    f = criar_filamento(cliente, dono)
    c = criar_carretel(cliente, dono, f["id"])
    cliente.delete(f"/api/filamentos/{f['id']}", headers=dono)
    assert cliente.get("/api/filamentos", headers=dono).json() == []
    assert cliente.get(f"/api/carreteis/{c['id']}", headers=dono).json()["filamento"]["material"] == "PLA"


def test_carretel_outra_empresa(cliente, dono, outro):
    f = criar_filamento(cliente, dono)
    c = criar_carretel(cliente, dono, f["id"])
    assert mov(cliente, outro, c["id"], "consumo", -10).status_code == 404
    assert saldo(cliente, dono, c["id"]) == 1000


def test_carretel_com_filamento_de_outra_empresa_404(cliente, dono, outro):
    f = criar_filamento(cliente, dono)
    r = cliente.put(f"/api/carreteis/{uuid.uuid4()}", headers=outro, json={
        "filamento_id": f["id"], "peso_inicial_g": 1000, "preco_pago": 100, "data_compra": "2026-11-02"})
    assert r.status_code == 404

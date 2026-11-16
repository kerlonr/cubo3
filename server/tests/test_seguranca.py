"""Achados do pentest (rodadas 1 e 2): cada um com a prova de que está fechado."""
import time
import uuid

import jwt

from test_catalogo import criar_modelo
from test_impressoes import confirmar, preparar
from test_pix_pagamentos import PIX, _pedido


def test_impressora_so_o_dono_grava_e_url_e_so_o_endereco(cliente, dono, membro, outro):
    assert cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=membro, json={"nome": "X"}).status_code == 403
    for url in ("http://127.0.0.1:8778/segredo.txt?x=", "file:///etc/passwd", "http://u:s@10.0.0.1",
                "http://10.0.0.1/caminho", "gopher://10.0.0.1"):
        r = cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=dono, json={"nome": "X", "moonraker_url": url})
        assert r.status_code == 422, url
    i = str(uuid.uuid4())
    r = cliente.put(f"/api/impressoras/{i}", headers=dono, json={"nome": "V3", "moonraker_url": "http://192.168.1.110:7125/"})
    assert r.status_code == 200 and r.json()["moonraker_url"] == "http://192.168.1.110:7125"
    # a mesma impressora física não pode ser controlada por outra empresa
    r = cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=outro, json={"nome": "Z", "moonraker_url": "http://192.168.1.110:7125"})
    assert r.status_code == 409


def test_valor_que_vira_zero_no_banco_e_recusado(cliente, dono):
    f = cliente.put(f"/api/filamentos/{uuid.uuid4()}", headers=dono, json={"marca": "X", "material": "PLA", "preco_kg": 100}).json()
    r = cliente.put(f"/api/carreteis/{uuid.uuid4()}", headers=dono, json={
        "filamento_id": f["id"], "peso_inicial_g": "0.00001", "preco_pago": 10, "data_compra": "2026-11-02"})
    assert r.status_code == 422
    assert cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=dono, json={"nome": "V", "vida_anos": "0.00001"}).status_code == 422
    assert cliente.get("/api/estoque", headers=dono).status_code == 200


def test_pedido_excluido_nao_muda_mais(cliente, dono):
    pid, iid, m = _pedido(cliente, dono, status="aberto", qtd=4)
    cliente.delete(f"/api/pedidos/{pid}", headers=dono)
    assert cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"status": "entregue"}).status_code == 404
    assert cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "entregue"}).status_code == 404
    assert cliente.get(f"/api/pedidos/{pid}", headers=dono).status_code == 404
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == 0


def test_listas_textos_inteiros_e_datas_com_limite(cliente, dono):
    m = str(uuid.uuid4())
    assert cliente.put(f"/api/modelos/{m}", headers=dono, json={"nome": "X", "links": [{"url": "javascript:alert(1)"}]}).status_code == 422
    assert cliente.put(f"/api/modelos/{m}", headers=dono, json={"nome": "X", "tags": ["t"] * 31}).status_code == 422
    assert cliente.put(f"/api/clientes/{uuid.uuid4()}", headers=dono, json={"nome": "😀" * 200}).status_code == 422
    assert cliente.put(f"/api/impressoes/{uuid.uuid4()}", headers=dono, json={"duracao_s": 2**62}).status_code == 422
    _, car, mod, i = preparar(cliente, dono)
    assert confirmar(cliente, dono, i["id"], finalidade="venda", pecas_boas=2**62, modelo_id=mod["id"]).status_code == 422
    for data in ("0001-01-01T00:00:00+14:00", "9999-12-31T23:59:59-12:00", "2026-10-31T23:30:00"):
        r = cliente.put(f"/api/pedidos/{uuid.uuid4()}", headers=dono, json={"data": data})
        assert r.status_code == 422, data
    assert cliente.put("/api/empresa/config", headers=dono, json={"margens": [10] * 11}).status_code == 422


def test_token_sem_validade_nao_vale(cliente, dono, empresa_a_id):
    from app.config import config
    claims = jwt.decode(dono["Authorization"].split()[1], options={"verify_signature": False})
    claims.pop("exp")
    sem_exp = jwt.encode(claims, config().jwt_segredo, algorithm="HS256")
    assert cliente.get("/api/eu", headers={"Authorization": f"Bearer {sem_exp}"}).status_code == 401
    claims["exp"] = int(time.time()) - 10
    vencido = jwt.encode(claims, config().jwt_segredo, algorithm="HS256")
    assert cliente.get("/api/eu", headers={"Authorization": f"Bearer {vencido}"}).status_code == 401


def test_cobranca_de_pedido_nao_passa_do_total(cliente, dono):
    cliente.put("/api/empresa/pix", headers=dono, json=PIX)
    pid, _, _ = _pedido(cliente, dono)  # 40
    assert cliente.post("/api/pix/cobranca", headers=dono, json={"pedido_id": pid, "valor": 9999999}).status_code == 422
    assert cliente.post("/api/pix/cobranca", headers=dono, json={"pedido_id": pid, "valor": 20}).status_code == 200


def test_docs_da_api_fechadas_por_padrao(cliente):
    assert cliente.get("/api/docs").status_code == 404
    assert cliente.get("/api/openapi.json").status_code == 404


def test_valor_gigante_no_pedido_nao_derruba_a_lista(cliente, dono):
    r = cliente.put(f"/api/pedidos/{uuid.uuid4()}", headers=dono, json={"itens": [
        {"id": str(uuid.uuid4()), "descricao": "x", "quantidade": 1e300, "preco_unitario": 1e300}]})
    assert r.status_code == 422
    assert cliente.get("/api/pedidos", headers=dono).status_code == 200
    assert criar_modelo(cliente, dono)  # segue funcionando

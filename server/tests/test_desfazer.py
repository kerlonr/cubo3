"""Liberdade para corrigir: reabrir impressão confirmada/descartada, reabrir pedido cancelado, data da venda,
aviso de troco e o que de fato entrou no mês."""
import uuid

from test_estoque import saldo
from test_impressoes import confirmar, preparar
from test_pix_pagamentos import _pedido


def _estoque(cliente, h, modelo_id):
    return cliente.get(f"/api/modelos/{modelo_id}", headers=h).json()["estoque"]


def test_reabrir_impressao_confirmada_e_confirmar_de_novo_com_outros_numeros(cliente, dono, outro):
    _, car, m, i = preparar(cliente, dono)
    confirmar(cliente, dono, i["id"], finalidade="venda", pecas_boas=1, modelo_id=m["id"],
              consumos=[{"carretel_id": car["id"], "gramas": 33}])
    assert (saldo(cliente, dono, car["id"]), _estoque(cliente, dono, m["id"])) == (967, 1)
    assert cliente.post(f"/api/impressoes/{i['id']}/reabrir", headers=outro).status_code == 404
    r = cliente.post(f"/api/impressoes/{i['id']}/reabrir", headers=dono)
    assert r.status_code == 200 and r.json()["status"] == "a_confirmar"
    assert (saldo(cliente, dono, car["id"]), _estoque(cliente, dono, m["id"])) == (1000, 0)
    r = confirmar(cliente, dono, i["id"], finalidade="venda", pecas_boas=3, modelo_id=m["id"],
                  consumos=[{"carretel_id": car["id"], "gramas": 99}])
    assert r.status_code == 200 and r.json()["pecas_boas"] == 3
    assert (saldo(cliente, dono, car["id"]), _estoque(cliente, dono, m["id"])) == (901, 3)
    assert cliente.post(f"/api/impressoes/{i['id']}/reabrir", headers=dono).status_code == 200
    assert cliente.post(f"/api/impressoes/{i['id']}/reabrir", headers=dono).status_code == 409  # já está aberta


def test_impressao_descartada_volta(cliente, dono):
    _, car, m, i = preparar(cliente, dono)
    cliente.post(f"/api/impressoes/{i['id']}/descartar", headers=dono)
    assert cliente.post(f"/api/impressoes/{i['id']}/reabrir", headers=dono).json()["status"] == "a_confirmar"
    assert confirmar(cliente, dono, i["id"], finalidade="teste", consumos=[{"carretel_id": car["id"], "gramas": 10}]).status_code == 200


def test_cancelado_reabre_e_estoque_fica_certo_em_qualquer_sequencia(cliente, dono):
    pid, iid, m = _pedido(cliente, dono, qtd=2)  # entregue: -2
    cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "cancelado"})
    assert _estoque(cliente, dono, m["id"]) == 0
    r = cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "produzindo"})
    assert r.status_code == 200 and _estoque(cliente, dono, m["id"]) == 0
    cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"status": "entregue", "entregue_em": "2026-11-12T15:00:00Z"})
    assert _estoque(cliente, dono, m["id"]) == -2
    cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "cancelado"})
    assert _estoque(cliente, dono, m["id"]) == 0
    cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "entregue"})
    assert _estoque(cliente, dono, m["id"]) == -2


def test_data_da_venda_entregue_pode_ser_corrigida(cliente, dono):
    pid, _, _ = _pedido(cliente, dono)  # entregue em 04/11
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"entregue_em": "2026-10-05T15:00:00Z"})
    assert r.status_code == 200 and r.json()["entregue_em"].startswith("2026-10-05")
    assert cliente.get("/api/painel?inicio=2026-10-01&fim=2026-10-31", headers=dono).json()["receita"] == 40
    assert cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["receita"] == 0


def test_baixar_o_preco_abaixo_do_recebido_avisa_o_troco(cliente, dono):
    pid, iid, m = _pedido(cliente, dono)  # 40
    cliente.put(f"/api/pedidos/{pid}/pagamentos/{uuid.uuid4()}", headers=dono, json={"valor": 40})
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={
        "itens": [{"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": 2, "preco_unitario": 10}]})
    assert r.status_code == 200
    assert r.json()["excedente"] == 20 and "sobram R$ 20,00" in r.json()["avisos"][0]


def test_extrato_mostra_o_que_entrou_de_parcelas(cliente, dono):
    pid, _, _ = _pedido(cliente, dono)
    cliente.put(f"/api/pedidos/{pid}/pagamentos/{uuid.uuid4()}", headers=dono,
                json={"valor": 15, "data": "2026-11-06T15:00:00Z"})
    e = cliente.get("/api/extrato?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    assert (e["entrou"], e["recebido_parcelas"]) == (40, 15)


def test_movimento_manual_apagado_nao_volta_pelo_reenvio(cliente, dono):
    i = str(uuid.uuid4())
    cliente.put(f"/api/insumos/{i}", headers=dono, json={"nome": "Argola", "custo_unitario": 0.3})
    mid = str(uuid.uuid4())
    corpo = {"item_tipo": "insumo", "item_id": i, "tipo": "compra", "quantidade": 100, "valor": 30}
    cliente.put(f"/api/movimentos/{mid}", headers=dono, json=corpo)
    cliente.delete(f"/api/movimentos/{mid}", headers=dono)
    cliente.put(f"/api/movimentos/{mid}", headers=dono, json=corpo)
    assert cliente.get(f"/api/insumos/{i}", headers=dono).json()["saldo"] == 0

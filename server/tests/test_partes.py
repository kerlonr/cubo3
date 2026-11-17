"""Item de várias peças impressas separadas (fidget = case + keycap): estoque e custo real por unidade."""
import uuid

from test_catalogo import criar_modelo
from test_estoque import criar_carretel, criar_filamento
from test_impressoes import confirmar
from test_pix_pagamentos import PIX


def _fidget(cliente, h):
    imp = cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h, json={"nome": "V3"}).json()
    f = criar_filamento(cliente, h)
    car = criar_carretel(cliente, h, f["id"])
    sw = str(uuid.uuid4())
    cliente.put(f"/api/insumos/{sw}", headers=h, json={"nome": "Switch", "custo_unitario": 1.5})
    m = criar_modelo(cliente, h, receita={
        "filamentos": [{"filamento_id": f["id"], "gramas": 20, "nome": "Case", "horas": 2},
                       {"filamento_id": f["id"], "gramas": 13, "nome": "Keycap", "horas": 1}],
        "horas": 3, "mao_obra_min": 10, "insumos": [{"insumo_id": sw, "qtd": 1}]})
    return imp, car, m, sw


def _imprimir(cliente, h, imp, horas=1):
    return cliente.put(f"/api/impressoes/{uuid.uuid4()}", headers=h, json={
        "impressora_id": imp["id"], "arquivo": "x.gcode", "duracao_s": int(horas * 3600)}).json()


def _modelo(cliente, h, m):
    return cliente.get(f"/api/modelos/{m['id']}", headers=h).json()


def _saldo_insumo(cliente, h, i):
    return cliente.get(f"/api/insumos/{i}", headers=h).json()["saldo"]


def test_cada_peca_sozinha_nao_vira_item_e_as_duas_viram_um(cliente, dono):
    imp, car, m, sw = _fidget(cliente, dono)
    case = _imprimir(cliente, dono, imp, 2)
    r = confirmar(cliente, dono, case["id"], finalidade="venda", pecas_boas=1, modelo_id=m["id"], parte=0,
                  consumos=[{"carretel_id": car["id"], "gramas": 22}])  # gastou 2 g a mais que o catálogo
    assert r.status_code == 200, r.text
    assert (_modelo(cliente, dono, m)["estoque"], _saldo_insumo(cliente, dono, sw)) == (0, 0)
    keycap = _imprimir(cliente, dono, imp, 1)
    confirmar(cliente, dono, keycap["id"], finalidade="venda", pecas_boas=1, modelo_id=m["id"], parte=1,
              consumos=[{"carretel_id": car["id"], "gramas": 13}])
    mod = _modelo(cliente, dono, m)
    assert (mod["estoque"], _saldo_insumo(cliente, dono, sw)) == (1, -1)
    # real = gramas reais (35 g, sem os 10% de perda do catálogo) + 3 h de máquina + 10 min + switch
    assert abs(mod["custo_real"] - (mod["custo"]["total"] - 0.33 + 0.22)) < 0.02  # catálogo − 10% de 33 g + 2 g a mais


def test_reabrir_uma_peca_tira_a_unidade_montada(cliente, dono):
    imp, car, m, sw = _fidget(cliente, dono)
    ids = []
    for parte in (0, 1):
        i = _imprimir(cliente, dono, imp)
        confirmar(cliente, dono, i["id"], finalidade="venda", pecas_boas=1, modelo_id=m["id"], parte=parte,
                  consumos=[{"carretel_id": car["id"], "gramas": 10}])
        ids.append(i["id"])
    assert _modelo(cliente, dono, m)["estoque"] == 1
    cliente.post(f"/api/impressoes/{ids[1]}/reabrir", headers=dono)
    assert (_modelo(cliente, dono, m)["estoque"], _saldo_insumo(cliente, dono, sw)) == (0, 0)
    confirmar(cliente, dono, ids[1], finalidade="venda", pecas_boas=1, modelo_id=m["id"], parte=1,
              consumos=[{"carretel_id": car["id"], "gramas": 10}])
    assert (_modelo(cliente, dono, m)["estoque"], _saldo_insumo(cliente, dono, sw)) == (1, -1)


def test_mesa_com_varias_de_uma_peca_monta_o_minimo(cliente, dono):
    imp, car, m, _ = _fidget(cliente, dono)
    a = _imprimir(cliente, dono, imp)
    confirmar(cliente, dono, a["id"], finalidade="venda", pecas_boas=6, modelo_id=m["id"], parte=0,
              consumos=[{"carretel_id": car["id"], "gramas": 120}])  # 6 cases numa mesa
    b = _imprimir(cliente, dono, imp)
    confirmar(cliente, dono, b["id"], finalidade="venda", pecas_boas=4, modelo_id=m["id"], parte=1,
              consumos=[{"carretel_id": car["id"], "gramas": 52}])  # 4 keycaps
    assert _modelo(cliente, dono, m)["estoque"] == 4


def test_item_inteiro_continua_como_antes(cliente, dono):
    imp, car, m, sw = _fidget(cliente, dono)
    i = _imprimir(cliente, dono, imp, 3)
    confirmar(cliente, dono, i["id"], finalidade="venda", pecas_boas=1, modelo_id=m["id"],
              consumos=[{"carretel_id": car["id"], "gramas": 33}])
    assert (_modelo(cliente, dono, m)["estoque"], _saldo_insumo(cliente, dono, sw)) == (1, -1)
    assert confirmar(cliente, dono, _imprimir(cliente, dono, imp)["id"], finalidade="venda", pecas_boas=1,
                     modelo_id=m["id"], parte=5).status_code == 422


def test_cobranca_traz_a_chave_legivel(cliente, dono):
    cliente.put("/api/empresa/pix", headers=dono, json=PIX)
    r = cliente.post("/api/pix/cobranca", headers=dono, json={"valor": 45}).json()
    assert (r["tipo"], r["chave"]) == ("cpf", "529.982.247-25")

import uuid
from decimal import Decimal

from test_catalogo import criar_modelo
from test_estoque import criar_carretel, criar_filamento, saldo


def preparar(cliente, h):
    imp = cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h, json={"nome": "V3"}).json()
    f = criar_filamento(cliente, h)
    car = criar_carretel(cliente, h, f["id"])
    m = criar_modelo(cliente, h, receita={"filamentos": [{"filamento_id": f["id"], "gramas": 33}],
                                          "horas": 3, "mao_obra_min": 10})
    i = uuid.uuid4()
    r = cliente.put(f"/api/impressoes/{i}", headers=h, json={
        "impressora_id": imp["id"], "arquivo": "vaso_PLA_3h.gcode", "duracao_s": 10800})
    assert r.status_code == 200, r.text
    assert (r.json()["status"], r.json()["origem"]) == ("a_confirmar", "manual")
    return imp, car, m, r.json()


def confirmar(cliente, h, imp_id, **dados):
    return cliente.post(f"/api/impressoes/{imp_id}/confirmar", headers=h, json=dados)


def test_confirmar_gera_custo_e_estoque(cliente, dono, db, empresa_a_id):
    from app.estoque.servico import custo_medio_peca
    _, car, m, i = preparar(cliente, dono)
    r = confirmar(cliente, dono, i["id"], finalidade="venda", pecas_boas=1, modelo_id=m["id"],
                  consumos=[{"carretel_id": car["id"], "gramas": 33}])
    assert r.status_code == 200, r.text
    assert (r.json()["status"], r.json()["custo_total"], r.json()["custo_unitario"]) == ("confirmada", 5.99, 5.99)
    assert saldo(cliente, dono, car["id"]) == 967
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == 1
    assert round(custo_medio_peca(db, empresa_a_id, uuid.UUID(m["id"])), 2) == Decimal("5.99")


def test_perda_entra_no_custo_e_no_estoque(cliente, dono):
    _, car, m, i = preparar(cliente, dono)
    r = confirmar(cliente, dono, i["id"], finalidade="venda", pecas_boas=1, modelo_id=m["id"],
                  consumos=[{"carretel_id": car["id"], "gramas": 33}], perdas=[{"carretel_id": car["id"], "gramas": 10}])
    assert r.json()["custo_total"] == 6.99
    assert saldo(cliente, dono, car["id"]) == 957


def test_confirmar_duas_vezes(cliente, dono):
    _, car, m, i = preparar(cliente, dono)
    dados = dict(finalidade="venda", pecas_boas=1, modelo_id=m["id"], consumos=[{"carretel_id": car["id"], "gramas": 33}])
    primeira = confirmar(cliente, dono, i["id"], **dados).json()
    segunda = confirmar(cliente, dono, i["id"], **{**dados, "consumos": [{"carretel_id": car["id"], "gramas": 99}]})
    assert segunda.status_code == 200 and segunda.json()["custo_total"] == primeira["custo_total"]
    assert saldo(cliente, dono, car["id"]) == 967
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == 1


def test_finalidade_teste_nao_gera_peca(cliente, dono):
    _, car, m, i = preparar(cliente, dono)
    confirmar(cliente, dono, i["id"], finalidade="teste", pecas_boas=1, modelo_id=m["id"],
              consumos=[{"carretel_id": car["id"], "gramas": 33}])
    assert saldo(cliente, dono, car["id"]) == 967
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == 0


def test_descartar_sem_movimentos(cliente, dono):
    _, car, _, i = preparar(cliente, dono)
    r = cliente.post(f"/api/impressoes/{i['id']}/descartar", headers=dono)
    assert r.json()["status"] == "descartada"
    assert saldo(cliente, dono, car["id"]) == 1000
    pend = cliente.get("/api/impressoes", headers=dono, params={"status": "a_confirmar"}).json()
    assert pend == []


def test_aprende_nome_do_arquivo(cliente, dono, db, empresa_a_id):
    from app.impressoes.servico import casar_modelo
    _, car, m, i = preparar(cliente, dono)
    assert casar_modelo(db, empresa_a_id, "vaso_PLA_3h.gcode") is None
    confirmar(cliente, dono, i["id"], finalidade="pessoal", modelo_id=m["id"],
              consumos=[{"carretel_id": car["id"], "gramas": 33}])
    db.expire_all()
    assert casar_modelo(db, empresa_a_id, "vaso_PLA_3h.gcode") == uuid.UUID(m["id"])


def test_carretel_de_outra_empresa_404(cliente, dono, outro):
    _, car, _, _ = preparar(cliente, dono)
    _, _, _, i_b = preparar(cliente, outro)
    r = confirmar(cliente, outro, i_b["id"], finalidade="pessoal", consumos=[{"carretel_id": car["id"], "gramas": 33}])
    assert r.status_code == 404
    assert saldo(cliente, dono, car["id"]) == 1000
    assert cliente.get(f"/api/impressoes/{i_b['id']}", headers=outro).json()["status"] == "a_confirmar"

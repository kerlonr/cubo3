import uuid

from test_estoque import criar_filamento
from test_impressoes import confirmar, preparar
from test_vendas import item, produzir, venda


def painel(cliente, h, **p):
    r = cliente.get("/api/painel", headers=h, params=p)
    assert r.status_code == 200, r.text
    return r.json()


def test_painel_numeros(cliente, dono):
    _, car, m, imp = preparar(cliente, dono)  # carretel de R$ 100 comprado hoje
    confirmar(cliente, dono, imp["id"], finalidade="teste", consumos=[{"carretel_id": car["id"], "gramas": 33}])
    produzir(cliente, dono, m["id"])
    venda(cliente, dono, [item(m["id"])])
    from datetime import datetime
    from zoneinfo import ZoneInfo
    hoje = datetime.now(ZoneInfo("America/Sao_Paulo")).date().isoformat()
    assert cliente.put(f"/api/despesas/{uuid.uuid4()}", headers=dono,
                       json={"data": hoje, "categoria": "energia", "valor": 50}).status_code == 200
    p = painel(cliente, dono)
    assert (p["receita"], p["gastos"], p["resultado"], p["lucro_vendas"]) == (25.28, 150, -124.72, 7.64)
    assert (p["horas_impressao"], p["kg_filamento"]) == (3.0, 0.033)
    assert p["mais_vendidos"] == [{"modelo_id": m["id"], "nome": "Vaso", "qtd": 2}]
    assert p["por_mes"][-1] == {"mes": hoje[:7], "receita": 25.28, "gastos": 150}


def test_virada_de_mes_no_fuso(cliente, dono):
    from test_catalogo import criar_modelo
    m = criar_modelo(cliente, dono)
    venda(cliente, dono, [item(m["id"], qtd=1, preco=10)], custo_envio=0, entregue_em="2026-11-01T02:30:00Z")
    assert painel(cliente, dono, inicio="2026-10-01", fim="2026-10-31")["receita"] == 10
    assert painel(cliente, dono, inicio="2026-11-01", fim="2026-11-30")["receita"] == 0


def test_a_confirmar_ignora_arquivadas(cliente, dono, db):
    from app.impressoes.modelos import Impressao
    _, _, _, imp = preparar(cliente, dono)
    assert painel(cliente, dono)["a_confirmar"] == 1
    db.get(Impressao, uuid.UUID(imp["id"])).status = "arquivada"
    db.commit()
    assert painel(cliente, dono)["a_confirmar"] == 0


def test_por_mes_tem_12_meses(cliente, dono):
    p = painel(cliente, dono, inicio="2026-03-01", fim="2026-03-31")
    meses = [x["mes"] for x in p["por_mes"]]
    assert len(meses) == 12 and meses[0] == "2025-04" and meses[-1] == "2026-03"


def test_estoque_baixo(cliente, dono):
    criar_filamento(cliente, dono, estoque_minimo_g=500)
    baixo = painel(cliente, dono)["estoque_baixo"]
    assert [(b["tipo"], b["saldo"]) for b in baixo] == [("filamento", 0)]


def test_despesa_outra_empresa(cliente, dono, outro):
    cliente.put(f"/api/despesas/{uuid.uuid4()}", headers=dono, json={"data": "2026-11-02", "categoria": "outros", "valor": 50})
    assert painel(cliente, outro, inicio="2026-11-01", fim="2026-11-30")["gastos"] == 0

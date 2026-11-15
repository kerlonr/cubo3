"""Aviso ao vivo de escrita, comprovantes do pedido, preço editável na venda entregue e peças por impressão."""
import uuid

import pytest

from test_catalogo import criar_modelo
from test_estoque import criar_filamento


@pytest.fixture
def avisos(monkeypatch):
    import app.main
    recebidos = []
    monkeypatch.setattr(app.main.hub, "publicar", lambda empresa, ev: recebidos.append((empresa, ev)))
    return recebidos


def test_escrita_avisa_a_empresa_e_leitura_nao(cliente, dono, empresa_a_id, avisos):
    cliente.put(f"/api/despesas/{uuid.uuid4()}", headers=dono, json={"data": "2026-11-05", "valor": 10})
    cliente.get("/api/despesas", headers=dono)
    cliente.post("/api/calculadora", headers=dono, json={"horas": 1})
    assert [(e, ev["tipo"], ev["caminho"].split("/")[2]) for e, ev in avisos] == [(empresa_a_id, "dados", "despesas")]


def test_escrita_recusada_nao_avisa(cliente, dono, outro, avisos):
    d = str(uuid.uuid4())
    cliente.put(f"/api/despesas/{d}", headers=dono, json={"data": "2026-11-05", "valor": 10})
    avisos.clear()
    assert cliente.delete(f"/api/despesas/{d}", headers=outro).status_code == 404
    assert cliente.put(f"/api/despesas/{uuid.uuid4()}", headers=dono, json={"valor": -1}).status_code == 422
    assert avisos == []


def _pedido_entregue(cliente, h, preco=20, qtd=2):
    m = criar_modelo(cliente, h, preco_venda=preco)
    pid, iid = str(uuid.uuid4()), str(uuid.uuid4())
    r = cliente.put(f"/api/pedidos/{pid}", headers=h, json={
        "status": "entregue", "entregue_em": "2026-11-04T15:00:00Z",
        "itens": [{"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": qtd, "preco_unitario": preco}]})
    assert r.status_code == 200, r.text
    return pid, iid, m


def test_venda_entregue_aceita_novo_preco_e_recalcula(cliente, dono):
    pid, iid, m = _pedido_entregue(cliente, dono)
    estoque_antes = cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"]
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={
        "itens": [{"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": 2, "preco_unitario": 22.5}],
        "desconto": 5})
    assert r.status_code == 200, r.text
    p = r.json()
    assert (p["bruto"], p["receita"], p["lucro"]) == (45, 40, 40)  # custo 0 (modelo sem receita), sem canal
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == estoque_antes
    assert cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["receita"] == 40


def test_venda_entregue_nao_muda_quantidade_nem_itens(cliente, dono):
    pid, iid, m = _pedido_entregue(cliente, dono)
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={
        "itens": [{"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": 3, "preco_unitario": 20}]})
    assert r.status_code == 409


def test_venda_cancelada_nao_muda_preco(cliente, dono):
    pid, iid, m = _pedido_entregue(cliente, dono)
    cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "cancelado"})
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={
        "itens": [{"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": 2, "preco_unitario": 1}]})
    assert r.status_code == 409


def test_comprovante_anexar_ver_e_apagar(cliente, dono, outro):
    pid, _, _ = _pedido_entregue(cliente, dono)
    r = cliente.post(f"/api/pedidos/{pid}/anexos", headers=dono,
                     files={"arquivo": ("pix.jpg", b"jpeg-falso", "image/jpeg")})
    assert r.status_code == 200, r.text
    a = r.json()
    assert (a["tipo"], a["tamanho"]) == ("foto", 10)
    assert cliente.get(f"/api/pedidos/{pid}", headers=dono).json()["anexos"][0]["id"] == a["id"]
    assert cliente.get(a["url"], headers=dono).content == b"jpeg-falso"
    assert cliente.get(a["url"], headers=outro).status_code == 404
    assert cliente.post(f"/api/pedidos/{pid}/anexos", headers=outro,
                        files={"arquivo": ("x.pdf", b"%PDF", "application/pdf")}).status_code == 404
    assert cliente.post(f"/api/pedidos/{pid}/anexos", headers=dono,
                        files={"arquivo": ("x.exe", b"MZ", "application/octet-stream")}).status_code == 415
    assert cliente.delete(f"/api/anexos/{a['id']}", headers=outro).status_code == 404
    assert cliente.delete(f"/api/anexos/{a['id']}", headers=dono).status_code == 200
    assert cliente.get(f"/api/pedidos/{pid}", headers=dono).json()["anexos"] == []


def test_pecas_por_impressao_divide_material_e_maquina(cliente, dono):
    f = criar_filamento(cliente, dono)
    receita = {"filamentos": [{"filamento_id": f["id"], "gramas": 33 * 6}], "horas": 18, "mao_obra_min": 10}
    uma = criar_modelo(cliente, dono, receita={"filamentos": [{"filamento_id": f["id"], "gramas": 33}],
                                               "horas": 3, "mao_obra_min": 10})
    mesa = criar_modelo(cliente, dono, receita={**receita, "pecas_por_impressao": 6})
    assert mesa["custo"]["total"] == uma["custo"]["total"] == 6.32
    assert mesa["receita"]["pecas_por_impressao"] == 6
    calc = cliente.post("/api/calculadora", headers=dono, json={
        "filamentos": [{"preco_kg": 100, "gramas": 198}], "horas": 18, "mao_obra_min": 10, "pecas_por_impressao": 6})
    assert calc.json()["custo"]["total"] == 6.32
    sem = criar_modelo(cliente, dono, receita=receita)  # receita antiga: sem o campo vale 1
    assert sem["custo"]["total"] == 29.59

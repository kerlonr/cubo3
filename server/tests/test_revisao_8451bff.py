"""Revisão do commit 8451bff: dados antigos, dinheiro e isolamento nas rotas novas."""
import uuid

from test_catalogo import criar_modelo, enviar
from test_estoque import criar_carretel, criar_filamento

PLANILHA = {"horas": 3, "mao_obra_min": 10}


def test_receita_antiga_com_insumo_excluido_mantem_o_custo(cliente, dono):
    """Receita salva antes do commit: só insumo_id/qtd, sem preço copiado. Antes o servidor contava o insumo
    mesmo excluído; agora ele vira R$ 0 e o custo do modelo (e do pedido entregue depois) cai em silêncio."""
    i = str(uuid.uuid4())
    cliente.put(f"/api/insumos/{i}", headers=dono, json={"nome": "Switch", "custo_unitario": 2})
    m = criar_modelo(cliente, dono, receita={**PLANILHA, "filamentos": [{"preco_kg": 100, "gramas": 33}],
                                             "insumos": [{"insumo_id": i, "qtd": 1}]})
    assert m["custo"]["total"] == 8.32
    cliente.delete(f"/api/insumos/{i}", headers=dono)
    depois = cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["custo"]["total"]
    assert depois == 8.32, f"custo mudou sozinho: {depois}"


def test_filamento_excluido_servidor_conta_preco(cliente, dono):
    """Servidor usa o preço do filamento excluído; o app (lista sem excluídos) usa 0. Ver teste do app."""
    f = criar_filamento(cliente, dono)
    m = criar_modelo(cliente, dono, receita={**PLANILHA, "filamentos": [{"filamento_id": f["id"], "gramas": 33}]})
    cliente.delete(f"/api/filamentos/{f['id']}", headers=dono)
    assert f["id"] not in [x["id"] for x in cliente.get("/api/filamentos", headers=dono).json()]
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["custo"]["total"] == 6.32


def test_extrato_e_painel_arredondam_diferente(cliente, dono):
    """Extrato arredonda cada linha e soma; painel soma e arredonda: centavos de diferença."""
    i = str(uuid.uuid4())
    cliente.put(f"/api/insumos/{i}", headers=dono, json={"nome": "Argola", "custo_unitario": 0.3})
    for _ in range(2):
        cliente.put(f"/api/movimentos/{uuid.uuid4()}", headers=dono, json={
            "item_tipo": "insumo", "item_id": i, "tipo": "compra", "quantidade": 1, "valor": "10.005",
            "data": "2026-11-02T12:00:00Z"})
    e = cliente.get("/api/extrato?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    p = cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    assert e["saiu"] == p["gastos"], (e["saiu"], p["gastos"])


def test_delete_movimento_de_outra_empresa_e_de_origem(cliente, dono, outro):
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"])
    aj = str(uuid.uuid4())
    cliente.put(f"/api/movimentos/{aj}", headers=dono, json={
        "item_tipo": "carretel", "item_id": car["id"], "tipo": "ajuste", "quantidade": -10})
    assert cliente.delete(f"/api/movimentos/{aj}", headers=outro).status_code == 404
    assert cliente.get(f"/api/carreteis/{car['id']}", headers=dono).json()["saldo_g"] == 990
    assert cliente.delete(f"/api/movimentos/{aj}", headers=dono).status_code == 200
    assert cliente.delete(f"/api/movimentos/{aj}", headers=dono).status_code == 200  # repetido: idempotente
    # reenvio do PUT original (fila) não ressuscita o movimento
    cliente.put(f"/api/movimentos/{aj}", headers=dono, json={
        "item_tipo": "carretel", "item_id": car["id"], "tipo": "ajuste", "quantidade": -10})
    assert cliente.get(f"/api/carreteis/{car['id']}", headers=dono).json()["saldo_g"] == 1000


def test_extrato_nao_mostra_nada_de_outra_empresa(cliente, dono, outro):
    f = criar_filamento(cliente, outro)
    criar_carretel(cliente, outro, f["id"])
    m = criar_modelo(cliente, outro, preco_venda=20)
    cliente.put(f"/api/pedidos/{uuid.uuid4()}", headers=outro, json={
        "status": "entregue", "entregue_em": "2026-11-04T15:00:00Z",
        "itens": [{"id": str(uuid.uuid4()), "modelo_id": m["id"], "descricao": "Vaso", "quantidade": 1,
                   "preco_unitario": 20}]})
    e = cliente.get("/api/extrato?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    assert (e["linhas"], e["entrou"], e["saiu"], e["perdas_g"]) == ([], 0, 0, 0)


def test_capa_de_outra_empresa_e_editar_carretel_de_outra(cliente, dono, outro):
    m = criar_modelo(cliente, dono)
    mb = criar_modelo(cliente, outro)
    foto_b = enviar(cliente, outro, mb["id"], "b.png", b"png").json()
    assert cliente.put(f"/api/modelos/{m['id']}", headers=dono, json={"capa_id": foto_b["id"]}).status_code == 422
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"], preco=100)
    assert cliente.put(f"/api/carreteis/{car['id']}", headers=outro, json={"preco_pago": 1}).status_code == 404
    assert cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["gastos"] == 100


def test_carretel_usado_nao_se_exclui_e_o_gasto_fica(cliente, dono):
    """Carretel já usado: excluir é recusado (o gasto aconteceu); arquivar é o caminho."""
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"], preco=100)
    cliente.put(f"/api/movimentos/{uuid.uuid4()}", headers=dono, json={
        "item_tipo": "carretel", "item_id": car["id"], "tipo": "consumo", "quantidade": -900})
    assert cliente.delete(f"/api/carreteis/{car['id']}", headers=dono).status_code == 409
    p = cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    assert (p["gastos"], p["kg_filamento"]) == (100, 0.9)

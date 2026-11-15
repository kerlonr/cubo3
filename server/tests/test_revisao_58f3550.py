"""Revisão do 58f3550: preço editável na venda entregue, comprovantes e peças por impressão."""
import uuid

from test_ao_vivo_anexos import _pedido_entregue
from test_catalogo import criar_modelo
from test_estoque import criar_carretel, criar_filamento
from test_impressoes import confirmar


def _item(iid, m, preco, qtd=2):
    return {"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": qtd, "preco_unitario": preco}


def test_taxas_do_canal_ficam_congeladas_ao_editar_preco(cliente, dono):
    canal = str(uuid.uuid4())
    cliente.put(f"/api/canais/{canal}", headers=dono, json={"nome": "Shopee", "taxa_pct": 10, "taxa_fixa": 1})
    m = criar_modelo(cliente, dono, preco_venda=20)
    pid, iid = str(uuid.uuid4()), str(uuid.uuid4())
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={
        "canal_id": canal, "status": "entregue", "itens": [_item(iid, m, 20)]})
    assert r.json()["taxas"] == 5  # 40 * 10% + 1
    cliente.put(f"/api/canais/{canal}", headers=dono, json={"taxa_pct": 50, "taxa_fixa": 9})
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(iid, m, 30)]})
    assert r.status_code == 200, r.text
    assert (r.json()["bruto"], r.json()["taxas"], r.json()["lucro"]) == (60, 7, 53)


def test_lucro_por_modelo_segue_o_preco_editado(cliente, dono, db, empresa_a_id):
    from app.vendas.servico import vendidos_por_modelo
    pid, iid, m = _pedido_entregue(cliente, dono)
    cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(iid, m, 25)]})
    db.expire_all()
    assert vendidos_por_modelo(db, empresa_a_id)[uuid.UUID(m["id"])] == (2, 50)


def test_desconto_maior_que_o_total_e_recusado(cliente, dono):
    pid, iid, m = _pedido_entregue(cliente, dono)  # 2 x 20 = 40
    assert cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"desconto": 100}).status_code == 422
    assert cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["receita"] == 40


def test_versao_base_conferida_no_pedido(cliente, dono):
    """Reenvio atrasado com versão velha não desfaz o preço que outro aparelho corrigiu."""
    pid, iid, m = _pedido_entregue(cliente, dono)
    lido = cliente.get(f"/api/pedidos/{pid}", headers=dono).json()["atualizado_em"]
    cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(iid, m, 30)]})  # outro aparelho
    r = cliente.put(f"/api/pedidos/{pid}", headers={**dono, "X-Versao-Base": lido},
                    json={"itens": [_item(iid, m, 21)]})
    assert r.status_code == 409
    assert cliente.get(f"/api/pedidos/{pid}", headers=dono).json()["bruto"] == 60
    mesma = cliente.put(f"/api/pedidos/{pid}", headers={**dono, "X-Versao-Base": lido},
                        json={"itens": [_item(iid, m, 30)]})  # reenvio da mesma edição: aceito
    assert mesma.status_code == 200


def test_canal_trocado_em_entregue_e_ignorado_sem_aviso(cliente, dono):
    canal = str(uuid.uuid4())
    cliente.put(f"/api/canais/{canal}", headers=dono, json={"nome": "ML", "taxa_pct": 20})
    pid, iid, m = _pedido_entregue(cliente, dono)
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"canal_id": canal})
    assert r.status_code == 200 and r.json()["canal_id"] is None


def test_item_repetido_em_entregue_passa_e_o_ultimo_preco_vence(cliente, dono):
    pid, iid, m = _pedido_entregue(cliente, dono)
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(iid, m, 99), _item(iid, m, 25)]})
    assert r.status_code == 200 and r.json()["bruto"] == 50


def test_comprovante_apagado_nao_baixa(cliente, dono):
    pid, _, _ = _pedido_entregue(cliente, dono)
    a = cliente.post(f"/api/pedidos/{pid}/anexos", headers=dono,
                     files={"arquivo": ("pix.jpg", b"jpeg", "image/jpeg")}).json()
    assert cliente.delete(f"/api/anexos/{a['id']}", headers=dono).status_code == 200
    assert cliente.get(a["url"], headers=dono).status_code == 404


def test_comprovante_em_pedido_excluido_e_recusado(cliente, dono):
    pid = str(uuid.uuid4())
    cliente.put(f"/api/pedidos/{pid}", headers=dono, json={})
    assert cliente.delete(f"/api/pedidos/{pid}", headers=dono).status_code == 200
    r = cliente.post(f"/api/pedidos/{pid}/anexos", headers=dono, files={"arquivo": ("p.pdf", b"%PDF", "application/pdf")})
    assert r.status_code == 404


def test_mesa_de_6_confirmada_conta_mao_de_obra_por_peca(cliente, dono):
    """Mão de obra da receita é por peça nos dois. Sobra só a eficiência (10% de perda no catálogo, gramas
    reais na confirmação): 6,32 - 0,33 = 5,99."""
    imp = cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=dono, json={"nome": "V3"}).json()
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"])
    m = criar_modelo(cliente, dono, receita={"filamentos": [{"filamento_id": f["id"], "gramas": 198}],
                                             "horas": 18, "mao_obra_min": 10, "pecas_por_impressao": 6})
    i = cliente.put(f"/api/impressoes/{uuid.uuid4()}", headers=dono, json={
        "impressora_id": imp["id"], "arquivo": "chaveiros.gcode", "duracao_s": 18 * 3600}).json()
    r = confirmar(cliente, dono, i["id"], finalidade="venda", pecas_boas=6, modelo_id=m["id"],
                  consumos=[{"carretel_id": car["id"], "gramas": 198}])
    assert r.status_code == 200, r.text
    assert m["custo"]["total"] == 6.32
    assert r.json()["custo_unitario"] == 5.99, r.json()["custo_unitario"]

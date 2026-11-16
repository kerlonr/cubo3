"""Pix da empresa (só o dono vê a chave), cobrança copia e cola, parcelas e venda entregue editável."""
import uuid
from decimal import Decimal

import pytest

from app.pix import copia_e_cola, crc16, normalizar_chave
from test_catalogo import criar_modelo

PIX = {"tipo": "cpf", "chave": "529.982.247-25", "nome": "Kerlon Ribeiro", "cidade": "Passo Fundo"}


def test_br_code_do_manual_do_banco_central():
    assert copia_e_cola("123e4567-e12b-12d1-a456-426655440000", "Fulano de Tal", "BRASILIA") == (
        "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR"
        "5913Fulano de Tal6008BRASILIA62070503***63041D3D")


def test_br_code_com_valor_e_acentos():
    c = copia_e_cola("52998224725", "João Ação", "São José", Decimal("45"), "CUBO3ABC")
    assert "540545.00" in c and "5909Joao Acao" in c and "6008Sao Jose" in c
    assert c[-4:] == crc16(c[:-4])


@pytest.mark.parametrize("tipo,chave,esperado", [
    ("cpf", "529.982.247-25", "52998224725"), ("cnpj", "11.222.333/0001-81", "11222333000181"),
    ("email", " Kerlon@Exemplo.com ", "kerlon@exemplo.com"), ("telefone", "(54) 99999-8888", "+5554999998888"),
    ("aleatoria", "123E4567-E12B-12D1-A456-426655440000", "123e4567-e12b-12d1-a456-426655440000")])
def test_chave_normalizada(tipo, chave, esperado):
    assert normalizar_chave(tipo, chave) == esperado


@pytest.mark.parametrize("tipo,chave", [("cpf", "111.111.111-11"), ("cpf", "529.982.247-26"), ("cnpj", "11.222.333/0001-80"),
                                        ("email", "sem-arroba"), ("telefone", "123"), ("aleatoria", "abc")])
def test_chave_invalida(tipo, chave):
    with pytest.raises(ValueError):
        normalizar_chave(tipo, chave)


def test_so_o_dono_grava_e_ve_a_chave_inteira(cliente, dono, membro, outro):
    assert cliente.put("/api/empresa/pix", headers=membro, json=PIX).status_code == 403
    r = cliente.put("/api/empresa/pix", headers=dono, json=PIX)
    assert r.status_code == 200, r.text
    assert r.json()["chave"] == "52998224725" and r.headers["cache-control"] == "no-store"
    m = cliente.get("/api/empresa/pix", headers=membro).json()
    assert "chave" not in m and m["chave_mascarada"].startswith("529") and "998224" not in m["chave_mascarada"]
    assert cliente.get("/api/empresa/pix", headers=outro).json() == {"configurado": False}
    # O config vai para todo membro e fica no cache do aparelho: a chave não pode estar lá.
    assert "52998224725" not in cliente.get("/api/empresa/config", headers=membro).text
    assert cliente.put("/api/empresa/pix", headers=dono, json={**PIX, "chave": "123"}).status_code == 422
    assert cliente.delete("/api/empresa/pix", headers=membro).status_code == 403
    assert cliente.delete("/api/empresa/pix", headers=dono).status_code == 200
    assert cliente.get("/api/empresa/pix", headers=dono).json() == {"configurado": False}


def _pedido(cliente, h, status="entregue", preco=20, qtd=2):
    m = criar_modelo(cliente, h, preco_venda=preco)
    pid, iid = str(uuid.uuid4()), str(uuid.uuid4())
    corpo = {"itens": [{"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": qtd, "preco_unitario": preco}]}
    if status == "entregue":
        corpo |= {"status": "entregue", "entregue_em": "2026-11-04T15:00:00Z"}
    r = cliente.put(f"/api/pedidos/{pid}", headers=h, json=corpo)
    assert r.status_code == 200, r.text
    return pid, iid, m


def test_cobranca_pix_com_o_que_falta(cliente, dono, membro, outro):
    pid, _, _ = _pedido(cliente, dono)
    assert cliente.post("/api/pix/cobranca", headers=dono, json={"pedido_id": pid}).status_code == 409  # sem Pix
    cliente.put("/api/empresa/pix", headers=dono, json=PIX)
    cliente.put(f"/api/pedidos/{pid}/pagamentos/{uuid.uuid4()}", headers=dono, json={"valor": 15, "forma": "Pix"})
    r = cliente.post("/api/pix/cobranca", headers=membro, json={"pedido_id": pid})
    assert r.status_code == 200, r.text
    assert r.json()["valor"] == 25 and "540525.00" in r.json()["copia_e_cola"]
    assert "52998224725" in r.json()["copia_e_cola"]  # o código leva a chave: é assim que o banco paga
    avulso = cliente.post("/api/pix/cobranca", headers=membro, json={"valor": 12.9}).json()
    assert "540512.90" in avulso["copia_e_cola"] and "62070503***" in avulso["copia_e_cola"]
    assert cliente.post("/api/pix/cobranca", headers=outro, json={"pedido_id": pid}).status_code == 409  # B sem Pix
    cliente.put("/api/empresa/pix", headers=outro, json=PIX)
    assert cliente.post("/api/pix/cobranca", headers=outro, json={"pedido_id": pid}).status_code == 404
    assert cliente.post("/api/pix/cobranca", headers=dono, json={"valor": 0}).status_code == 422


def test_parcelas_somam_e_quitam(cliente, dono):
    pid, _, _ = _pedido(cliente, dono)  # total 40
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    p = cliente.put(f"/api/pedidos/{pid}/pagamentos/{a}", headers=dono, json={"valor": 15, "forma": "Pix"}).json()
    assert (p["recebido"], p["saldo"], p["pago"]) == (15, 25, False)
    assert cliente.put(f"/api/pedidos/{pid}/pagamentos/{a}", headers=dono, json={"valor": 15, "forma": "Pix"}).json()["recebido"] == 15
    r = cliente.put(f"/api/pedidos/{pid}/pagamentos/{b}", headers=dono, json={"valor": 30})
    assert r.status_code == 422 and "25,00" in r.text
    p = cliente.put(f"/api/pedidos/{pid}/pagamentos/{b}", headers=dono, json={"valor": 25, "forma": "Dinheiro"}).json()
    assert (p["recebido"], p["saldo"], p["pago"], p["forma_pagamento"]) == (40, 0, True, "Dinheiro")
    p = cliente.delete(f"/api/pagamentos/{b}", headers=dono).json()
    assert (p["recebido"], p["pago"]) == (15, False)
    p = cliente.put(f"/api/pedidos/{pid}/pagamentos/{a}", headers=dono, json={"valor": 10}).json()  # corrigiu o valor
    assert p["recebido"] == 10 and len(p["pagamentos"]) == 1


def test_parcela_isolada_por_empresa_e_por_pedido(cliente, dono, outro):
    pid, _, _ = _pedido(cliente, dono)
    pid2, _, _ = _pedido(cliente, dono)
    x = str(uuid.uuid4())
    cliente.put(f"/api/pedidos/{pid}/pagamentos/{x}", headers=dono, json={"valor": 5})
    assert cliente.put(f"/api/pedidos/{pid}/pagamentos/{uuid.uuid4()}", headers=outro, json={"valor": 5}).status_code == 404
    assert cliente.put(f"/api/pedidos/{pid2}/pagamentos/{x}", headers=dono, json={"valor": 5}).status_code == 404
    assert cliente.delete(f"/api/pagamentos/{x}", headers=outro).status_code == 404


def test_pedido_antigo_marcado_pago_conta_inteiro(cliente, dono):
    pid, _, _ = _pedido(cliente, dono)
    p = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"pago": True}).json()
    assert (p["recebido"], p["saldo"]) == (40, 0)


def test_entregue_muda_quantidade_e_estoque_acompanha(cliente, dono):
    pid, iid, m = _pedido(cliente, dono, qtd=2)
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == -2
    novo = str(uuid.uuid4())
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [
        {"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": 6, "preco_unitario": 7.5},
        {"id": novo, "descricao": "Embalagem presente", "quantidade": 1, "preco_unitario": 5}]})
    assert r.status_code == 200, r.text
    assert (r.json()["bruto"], r.json()["status"], r.json()["entregue_em"][:10]) == (50, "entregue", "2026-11-04")
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == -6
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [
        {"id": novo, "descricao": "Embalagem presente", "quantidade": 1, "preco_unitario": 5}]})  # tirou o chaveiro
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == 0
    assert cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["receita"] == 5


def test_reabrir_entregue_devolve_estoque_e_entregar_de_novo_baixa(cliente, dono):
    pid, iid, m = _pedido(cliente, dono, qtd=2)
    r = cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "produzindo"})
    assert r.status_code == 200 and r.json()["receita"] is None
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == 0
    assert cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()["receita"] == 0
    cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"status": "entregue", "entregue_em": "2026-11-10T15:00:00Z"})
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == -2
    assert cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "cancelado"}).status_code == 200
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == 0


def test_item_repetido_recusado(cliente, dono):
    pid, iid, m = _pedido(cliente, dono)
    it = {"id": iid, "modelo_id": m["id"], "descricao": "Chaveiro", "quantidade": 2, "preco_unitario": 20}
    assert cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [it, it]}).status_code == 422

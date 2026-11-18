"""Venda bloqueada: depois de fechada ninguém altera mais nada nela."""
import uuid

from test_catalogo import criar_modelo
from test_vendas import canal, item, produzir, venda


def bloquear(cliente, h, pedido_id, bloqueado=True):
    return cliente.post(f"/api/pedidos/{pedido_id}/bloqueio", headers=h, json={"bloqueado": bloqueado})


def vender(cliente, dono):
    m = criar_modelo(cliente, dono)
    produzir(cliente, dono, m["id"], qtd=4)
    p = venda(cliente, dono, [item(m["id"])]).json()
    assert p["bloqueado"] is False
    return m, p


def test_bloqueada_recusa_toda_alteracao(cliente, dono):
    m, p = vender(cliente, dono)
    assert bloquear(cliente, dono, p["id"]).json()["bloqueado"] is True
    pid = p["id"]

    tentativas = [
        cliente.put(f"/api/pedidos/{pid}", headers=dono,
                    json={"canal_id": canal(cliente, dono), "status": "entregue", "itens": [item(m["id"], qtd=9)]}),
        cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "cancelado"}),
        cliente.put(f"/api/pedidos/{pid}/pagamentos/{uuid.uuid4()}", headers=dono, json={"valor": 1}),
        cliente.delete(f"/api/pedidos/{pid}", headers=dono),
    ]
    for r in tentativas:
        assert r.status_code == 409, r.text
        assert "bloqueada" in r.json()["detail"].lower()

    # Nada mudou: itens, status e estoque seguem como estavam.
    depois = cliente.get(f"/api/pedidos/{pid}", headers=dono).json()
    assert (depois["status"], depois["itens"][0]["quantidade"], depois["bloqueado"]) == ("entregue", 2.0, True)
    assert cliente.get(f"/api/modelos/{m['id']}", headers=dono).json()["estoque"] == 2


def test_pagamento_e_comprovante_de_venda_bloqueada(cliente, dono):
    m = criar_modelo(cliente, dono)
    produzir(cliente, dono, m["id"], qtd=2)
    p = venda(cliente, dono, [item(m["id"])], pago=False).json()
    pag = uuid.uuid4()
    assert cliente.put(f"/api/pedidos/{p['id']}/pagamentos/{pag}", headers=dono, json={"valor": 5}).status_code == 200
    anexo = cliente.post(f"/api/pedidos/{p['id']}/anexos", headers=dono,
                         files={"arquivo": ("pix.png", b"123", "image/png")}).json()
    bloquear(cliente, dono, p["id"])

    assert cliente.delete(f"/api/pagamentos/{pag}", headers=dono).status_code == 409
    assert cliente.delete(f"/api/anexos/{anexo['id']}", headers=dono).status_code == 409
    assert cliente.post(f"/api/pedidos/{p['id']}/anexos", headers=dono,
                        files={"arquivo": ("outro.png", b"123", "image/png")}).status_code == 409
    # O que já estava lá continua: o dinheiro recebido e o comprovante não somem.
    depois = cliente.get(f"/api/pedidos/{p['id']}", headers=dono).json()
    assert (depois["recebido"], len(depois["anexos"])) == (5.0, 1)
    # Cobrar no Pix continua valendo: não altera a venda.
    assert cliente.post("/api/pix/cobranca", headers=dono, json={"pedido_id": p["id"]}).status_code in (200, 409)


def test_so_o_dono_desbloqueia(cliente, dono, membro):
    _, p = vender(cliente, dono)
    assert bloquear(cliente, membro, p["id"]).status_code == 200, "qualquer um fecha a venda"
    r = bloquear(cliente, membro, p["id"], bloqueado=False)
    assert r.status_code == 403 and "dono" in r.json()["detail"]
    assert cliente.get(f"/api/pedidos/{p['id']}", headers=dono).json()["bloqueado"] is True

    assert bloquear(cliente, dono, p["id"], bloqueado=False).json()["bloqueado"] is False
    assert cliente.post(f"/api/pedidos/{p['id']}/status", headers=dono,
                        json={"status": "cancelado"}).status_code == 200, "desbloqueada, volta a editar"


def test_bloqueio_nao_vaza_entre_empresas(cliente, dono, outro):
    _, p = vender(cliente, dono)
    assert bloquear(cliente, outro, p["id"]).status_code == 404

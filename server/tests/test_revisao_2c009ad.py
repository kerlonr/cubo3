"""Revisão do commit 2c009ad: preço das impressões, parcelas, Pix e venda entregue editável.

Cada teste descreve o comportamento CORRETO; os que falham provam um bug.
"""
import uuid
from decimal import Decimal

from app.pix import copia_e_cola, crc16, normalizar_chave
from test_catalogo import criar_modelo
from test_estoque import criar_carretel, criar_filamento


def _impressora(cliente, h):
    return cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h, json={"nome": "V3"}).json()


def _impressao(cliente, h, imp_id, **extra):
    i = str(uuid.uuid4())
    r = cliente.put(f"/api/impressoes/{i}", headers=h, json={"impressora_id": imp_id, **extra})
    assert r.status_code == 200, r.text
    return i


def _confirmar(cliente, h, i, **dados):
    r = cliente.post(f"/api/impressoes/{i}/confirmar", headers=h, json=dados)
    assert r.status_code == 200, r.text
    return r.json()


def _vender(cliente, h, itens, **extra):
    pid = str(uuid.uuid4())
    r = cliente.put(f"/api/pedidos/{pid}", headers=h, json={
        "itens": itens, "status": "entregue", "entregue_em": "2026-11-04T15:00:00Z", **extra})
    assert r.status_code == 200, r.text
    return pid, r.json()


def _item(modelo_id, qtd=1, preco=20, id=None):
    return {"id": id or str(uuid.uuid4()), "modelo_id": modelo_id, "descricao": "x", "quantidade": qtd,
            "preco_unitario": preco}


# ---------------------------------------------------------------- preço das impressões

def test_planilha_no_catalogo_e_na_impressao(cliente, dono):
    """Catálogo: 6,32 (com 1,1). Impressão real com os mesmos 33 g: 5,99 (sem 1,1, como manda a spec)."""
    imp = _impressora(cliente, dono)
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"])
    m = criar_modelo(cliente, dono, receita={"filamentos": [{"filamento_id": f["id"], "gramas": 33}],
                                             "horas": 3, "mao_obra_min": 10})
    assert m["custo"]["total"] == 6.32
    i = _impressao(cliente, dono, imp["id"], duracao_s=10800)
    r = _confirmar(cliente, dono, i, finalidade="venda", pecas_boas=1, modelo_id=m["id"],
                   consumos=[{"carretel_id": car["id"], "gramas": 33}])
    assert r["custo_total"] == 5.99


def test_mesa_com_6_pecas_custo_por_peca_bate_com_catalogo(cliente, dono):
    """6 chaveiros na mesa: 60 g e 3 h da mesa inteira, 10 min de montagem por peça."""
    imp = _impressora(cliente, dono)
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"])
    m = criar_modelo(cliente, dono, receita={"filamentos": [{"filamento_id": f["id"], "gramas": 60}],
                                             "horas": 3, "mao_obra_min": 10, "pecas_por_impressao": 6})
    i = _impressao(cliente, dono, imp["id"], duracao_s=10800)
    r = _confirmar(cliente, dono, i, finalidade="venda", pecas_boas=6, modelo_id=m["id"],
                   consumos=[{"carretel_id": car["id"], "gramas": 60}])
    # catálogo por peça: 60*0,1*1,1/6=1,10 + 1,67 + 1,02/6=0,17 → 2,94; real sem 1,1: 1,00+1,67+0,17 = 2,84
    assert m["custo"]["total"] == 2.94
    assert r["custo_unitario"] == 2.84


def test_impressao_manual_sem_duracao_mas_com_inicio_e_fim_cobra_maquina(cliente, dono):
    """Impressão manual com início e fim e sem duracao_s: a máquina sai R$ 0 (lucro inflado)."""
    imp = _impressora(cliente, dono)
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"])
    m = criar_modelo(cliente, dono, receita={"filamentos": [{"filamento_id": f["id"], "gramas": 33}], "horas": 3})
    i = _impressao(cliente, dono, imp["id"], inicio="2026-11-04T10:00:00Z", fim="2026-11-04T13:00:00Z")
    r = _confirmar(cliente, dono, i, finalidade="venda", pecas_boas=1, modelo_id=m["id"],
                   consumos=[{"carretel_id": car["id"], "gramas": 33}])
    assert r["custo_total"] > 3.30 + 0.5, f"máquina não cobrada: {r['custo_total']}"


def test_producao_manual_sem_valor_dilui_custo_medio(cliente, dono, db, empresa_a_id):
    """Ajuste de estoque lançado como 'producao' sem valor (via /movimentos) puxa o custo médio para baixo."""
    from app.estoque.servico import custo_medio_peca
    imp = _impressora(cliente, dono)
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"])
    m = criar_modelo(cliente, dono, receita={"filamentos": [{"filamento_id": f["id"], "gramas": 33}], "horas": 3})
    i = _impressao(cliente, dono, imp["id"], duracao_s=10800)
    _confirmar(cliente, dono, i, finalidade="venda", pecas_boas=1, modelo_id=m["id"],
               consumos=[{"carretel_id": car["id"], "gramas": 33}])
    r = cliente.put(f"/api/movimentos/{uuid.uuid4()}", headers=dono, json={
        "item_tipo": "peca", "item_id": m["id"], "tipo": "producao", "quantidade": 9})
    if r.status_code != 200:
        return  # servidor recusou: sem bug
    medio = custo_medio_peca(db, empresa_a_id, uuid.UUID(m["id"]))
    assert medio > Decimal("1"), f"custo médio diluído para {medio:.4f} (era 4,32)"


def test_falhou_sem_pecas_nao_cobra_montagem(cliente, dono):
    """Falhou com 0 peças boas: a montagem por peça (receita) não aconteceu; hoje cobra 1 peça."""
    imp = _impressora(cliente, dono)
    m = criar_modelo(cliente, dono, receita={"horas": 0, "mao_obra_min": 60})
    i = _impressao(cliente, dono, imp["id"], duracao_s=0)
    r = _confirmar(cliente, dono, i, finalidade="falhou", pecas_boas=0, modelo_id=m["id"])
    assert r["custo_total"] == 0, f"falha cobrou montagem: {r['custo_total']}"


def test_confirmar_impressao_excluida(cliente, dono):
    """Impressão apagada (lixeira) ainda pode ser confirmada e baixar carretel."""
    imp = _impressora(cliente, dono)
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"])
    i = _impressao(cliente, dono, imp["id"], duracao_s=60)
    assert cliente.delete(f"/api/impressoes/{i}", headers=dono).status_code == 200
    r = cliente.post(f"/api/impressoes/{i}/confirmar", headers=dono, json={
        "finalidade": "pessoal", "consumos": [{"carretel_id": car["id"], "gramas": 10}]})
    assert r.status_code in (404, 409), r.text


# ---------------------------------------------------------------- custo na venda

def test_custo_envio_da_receita_conta_duas_vezes_sem_producao(cliente, dono):
    """Sem produção, o custo do item é o do catálogo, que já soma o envio da receita; o pedido soma o seu."""
    m = criar_modelo(cliente, dono, receita={"horas": 0, "mao_obra_min": 0, "custo_envio": 10})
    _, p = _vender(cliente, dono, [_item(m["id"], 1, 50)], custo_envio=10)
    assert p["lucro"] == 40, f"envio contado duas vezes: lucro {p['lucro']}"


def test_trocar_modelo_do_item_em_venda_entregue_atualiza_custo(cliente, dono):
    barato = criar_modelo(cliente, dono, receita={"mao_obra_min": 6})    # R$ 1,00
    caro = criar_modelo(cliente, dono, receita={"mao_obra_min": 120})    # R$ 20,00
    iid = str(uuid.uuid4())
    pid, p = _vender(cliente, dono, [_item(barato["id"], 1, 30, id=iid)])
    assert p["custo_itens"] == 1
    r = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(caro["id"], 1, 30, id=iid)]})
    assert r.status_code == 200, r.text
    assert cliente.get(f"/api/modelos/{caro['id']}", headers=dono).json()["estoque"] == -1
    assert r.json()["custo_itens"] == 20, f"custo do modelo antigo ficou congelado: {r.json()['custo_itens']}"


def test_reabrir_entregar_cancelar_estoque_soma_movimentos(cliente, dono, db, empresa_a_id):
    from app.estoque.servico import saldo
    m = criar_modelo(cliente, dono)
    iid = str(uuid.uuid4())
    pid, _ = _vender(cliente, dono, [_item(m["id"], 2, 10, id=iid)])
    cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(m["id"], 5, 10, id=iid)]})
    cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "pronto"})
    cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "entregue"})
    cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(m["id"], 3, 10, id=iid)]})
    assert saldo(db, empresa_a_id, "peca", uuid.UUID(m["id"])) == -3
    cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "cancelado"})
    db.expire_all()
    assert saldo(db, empresa_a_id, "peca", uuid.UUID(m["id"])) == 0
    painel = cliente.get("/api/painel?inicio=2026-11-01&fim=2026-11-30", headers=dono).json()
    assert painel["receita"] == 0 and painel["lucro_vendas"] == 0


# ---------------------------------------------------------------- parcelas

def _pagar(cliente, h, pid, valor, id=None):
    return cliente.put(f"/api/pedidos/{pid}/pagamentos/{id or uuid.uuid4()}", headers=h, json={"valor": valor})


def test_preco_editado_depois_de_quitar_volta_a_receber(cliente, dono):
    m = criar_modelo(cliente, dono)
    iid = str(uuid.uuid4())
    pid, _ = _vender(cliente, dono, [_item(m["id"], 1, 40, id=iid)])
    assert _pagar(cliente, dono, pid, 40).json()["pago"] is True
    p = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(m["id"], 1, 50, id=iid)]}).json()
    assert (p["pago"], p["saldo"]) == (False, 10)


def test_preco_editado_por_status_reabre_e_entrega_mantem_pago(cliente, dono):
    m = criar_modelo(cliente, dono)
    pid, _ = _vender(cliente, dono, [_item(m["id"], 1, 40)])
    _pagar(cliente, dono, pid, 40)
    cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "pronto"})
    p = cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "entregue"}).json()
    assert (p["pago"], p["recebido"], p["saldo"]) == (True, 40, 0)


def test_pedido_antigo_pago_sem_parcela_e_preco_editado(cliente, dono):
    """Marcado pago (sem parcelas) por R$ 40; preço sobe para 50 → recebido vira 50 sem ninguém receber."""
    m = criar_modelo(cliente, dono)
    iid = str(uuid.uuid4())
    pid, _ = _vender(cliente, dono, [_item(m["id"], 1, 40, id=iid)], pago=True)
    p = cliente.put(f"/api/pedidos/{pid}", headers=dono, json={"itens": [_item(m["id"], 1, 50, id=iid)]}).json()
    assert p["recebido"] == 40, f"recebido acompanhou o preço novo: {p['recebido']}"


def test_pedido_antigo_pago_perde_o_pago_ao_apagar_parcela(cliente, dono):
    """Pedido antigo marcado pago; alguém lança uma parcela por engano e apaga → pedido vira 'a receber'."""
    m = criar_modelo(cliente, dono)
    pid, _ = _vender(cliente, dono, [_item(m["id"], 1, 40)], pago=True)
    x = str(uuid.uuid4())
    assert _pagar(cliente, dono, pid, 5, id=x).status_code == 422  # já estava pago: não cabe mais nada
    p = cliente.get(f"/api/pedidos/{pid}", headers=dono).json()
    assert (p["pago"], p["recebido"], len(p["pagamentos"])) == (True, 40, 0)  # recusado: nada muda


def test_parcela_apagada_e_reenviada_ressuscita(cliente, dono):
    m = criar_modelo(cliente, dono)
    pid, _ = _vender(cliente, dono, [_item(m["id"], 1, 40)])
    x = str(uuid.uuid4())
    _pagar(cliente, dono, pid, 10, id=x)
    cliente.delete(f"/api/pagamentos/{x}", headers=dono)
    p = _pagar(cliente, dono, pid, 10, id=x).json()
    assert p["recebido"] == 0, "PUT repetido da fila trouxe de volta a parcela apagada"


def test_parcela_tres_casas_recusada_e_centavos(cliente, dono):
    m = criar_modelo(cliente, dono)
    pid, _ = _vender(cliente, dono, [_item(m["id"], 3, 3.3333)])  # 9,9999 → 10,00
    assert _pagar(cliente, dono, pid, 9.999).status_code == 422
    p = _pagar(cliente, dono, pid, 10).json()
    assert (p["total"], p["pago"], p["saldo"]) == (10, True, 0)


def test_parcela_em_pedido_cancelado_depois_continua_somando(cliente, dono):
    m = criar_modelo(cliente, dono)
    pid, _ = _vender(cliente, dono, [_item(m["id"], 1, 40)])
    _pagar(cliente, dono, pid, 40)
    p = cliente.post(f"/api/pedidos/{pid}/status", headers=dono, json={"status": "cancelado"}).json()
    assert p["status"] == "cancelado"
    # parcela fica (dinheiro que entrou); só registra o comportamento
    assert p["recebido"] == 40


# ---------------------------------------------------------------- Pix

def _campos(codigo):
    """Lê o TLV de nível 1; quebra se algum tamanho estiver errado."""
    out, i = {}, 0
    while i < len(codigo):
        id_, n = codigo[i:i + 2], int(codigo[i + 2:i + 4])
        out[id_] = codigo[i + 4:i + 4 + n]
        i += 4 + n
    assert i == len(codigo)
    return out


def test_br_code_valor_alto_e_nomes_longos():
    c = copia_e_cola("+5554999998888", "Ateliê de Impressões Três Dê Ltda ME", "São João do Polêsine do Sul",
                     Decimal("99999.99"), "CUBO3" + "A" * 20)
    f = _campos(c)
    assert f["54"] == "99999.99" and len(f["59"]) <= 25 and len(f["60"]) <= 15
    assert c[-4:] == crc16(c[:-4])


def test_chave_email_com_acento_quebra_tamanho():
    try:
        chave = normalizar_chave("email", "joão@exemplo.com")
    except ValueError:
        return  # recusou: ok
    c = copia_e_cola(chave, "Fulano", "Cidade", Decimal("1"))
    assert len(c.encode()) == len(c), "chave com acento no BR Code: tamanho do campo em caracteres ≠ bytes"


def test_cpf_com_letras_aceito():
    try:
        normalizar_chave("cpf", "abc529.982.247-25xyz")
    except ValueError:
        return
    raise AssertionError("CPF com letras foi aceito")


# ---------------------------------------------------------------- movimento manual

def test_movimento_manual_com_valor_negativo_ou_vinculo_falso(cliente, dono):
    f = criar_filamento(cliente, dono)
    car = criar_carretel(cliente, dono, f["id"])
    # compra manual com valor negativo: vira "dinheiro entrando" no painel
    r = cliente.put(f"/api/movimentos/{uuid.uuid4()}", headers=dono, json={
        "item_tipo": "carretel", "item_id": car["id"], "tipo": "compra", "quantidade": 10, "valor": -500,
        "data": "2026-11-05T12:00:00Z"})
    negativo_aceito = r.status_code == 200
    # ajuste manual com pedido_id inventado: depois não dá para apagar
    mid = str(uuid.uuid4())
    r = cliente.put(f"/api/movimentos/{mid}", headers=dono, json={
        "item_tipo": "carretel", "item_id": car["id"], "tipo": "ajuste", "quantidade": -5,
        "pedido_id": str(uuid.uuid4())})
    preso = r.status_code == 200 and cliente.delete(f"/api/movimentos/{mid}", headers=dono).status_code == 409
    assert not negativo_aceito and not preso, (negativo_aceito, preso)

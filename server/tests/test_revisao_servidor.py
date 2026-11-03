"""Testes da revisão final da branch feat/servidor.

Cada teste afirma o comportamento CORRETO; se falhar, o bug está reproduzido.
"""
import os
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from test_catalogo import criar_modelo, enviar
from test_estoque import criar_carretel, criar_filamento, saldo
from test_vendas import canal, item

# Bug reproduzido na revisão: o teste afirma o comportamento certo e hoje falha.
# strict=True: quando o bug for corrigido o teste acusa XPASS; aí é só tirar a marca.
BUG = pytest.mark.xfail(strict=True, reason="bug da revisão final de feat/servidor")


@pytest.fixture
def cli(app, cliente):
    """Cliente que devolve 500 em vez de levantar a exceção do servidor."""
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


def _impressao_manual(cliente, h, duracao_s=3600):
    i = str(uuid.uuid4())
    r = cliente.put(f"/api/impressoes/{i}", headers=h, json={"arquivo": "x.gcode", "duracao_s": duracao_s})
    assert r.status_code == 200, r.text
    return i


def test_revisao_consumo_repetido_do_mesmo_carretel(cliente, dono):
    """Dois consumos do mesmo carretel (ex.: multicor com 2 cores no mesmo rolo, ou app que não agrupa)."""
    car = criar_carretel(cliente, dono, criar_filamento(cliente, dono)["id"])
    i = _impressao_manual(cliente, dono)
    r = cliente.post(f"/api/impressoes/{i}/confirmar", headers=dono, json={
        "finalidade": "teste", "consumos": [{"carretel_id": car["id"], "gramas": 10},
                                            {"carretel_id": car["id"], "gramas": 20}]})
    assert r.status_code == 200, r.text
    # custo cobra 30 g; o estoque precisa baixar os mesmos 30 g
    assert saldo(cliente, dono, car["id"]) == 970


def test_revisao_modelos_atualizado_desde(cli, dono):
    criar_modelo(cli, dono)
    r = cli.get("/api/modelos", headers=dono, params={"atualizado_desde": "2020-01-01T00:00:00+00:00"})
    assert r.status_code == 200, r.text
    assert len(r.json()) == 1


def test_revisao_margem_100_derruba_calculadora(cli, dono):
    r = cli.put("/api/empresa/config", headers=dono, json={"margens": [20, 30, 100]})
    assert r.status_code == 422, "margem de 100% (ou mais) não deveria ser aceita"
    r = cli.post("/api/calculadora", headers=dono, json={"filamentos": [{"preco_kg": 100, "gramas": 33}], "horas": 3})
    assert r.status_code == 200, r.text


def test_revisao_margem_acima_de_100_aceita(cli, dono):
    r = cli.put("/api/empresa/config", headers=dono, json={"margens": [150]})
    assert r.status_code == 422, f"percentual fora de 0–100 aceito: {r.status_code} {r.text}"


@BUG
def test_revisao_data_sem_fuso_vira_500(cli, dono):
    m = criar_modelo(cli, dono)
    r = cli.put(f"/api/pedidos/{uuid.uuid4()}", headers=dono, json={
        "canal_id": canal(cli, dono), "status": "entregue", "itens": [item(m["id"])],
        "entregue_em": "2026-10-31T23:30:00"})
    assert r.status_code in (200, 422), f"esperado 200 (assumindo fuso local) ou 422, veio {r.status_code}"


@BUG
def test_revisao_movimento_data_sem_fuso(cli, dono):
    car = criar_carretel(cli, dono, criar_filamento(cli, dono)["id"])
    r = cli.put(f"/api/movimentos/{uuid.uuid4()}", headers=dono, json={
        "item_tipo": "carretel", "item_id": car["id"], "tipo": "consumo", "quantidade": -5,
        "data": "2026-10-31T23:30:00"})
    assert r.status_code in (200, 422), f"veio {r.status_code}"


def test_revisao_null_explicito_em_campo_com_padrao(cli, dono):
    r = cli.put(f"/api/impressoras/{uuid.uuid4()}", headers=dono, json={"nome": "V3", "preco": None})
    assert r.status_code in (200, 422), f"veio {r.status_code}"


@BUG
def test_revisao_preco_kg_real_arredonda_half_up(cliente, dono):
    car = criar_carretel(cliente, dono, criar_filamento(cliente, dono)["id"], peso=800, preco=80.02)
    # 80,02 / 800 g × 1000 = 100,025 → ROUND_HALF_UP = 100,03
    assert car["preco_kg_real"] == 100.03


def test_revisao_bloqueio_de_login_em_paralelo(cliente, empresas, monkeypatch):
    """Com o argon2 de produção (~dezenas de ms), tentativas em paralelo perdem a contagem de falhas."""
    from app.auth import rotas
    original = rotas.confere_senha

    def lento(s, h):
        time.sleep(0.2)  # simula o custo do argon2 com parâmetros de produção
        return original(s, h)

    monkeypatch.setattr(rotas, "confere_senha", lento)

    def tentar(_):
        return cliente.post("/api/auth/login", json={"email": "dono@a.com", "senha": "errada-123"}).status_code

    with ThreadPoolExecutor(20) as ex:
        codigos = list(ex.map(tentar, range(20)))
    # depois de 20 falhas, a conta tem de estar bloqueada
    depois = cliente.post("/api/auth/login", json={"email": "dono@a.com", "senha": "errada-123"}).status_code
    assert codigos.count(401) <= 5 and depois == 429, f"401 em paralelo: {codigos.count(401)}; depois: {depois}"


def test_revisao_confirmacao_concorrente_baixa_duas_vezes(cliente, dono, monkeypatch):
    """Dois aparelhos confirmam a mesma impressão ao mesmo tempo, cada um com um carretel."""
    from app.impressoes import servico
    original = servico.param_empresa

    def lento(db, empresa_id):
        time.sleep(0.5)  # alarga a janela entre ler o status e gravar
        return original(db, empresa_id)

    monkeypatch.setattr(servico, "param_empresa", lento)
    fil = criar_filamento(cliente, dono)["id"]
    c1, c2 = criar_carretel(cliente, dono, fil), criar_carretel(cliente, dono, fil)
    i = _impressao_manual(cliente, dono)
    barreira = threading.Barrier(2)

    def confirmar(car):
        barreira.wait()
        return cliente.post(f"/api/impressoes/{i}/confirmar", headers=dono, json={
            "finalidade": "teste", "consumos": [{"carretel_id": car["id"], "gramas": 50}]}).status_code

    with ThreadPoolExecutor(2) as ex:
        codigos = list(ex.map(confirmar, (c1, c2)))
    baixado = (1000 - saldo(cliente, dono, c1["id"])) + (1000 - saldo(cliente, dono, c2["id"]))
    assert baixado == 50, f"códigos {codigos}; total baixado {baixado} g (uma impressão de 50 g)"


@pytest.mark.skipif(os.environ.get("REVISAO_GRANDE") != "1", reason="defina REVISAO_GRANDE=1 (sobe 120 MB)")
def test_revisao_upload_120mb(cliente, dono, tmp_path):
    m = criar_modelo(cliente, dono)
    r = enviar(cliente, dono, m["id"], "grande.stl", b"\0" * (120 * 1024 * 1024))
    assert r.status_code == 413
    assert "95 MB" in r.json()["detail"]
    assert not [p for p in (tmp_path / "arquivos").rglob("*") if p.is_file()]


@BUG
def test_revisao_null_explicito_em_registro_existente(cli, dono):
    i = uuid.uuid4()
    assert cli.put(f"/api/impressoras/{i}", headers=dono, json={"nome": "V3"}).status_code == 200
    r = cli.put(f"/api/impressoras/{i}", headers=dono, json={"preco": None})
    assert r.status_code in (200, 422), f"veio {r.status_code}"


@BUG
def test_revisao_arquivo_sumido_do_disco(cli, dono, tmp_path):
    m = criar_modelo(cli, dono)
    a = enviar(cli, dono, m["id"]).json()
    for p in (tmp_path / "arquivos").rglob("*.stl"):
        p.unlink()
    r = cli.get(a["url"], headers=dono)
    assert r.status_code == 404, f"veio {r.status_code}"


def test_revisao_excluir_impressao_confirmada_409(cliente, dono):
    car = criar_carretel(cliente, dono, criar_filamento(cliente, dono)["id"])
    i = _impressao_manual(cliente, dono)
    cliente.post(f"/api/impressoes/{i}/confirmar", headers=dono, json={
        "finalidade": "teste", "consumos": [{"carretel_id": car["id"], "gramas": 10}]})
    assert cliente.delete(f"/api/impressoes/{i}", headers=dono).status_code == 409
    assert cliente.get(f"/api/impressoes/{i}", headers=dono).json()["excluido"] is False
    pendente = _impressao_manual(cliente, dono)
    assert cliente.delete(f"/api/impressoes/{pendente}", headers=dono).status_code == 200


def test_revisao_ultima_gravacao_vence(cliente, dono):
    i = uuid.uuid4()
    cliente.put(f"/api/canais/{i}", headers=dono, json={"nome": "Shopee", "taxa_pct": 20})
    velho = cliente.put(f"/api/canais/{i}", headers={**dono, "X-Alterado-Em": "2020-01-01T00:00:00Z"},
                        json={"taxa_pct": 99})
    assert velho.status_code == 200 and velho.json()["taxa_pct"] == 20
    novo = cliente.put(f"/api/canais/{i}", headers={**dono, "X-Alterado-Em": "2099-01-01T00:00:00Z"},
                       json={"taxa_pct": 12})
    assert novo.json()["taxa_pct"] == 12
    assert cliente.put(f"/api/canais/{i}", headers=dono, json={"taxa_pct": 15}).json()["taxa_pct"] == 15

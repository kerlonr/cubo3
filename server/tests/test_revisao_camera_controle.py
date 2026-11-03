"""Revisão 79c77a8..4a7f389: provas de bugs (xfail com motivo) e checagens que já passam."""
import uuid

import pytest

from app.klipper import moonraker


def _impressora(cliente, h):
    return cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h,
                       json={"nome": "V3", "moonraker_url": "http://192.168.1.110:7125"}).json()


@pytest.fixture
def chamadas(monkeypatch):
    feitas = []
    monkeypatch.setattr(moonraker, "comando", lambda *a, **k: feitas.append(a) or {"result": "ok"})
    return feitas


@pytest.mark.parametrize("valor", ["NaN", "Infinity"])
def test_temperatura_nao_finita_da_422(cliente, dono, chamadas, valor):
    imp = _impressora(cliente, dono)
    r = cliente.post(f"/api/impressoras/{imp['id']}/comando", headers={**dono, "Content-Type": "application/json"},
                     content=f'{{"acao":"temperatura","alvo":"bico","valor":{valor}}}')
    assert chamadas == []  # já passa: nada chega ao Moonraker
    assert r.status_code == 422


def test_reenvio_identico_da_edicao_nao_e_conflito(cliente, dono):
    cid = uuid.uuid4()
    base = cliente.put(f"/api/clientes/{cid}", headers=dono, json={"nome": "Ana"}).json()["atualizado_em"]
    h = {**dono, "X-Versao-Base": base}
    assert cliente.put(f"/api/clientes/{cid}", headers=h, json={"nome": "Ana Souza"}).status_code == 200
    assert cliente.put(f"/api/clientes/{cid}", headers=h, json={"nome": "Ana Souza"}).status_code == 200


def test_criacao_com_versao_base_nao_e_recusada(cliente, dono):
    r = cliente.put(f"/api/clientes/{uuid.uuid4()}", headers={**dono, "X-Versao-Base": "2000-01-01T00:00:00+00:00"},
                    json={"nome": "Nova"})
    assert r.status_code == 200


def test_comando_de_outra_empresa_nao_chega_ao_moonraker(cliente, dono, outro, chamadas):
    imp = _impressora(cliente, dono)
    assert cliente.post(f"/api/impressoras/{imp['id']}/comando", headers=outro, json={"acao": "emergencia"}).status_code == 404
    assert chamadas == []

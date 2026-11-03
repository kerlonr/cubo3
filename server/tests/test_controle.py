import uuid

import httpx
import pytest

from app.klipper import moonraker
from test_catalogo import criar_modelo, enviar


@pytest.fixture
def chamadas(monkeypatch):
    feitas = []

    def comando(url, chave, caminho, params=None):
        feitas.append((caminho, params))
        return {"result": "ok"}

    monkeypatch.setattr(moonraker, "comando", comando)
    monkeypatch.setattr(moonraker, "estado_impressao", lambda url, chave: "standby")
    monkeypatch.setattr(moonraker, "enviar_e_imprimir",
                        lambda url, chave, nome, caminho: feitas.append(("upload", nome, caminho.read_bytes())) or {})
    return feitas


def impressora(cliente, h):
    return cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h,
                       json={"nome": "V3", "moonraker_url": "http://192.168.1.110:7125"}).json()


def comando(cliente, h, imp_id, **corpo):
    return cliente.post(f"/api/impressoras/{imp_id}/comando", headers=h, json=corpo)


def test_membro_nao_controla(cliente, dono, membro, chamadas):
    imp = impressora(cliente, dono)
    assert comando(cliente, membro, imp["id"], acao="pausar").status_code == 403
    m = criar_modelo(cliente, dono)
    a = enviar(cliente, dono, m["id"], "vaso.gcode", b"G28").json()
    assert cliente.post(f"/api/arquivos/{a['id']}/imprimir", headers=membro,
                        json={"impressora_id": imp["id"]}).status_code == 403
    assert chamadas == []


@pytest.mark.parametrize("acao,caminho", [("pausar", "/printer/print/pause"), ("continuar", "/printer/print/resume"),
                                          ("cancelar", "/printer/print/cancel"), ("emergencia", "/printer/emergency_stop")])
def test_acoes(cliente, dono, chamadas, acao, caminho):
    imp = impressora(cliente, dono)
    assert comando(cliente, dono, imp["id"], acao=acao).json() == {"ok": True}
    assert chamadas == [(caminho, None)]


def test_temperatura(cliente, dono, chamadas):
    imp = impressora(cliente, dono)
    assert comando(cliente, dono, imp["id"], acao="temperatura", alvo="bico", valor=210).status_code == 200
    assert comando(cliente, dono, imp["id"], acao="temperatura", alvo="mesa", valor=60).status_code == 200
    assert chamadas == [("/printer/gcode/script", {"script": "SET_HEATER_TEMPERATURE HEATER=extruder TARGET=210"}),
                        ("/printer/gcode/script", {"script": "SET_HEATER_TEMPERATURE HEATER=heater_bed TARGET=60"})]


@pytest.mark.parametrize("alvo,valor", [("bico", 301), ("mesa", 121), ("bico", -1), ("bico", None), (None, 200)])
def test_temperatura_fora_do_limite_422(cliente, dono, chamadas, alvo, valor):
    imp = impressora(cliente, dono)
    assert comando(cliente, dono, imp["id"], acao="temperatura", alvo=alvo, valor=valor).status_code == 422
    assert chamadas == []


def test_impressora_fora_do_ar_502(cliente, dono, monkeypatch):
    def falha(*a, **k):
        raise httpx.ConnectError("sem rota")
    monkeypatch.setattr(moonraker, "comando", falha)
    imp = impressora(cliente, dono)
    r = comando(cliente, dono, imp["id"], acao="pausar")
    assert r.status_code == 502 and "não respondeu" in r.json()["detail"]


def test_impressora_de_outra_empresa_404(cliente, dono, outro, chamadas):
    imp = impressora(cliente, dono)
    assert comando(cliente, outro, imp["id"], acao="pausar").status_code == 404
    assert chamadas == []


def test_imprimir_gcode(cliente, dono, chamadas):
    imp = impressora(cliente, dono)
    m = criar_modelo(cliente, dono)
    a = enviar(cliente, dono, m["id"], "vaso_PLA.gcode", b"G28\nG1 X10").json()
    r = cliente.post(f"/api/arquivos/{a['id']}/imprimir", headers=dono, json={"impressora_id": imp["id"]})
    assert r.status_code == 200 and r.json() == {"ok": True, "arquivo": "vaso_PLA.gcode"}
    assert chamadas == [("upload", "vaso_PLA.gcode", b"G28\nG1 X10")]


def test_imprimir_stl_422(cliente, dono, chamadas):
    imp = impressora(cliente, dono)
    a = enviar(cliente, dono, criar_modelo(cliente, dono)["id"]).json()
    assert cliente.post(f"/api/arquivos/{a['id']}/imprimir", headers=dono,
                        json={"impressora_id": imp["id"]}).status_code == 422


@pytest.mark.parametrize("estado", ["printing", "paused"])
def test_imprimir_com_impressora_ocupada_409(cliente, dono, chamadas, monkeypatch, estado):
    monkeypatch.setattr(moonraker, "estado_impressao", lambda url, chave: estado)
    imp = impressora(cliente, dono)
    a = enviar(cliente, dono, criar_modelo(cliente, dono)["id"], "x.gcode", b"G28").json()
    r = cliente.post(f"/api/arquivos/{a['id']}/imprimir", headers=dono, json={"impressora_id": imp["id"]})
    assert r.status_code == 409 and "ocupada" in r.json()["detail"]
    assert chamadas == []

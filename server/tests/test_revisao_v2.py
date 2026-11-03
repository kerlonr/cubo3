"""Revisão final feat/v2 (79c77a8..6dbbf7a): provas de bugs (xfail strict, com motivo) e checagens que já passam.

Nada aqui fala com impressora real: o Moonraker é trocado por funções falsas (monkeypatch).
"""
import uuid

import pytest

from app.klipper import moonraker


def _impressora(cliente, h):
    return cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h,
                       json={"nome": "V3", "moonraker_url": "http://192.168.1.110:7125"}).json()["id"]


@pytest.fixture
def klipper(monkeypatch):
    """Klipper falso com a regra real do run_script: linha a linha, aborta no primeiro erro
    (klippy/gcode.py _process_commands com need_ack=False relança a exceção)."""
    k = {"chamadas": [], "relativo": False, "homed": "", "estado": "standby", "baixados": []}

    def comando(url, chave, caminho, params=None):
        k["chamadas"].append((caminho, params))
        for linha in ((params or {}).get("script") or "").split("\n"):
            cmd = linha.strip().split(" ")[0].upper()
            if cmd == "G91":
                k["relativo"] = True
            elif cmd == "G90":
                k["relativo"] = False
            elif cmd == "G1" and any(e in linha.upper() for e in "XYZ") and not k["homed"]:
                raise moonraker.ErroKlipper("Must home axis first: 0.000 0.000 0.000 [0.000]")
        return {"result": "ok"}

    def baixar(url, chave, caminho):
        k["baixados"].append(caminho)
        return b"PNG"

    monkeypatch.setattr(moonraker, "comando", comando)
    monkeypatch.setattr(moonraker, "estado_impressao", lambda url, chave: k["estado"])
    monkeypatch.setattr(moonraker, "listar_macros", lambda url, chave: ["LIMPAR"])
    monkeypatch.setattr(moonraker, "baixar", baixar)
    return k


def test_mover_recusado_nao_deixa_a_impressora_em_modo_relativo(cliente, dono, klipper):
    imp = _impressora(cliente, dono)
    r = cliente.post(f"/api/impressoras/{imp}/comando", headers=dono, json={"acao": "mover", "eixo": "X", "distancia": 10})
    assert r.status_code == 400  # já passa: a recusa do Klipper chega ao app
    assert klipper["relativo"] is False


@pytest.mark.parametrize("estado,corpo", [
    ("printing", {"acao": "home", "eixos": "XYZ"}), ("printing", {"acao": "motores_off"}),
    ("printing", {"acao": "extrudar", "distancia": 25}), ("printing", {"acao": "mover", "eixo": "Z", "distancia": 10}),
    # pausada: mover/extrudar são o fluxo normal de troca de filamento (o RESUME restaura o estado do G-code);
    # home e desligar motores perdem a posição e a retomada sai torta.
    ("paused", {"acao": "home", "eixos": "XYZ"}), ("paused", {"acao": "motores_off"}),
])
def test_movimento_com_impressao_em_andamento_e_recusado(cliente, dono, klipper, corpo, estado):
    klipper["estado"], klipper["homed"] = estado, "xyz"
    imp = _impressora(cliente, dono)
    r = cliente.post(f"/api/impressoras/{imp}/comando", headers=dono, json=corpo)
    assert r.status_code == 409
    assert klipper["chamadas"] == []


@pytest.mark.parametrize("caminho", ["%2e%2e/%2e%2e/config/printer.png", "%2e%2e%2fconfig%2fprinter.cfg?x=.png",
                                     "vaso.gcode?x=.png", "vaso.gcode#.png"])
def test_miniatura_com_caminho_codificado_e_recusada(cliente, membro, dono, klipper, caminho):
    imp = _impressora(cliente, dono)
    r = cliente.get(f"/api/impressoras/{imp}/arquivos/miniatura", headers=membro, params={"caminho": caminho})
    assert r.status_code == 422
    assert klipper["baixados"] == []


@pytest.mark.parametrize("corpo", ['{"acao":"mover","eixo":"X","distancia":NaN}',
                                   '{"acao":"ventoinha","valor":Infinity}', '{"acao":"ajuste_z","valor":-Infinity}'])
def test_numero_nao_finito_da_422(cliente, dono, klipper, corpo):
    imp = _impressora(cliente, dono)
    r = cliente.post(f"/api/impressoras/{imp}/comando", headers={**dono, "Content-Type": "application/json"}, content=corpo)
    assert klipper["chamadas"] == []  # já passa
    assert r.status_code == 422


ACOES = [{"acao": a} for a in ("pausar", "continuar", "cancelar", "emergencia", "reiniciar_firmware", "motores_off")] + [
    {"acao": "temperatura", "alvo": "bico", "valor": 200}, {"acao": "home", "eixos": "XY"},
    {"acao": "mover", "eixo": "X", "distancia": 1}, {"acao": "extrudar", "distancia": 5},
    {"acao": "ventoinha", "valor": 50}, {"acao": "velocidade", "valor": 100}, {"acao": "fluxo", "valor": 100},
    {"acao": "ajuste_z", "valor": 0.01}, {"acao": "macro", "nome": "LIMPAR"}, {"acao": "inexistente"}, {}]


def test_membro_nao_faz_nenhuma_acao_por_nenhuma_rota(cliente, dono, membro, outro, klipper, db):
    imp = _impressora(cliente, dono)
    for corpo in ACOES:
        r = cliente.post(f"/api/impressoras/{imp}/comando", headers=membro, json=corpo)
        assert r.status_code == 403, (corpo, r.status_code)
        assert cliente.post(f"/api/impressoras/{imp}/comando", headers=outro, json=corpo).status_code in (403, 404, 422)
    assert cliente.post(f"/api/impressoras/{imp}/gcode", headers=membro, json={"script": "M112"}).status_code == 403
    assert cliente.post(f"/api/impressoras/{imp}/arquivos/imprimir", headers=membro, json={"nome": "a.gcode"}).status_code == 403
    assert cliente.post(f"/api/arquivos/{uuid.uuid4()}/imprimir", headers=membro,
                        json={"impressora_id": imp}).status_code == 403
    assert klipper["chamadas"] == []


def test_mover_aceito_volta_ao_modo_absoluto(cliente, dono, klipper):
    klipper["homed"] = "xyz"
    imp = _impressora(cliente, dono)
    r = cliente.post(f"/api/impressoras/{imp}/comando", headers=dono, json={"acao": "mover", "eixo": "Y", "distancia": -100})
    assert r.status_code == 200
    assert klipper["chamadas"] == [("/printer/gcode/script", {"script": "G91\nG1 Y-100 F6000"}),
                                   ("/printer/gcode/script", {"script": "G90"})]
    assert klipper["relativo"] is False

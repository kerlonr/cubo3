import asyncio
import json
import socket
import time
import uuid
from pathlib import Path

import pytest
import websockets
from starlette.websockets import WebSocketDisconnect

from app.klipper import moonraker

JOBS = json.loads((Path(__file__).parent / "fixtures" / "moonraker_historico.json").read_text())["result"]["jobs"]
JOB = JOBS[0]


def impressora(cliente, h, url="http://127.0.0.1:1"):
    r = cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h, json={"nome": "V3", "moonraker_url": url})
    return r.json()


def test_parser_trabalho_real():
    d = moonraker.trabalho_de_historico(JOB)
    assert (d.job_id, d.arquivo, d.status, d.gramas_total) == ("0000A8", "TQZ2G08_PLA_21m58s.gcode", "completed", 1.71)
    assert [f["tipo"] for f in d.filamentos] == ["PLA", "PLA"]
    assert [f["cor"] for f in d.filamentos] == ["#FFFFFF", "#000000"]
    assert d.miniatura_rel.endswith("-50x50.png")
    assert d.duracao_s == round(JOB["print_duration"]) and d.fim.tzinfo is not None


def test_parser_um_filamento_texto_puro():
    d = moonraker.trabalho_de_historico(JOBS[2])
    assert [(f["tipo"], f["gramas"]) for f in d.filamentos] == [("PLA", 125.33)]


def test_mesclar_estado():
    e = moonraker.mesclar_estado({}, {"print_stats": {"state": "printing", "filename": "a.gcode", "print_duration": 600},
                                      "display_status": {"progress": 0.25}})
    assert (e["estado"], e["arquivo"], e["progresso"], e["restante_s"]) == ("printing", "a.gcode", 0.25, 1800)
    e = moonraker.mesclar_estado(e, {"extruder": {"temperature": 200.4, "target": 210}})
    assert (e["bico"], e["bico_alvo"], e["progresso"], e["duracao_s"]) == (200.4, 210, 0.25, 600)


def _registrar(db, empresa_id, imp_id, job=JOB, arquivada=False):
    from app.klipper.servico import registrar_trabalho
    r = registrar_trabalho(db, empresa_id, uuid.UUID(imp_id), moonraker.trabalho_de_historico(job), arquivada=arquivada)
    db.commit()
    return r


def test_registrar_duas_vezes(cliente, dono, db, empresa_a_id, monkeypatch):
    imp = impressora(cliente, dono)
    assert _registrar(db, empresa_a_id, imp["id"]) is not None
    assert _registrar(db, empresa_a_id, imp["id"]) is None
    pend = cliente.get("/api/impressoes", headers=dono, params={"status": "a_confirmar"}).json()
    assert len(pend) == 1 and pend[0]["job_id"] == "0000A8" and pend[0]["origem"] == "klipper"
    assert pend[0]["estimativa"]["gramas_total"] == 1.71
    monkeypatch.setattr(moonraker, "buscar_job", lambda url, chave, job_id: JOB)
    r = cliente.post(f"/api/impressoras/{imp['id']}/historico/0000A8/trazer", headers=dono)
    assert r.status_code == 200 and r.json()["id"] == pend[0]["id"]
    assert len(cliente.get("/api/impressoes", headers=dono).json()) == 1


def test_trazer_entra_arquivada(cliente, dono, monkeypatch):
    imp = impressora(cliente, dono)
    monkeypatch.setattr(moonraker, "buscar_job", lambda url, chave, job_id: JOBS[2])
    r = cliente.post(f"/api/impressoras/{imp['id']}/historico/0000A6/trazer", headers=dono)
    assert r.status_code == 200 and r.json()["status"] == "arquivada"
    assert cliente.get("/api/painel", headers=dono).json()["a_confirmar"] == 0


def test_casar_modelo_no_registro(cliente, dono, db, empresa_a_id):
    from test_catalogo import criar_modelo
    m = criar_modelo(cliente, dono, nomes_arquivo=["TQZ2G08_PLA_21m58s.gcode"])
    imp = impressora(cliente, dono)
    assert str(_registrar(db, empresa_a_id, imp["id"]).modelo_id) == m["id"]


def _token(h):
    return h["Authorization"].removeprefix("Bearer ")


def test_hub_isola_empresas(cliente, dono, outro, empresas):
    from app.ao_vivo import hub
    a, b = empresas["a"], empresas["b"]
    with cliente.websocket_connect(f"/api/ao-vivo?token={_token(dono)}&empresa={a}") as wa, \
            cliente.websocket_connect(f"/api/ao-vivo?token={_token(outro)}&empresa={b}") as wb:
        hub.publicar(a, {"tipo": "teste", "para": "a"})
        hub.publicar(b, {"tipo": "teste", "para": "b"})
        assert wa.receive_json() == {"tipo": "teste", "para": "a"}
        assert wb.receive_json() == {"tipo": "teste", "para": "b"}
    with pytest.raises(WebSocketDisconnect) as e:
        with cliente.websocket_connect(f"/api/ao-vivo?token={_token(outro)}&empresa={a}") as ws:
            ws.receive_json()
    assert e.value.code == 4403
    with pytest.raises(WebSocketDisconnect) as e:
        with cliente.websocket_connect(f"/api/ao-vivo?token=lixo&empresa={a}") as ws:
            ws.receive_json()
    assert e.value.code == 4401


def _porta_livre():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def test_monitor_com_moonraker_falso(cliente, dono, fabrica, empresa_a_id):
    from app.ao_vivo import Hub
    from app.impressoes.modelos import Impressao
    from app.klipper.monitor import Monitor
    from sqlalchemy import select

    imp = impressora(cliente, dono)
    porta = _porta_livre()
    recebidos = []

    async def moonraker_falso(ws):
        async for bruto in ws:
            msg = json.loads(bruto)
            if msg["method"] == "printer.objects.subscribe":
                await ws.send(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {
                    "status": {"print_stats": {"state": "printing", "filename": JOB["filename"], "print_duration": 60},
                               "display_status": {"progress": 0.5}}}}))
                await ws.send(json.dumps({"jsonrpc": "2.0", "method": "notify_history_changed",
                                          "params": [{"action": "finished", "job": JOB}]}))
            else:
                await ws.send(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {}}))

    class HubTeste(Hub):
        def publicar(self, empresa_id, evento):
            recebidos.append((empresa_id, evento))

    async def cenario():
        async with websockets.serve(moonraker_falso, "127.0.0.1", porta):
            m = Monitor(uuid.UUID(imp["id"]), empresa_a_id, f"http://127.0.0.1:{porta}", None, fabrica, HubTeste())
            tarefa = asyncio.create_task(m.rodar())
            limite = time.monotonic() + 10
            while time.monotonic() < limite and not any(e["tipo"] == "impressao_terminou" for _, e in recebidos):
                await asyncio.sleep(0.05)
            tarefa.cancel()
            return m.estado

    estado = asyncio.run(cenario())
    assert estado["progresso"] == 0.5
    eventos = [e["tipo"] for _, e in recebidos]
    assert "estado" in eventos and "impressao_terminou" in eventos
    with fabrica() as s:
        imps = list(s.scalars(select(Impressao).where(Impressao.job_id == "0000A8")))
    assert [(i.status, i.empresa_id) for i in imps] == [("a_confirmar", empresa_a_id)]

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


def test_monitor_recupera_trabalho_terminado_desconectado(cliente, dono, fabrica, empresa_a_id):
    """Trabalho que terminou com o monitor fora do ar entra na reconexão (só os posteriores ao cadastro)."""
    from app.ao_vivo import Hub
    from app.impressoes.modelos import Impressao
    from app.klipper.monitor import Monitor
    from sqlalchemy import select

    imp = impressora(cliente, dono)
    novo = {**JOB, "job_id": "0000B1", "end_time": time.time() + 5}  # terminou depois do cadastro
    antigo = {**JOB, "job_id": "0000A1"}  # terminou antes de a impressora existir no Cubo³
    porta = _porta_livre()
    recebidos = []

    async def moonraker_falso(ws):
        async for bruto in ws:
            msg = json.loads(bruto)
            resultado = {"jobs": [novo, antigo]} if msg["method"] == "server.history.list" else {}
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": resultado}))

    class HubTeste(Hub):
        def publicar(self, empresa_id, evento):
            recebidos.append(evento)

    async def cenario():
        async with websockets.serve(moonraker_falso, "127.0.0.1", porta):
            m = Monitor(uuid.UUID(imp["id"]), empresa_a_id, f"http://127.0.0.1:{porta}", None, fabrica, HubTeste())
            tarefa = asyncio.create_task(m.rodar())
            limite = time.monotonic() + 10
            while time.monotonic() < limite and not any(e["tipo"] == "impressao_terminou" for e in recebidos):
                await asyncio.sleep(0.05)
            await asyncio.sleep(0.3)
            tarefa.cancel()

    asyncio.run(cenario())
    with fabrica() as s:
        jobs = sorted(i.job_id for i in s.scalars(select(Impressao).where(Impressao.empresa_id == empresa_a_id)))
    assert jobs == ["0000B1"]


def test_mesclar_estado_completo():
    e = moonraker.mesclar_estado({}, {
        "toolhead": {"position": [10.0, 20.0, 5.0, 0.0], "homed_axes": "xy"},
        "gcode_move": {"speed_factor": 1.5, "extrude_factor": 0.95, "homing_origin": [0, 0, -0.05, 0]},
        "fan": {"speed": 0.5}, "display_status": {"message": "Aquecendo"}})
    assert (e["posicao"], e["eixos_home"], e["velocidade_pct"], e["fluxo_pct"], e["z_offset"], e["ventoinha_pct"],
            e["mensagem"]) == ([10.0, 20.0, 5.0], "xy", 150, 95, -0.05, 50, "Aquecendo")


def test_console_ao_vivo(cliente, dono, fabrica, empresa_a_id):
    from app.ao_vivo import Hub
    from app.klipper.monitor import Monitor, monitores

    imp = impressora(cliente, dono)
    porta = _porta_livre()
    recebidos = []

    async def moonraker_falso(ws):
        async for bruto in ws:
            msg = json.loads(bruto)
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {}}))
            if msg["method"] == "printer.objects.subscribe":
                for i in range(105):
                    await ws.send(json.dumps({"jsonrpc": "2.0", "method": "notify_gcode_response",
                                              "params": [f"// linha {i}"]}))

    class HubTeste(Hub):
        def publicar(self, empresa_id, evento):
            recebidos.append(evento)

    async def cenario():
        async with websockets.serve(moonraker_falso, "127.0.0.1", porta):
            m = Monitor(uuid.UUID(imp["id"]), empresa_a_id, f"http://127.0.0.1:{porta}", None, fabrica, HubTeste())
            tarefa = asyncio.create_task(m.rodar())
            limite = time.monotonic() + 10
            while time.monotonic() < limite and len([e for e in recebidos if e["tipo"] == "console"]) < 105:
                await asyncio.sleep(0.05)
            tarefa.cancel()
            return m

    m = asyncio.run(cenario())
    console = [e for e in recebidos if e["tipo"] == "console"]
    assert console[0]["texto"] == "// linha 0" and console[0]["impressora_id"] == imp["id"] and console[0]["hora"]
    assert len(m.console) == 100 and m.console[-1]["texto"] == "// linha 104"
    monitores._monitores[uuid.UUID(imp["id"])] = (m, None)  # simula o monitor rodando para a rota
    try:
        linhas = cliente.get(f"/api/impressoras/{imp['id']}/console", headers=dono).json()["linhas"]
    finally:
        monitores._monitores.pop(uuid.UUID(imp["id"]), None)
    assert len(linhas) == 100 and linhas[0]["texto"] == "// linha 5"


def test_mesclar_estado_traz_camada_atual_e_total():
    e = moonraker.mesclar_estado({}, {"print_stats": {"state": "printing", "info": {"current_layer": 34, "total_layer": 120}}})
    assert (e["camada"], e["camadas"]) == (34, 120)
    assert moonraker.mesclar_estado({}, {"print_stats": {"state": "printing"}})["camada"] is None

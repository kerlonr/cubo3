import uuid

import pytest

from app.klipper import moonraker

ARQUIVOS = [
    {"filename": "antigo.gcode", "size": 10, "modified": 1700000000.0, "estimated_time": 60,
     "filament_weight_total": 1.5, "thumbnails": [{"width": 32, "height": 32, "relative_path": ".thumbs/antigo-32x32.png"},
                                                  {"width": 300, "height": 300, "relative_path": ".thumbs/antigo-300x300.png"}]},
    {"filename": "novo.gcode", "size": 20, "modified": 1790000000.0},
]


@pytest.fixture
def klipper(monkeypatch):
    feitas = []
    estado = {"impressao": "standby"}

    def comando(url, chave, caminho, params=None):
        feitas.append((caminho, params))
        return {"result": "ok"}

    monkeypatch.setattr(moonraker, "comando", comando)
    monkeypatch.setattr(moonraker, "estado_impressao", lambda url, chave: estado["impressao"])
    monkeypatch.setattr(moonraker, "listar_arquivos", lambda url, chave: ARQUIVOS)
    monkeypatch.setattr(moonraker, "listar_macros", lambda url, chave: ["LIMPAR_BICO", "PURGE"])
    monkeypatch.setattr(moonraker, "baixar", lambda url, chave, caminho: b"PNG" if caminho.endswith(".png") else None)
    return feitas, estado


def impressora(cliente, h):
    return cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h,
                       json={"nome": "V3", "moonraker_url": "http://192.168.1.110:7125"}).json()["id"]


def script(feitas):
    return [p["script"] if p else c for c, p in feitas]


@pytest.mark.parametrize("corpo,esperado", [
    ({"acao": "home", "eixos": "XYZ"}, "G28 X Y Z"),
    ({"acao": "home", "eixos": "XY"}, "G28 X Y"),
    ({"acao": "home", "eixos": "Z"}, "G28 Z"),
    ({"acao": "mover", "eixo": "X", "distancia": 10}, "G91\nG1 X10 F6000|G90"),
    ({"acao": "mover", "eixo": "Z", "distancia": -0.1}, "G91\nG1 Z-0.1 F600|G90"),
    ({"acao": "motores_off"}, "M84"),
    ({"acao": "extrudar", "distancia": -5}, "M83\nG1 E-5 F300"),
    ({"acao": "ventoinha", "valor": 50}, "M106 S128"),
    ({"acao": "ventoinha", "valor": 0}, "M107"),
    ({"acao": "velocidade", "valor": 150}, "M220 S150"),
    ({"acao": "fluxo", "valor": 95}, "M221 S95"),
    ({"acao": "ajuste_z", "valor": -0.05}, "SET_GCODE_OFFSET Z_ADJUST=-0.05 MOVE=1"),
    ({"acao": "macro", "nome": "LIMPAR_BICO"}, "LIMPAR_BICO"),
    ({"acao": "reiniciar_firmware"}, "/printer/firmware_restart"),
])
def test_acoes_novas(cliente, dono, klipper, corpo, esperado):
    imp = impressora(cliente, dono)
    r = cliente.post(f"/api/impressoras/{imp}/comando", headers=dono, json=corpo)
    assert r.status_code == 200, r.text
    assert script(klipper[0]) == esperado.split("|")  # mover: G90 vai numa segunda chamada


@pytest.mark.parametrize("corpo", [
    {"acao": "mover", "eixo": "X", "distancia": 101}, {"acao": "mover", "eixo": "X", "distancia": 0},
    {"acao": "mover", "eixo": "E", "distancia": 1}, {"acao": "extrudar", "distancia": 51},
    {"acao": "ventoinha", "valor": 101}, {"acao": "velocidade", "valor": 5}, {"acao": "fluxo", "valor": 151},
    {"acao": "ajuste_z", "valor": 0.6}, {"acao": "ajuste_z", "valor": 0}, {"acao": "home", "eixos": "XZ"},
    {"acao": "macro", "nome": "INEXISTENTE"}, {"acao": "macro", "nome": "LIMPAR_BICO\nM112"},
])
def test_limites_422(cliente, dono, klipper, corpo):
    imp = impressora(cliente, dono)
    assert cliente.post(f"/api/impressoras/{imp}/comando", headers=dono, json=corpo).status_code == 422
    assert klipper[0] == []


def test_gcode_livre(cliente, dono, klipper):
    imp = impressora(cliente, dono)
    assert cliente.post(f"/api/impressoras/{imp}/gcode", headers=dono, json={"script": "M115"}).status_code == 200
    assert script(klipper[0]) == ["M115"]
    r = cliente.post(f"/api/impressoras/{imp}/gcode", headers=dono, json={"script": "G1 X1\n" * 100})
    assert r.status_code == 422


def test_membro_nao_faz_nenhuma_acao(cliente, dono, membro, klipper):
    imp = impressora(cliente, dono)
    for corpo in ({"acao": "home", "eixos": "XYZ"}, {"acao": "mover", "eixo": "X", "distancia": 1},
                  {"acao": "macro", "nome": "PURGE"}):
        assert cliente.post(f"/api/impressoras/{imp}/comando", headers=membro, json=corpo).status_code == 403
    assert cliente.post(f"/api/impressoras/{imp}/gcode", headers=membro, json={"script": "M84"}).status_code == 403
    assert cliente.post(f"/api/impressoras/{imp}/arquivos/imprimir", headers=membro,
                        json={"nome": "novo.gcode"}).status_code == 403
    assert klipper[0] == []
    assert cliente.get(f"/api/impressoras/{imp}/arquivos", headers=membro).status_code == 200
    assert cliente.get(f"/api/impressoras/{imp}/macros", headers=membro).status_code == 200


def test_erro_do_klipper_chega_com_a_mensagem(cliente, dono, monkeypatch):
    def recusa(url, chave, caminho, params=None):
        raise moonraker.ErroKlipper("Must home axis first: 10.000 0.000 0.000 [0.000]")
    monkeypatch.setattr(moonraker, "comando", recusa)
    # sem isso o teste perguntava o estado à impressora real da rede (e dava 409 com ela imprimindo)
    monkeypatch.setattr(moonraker, "estado_impressao", lambda url, chave: "standby")
    imp = impressora(cliente, dono)
    r = cliente.post(f"/api/impressoras/{imp}/comando", headers=dono, json={"acao": "mover", "eixo": "X", "distancia": 10})
    assert r.status_code == 400 and r.json()["detail"] == "Klipper: Must home axis first: 10.000 0.000 0.000 [0.000]"


def test_arquivos_da_impressora(cliente, dono, klipper):
    imp = impressora(cliente, dono)
    lista = cliente.get(f"/api/impressoras/{imp}/arquivos", headers=dono).json()
    assert [a["nome"] for a in lista] == ["novo.gcode", "antigo.gcode"]
    antigo = lista[1]
    assert (antigo["tempo_estimado_s"], antigo["gramas"], antigo["miniatura"]) == (60, 1.5, ".thumbs/antigo-300x300.png")
    assert antigo["modificado"].startswith("2023-11-14")
    assert lista[0]["miniatura"] is None


@pytest.mark.parametrize("caminho", ["../../config/printer.cfg", "/etc/passwd.png", "../x.png", "printer.cfg"])
def test_miniatura_caminho_malicioso_422(cliente, dono, klipper, caminho):
    imp = impressora(cliente, dono)
    r = cliente.get(f"/api/impressoras/{imp}/arquivos/miniatura", headers=dono, params={"caminho": caminho})
    assert r.status_code == 422


def test_miniatura_ok(cliente, dono, klipper):
    imp = impressora(cliente, dono)
    r = cliente.get(f"/api/impressoras/{imp}/arquivos/miniatura", headers=dono,
                    params={"caminho": ".thumbs/antigo-300x300.png"})
    assert r.status_code == 200 and r.content == b"PNG" and r.headers["content-type"] == "image/png"


def test_imprimir_arquivo_da_impressora(cliente, dono, klipper):
    feitas, estado = klipper
    imp = impressora(cliente, dono)
    r = cliente.post(f"/api/impressoras/{imp}/arquivos/imprimir", headers=dono, json={"nome": "novo.gcode"})
    assert r.status_code == 200 and feitas == [("/printer/print/start", {"filename": "novo.gcode"})]
    estado["impressao"] = "printing"
    r = cliente.post(f"/api/impressoras/{imp}/arquivos/imprimir", headers=dono, json={"nome": "novo.gcode"})
    assert r.status_code == 409 and len(feitas) == 1
    assert cliente.post(f"/api/impressoras/{imp}/arquivos/imprimir", headers=dono,
                        json={"nome": "../printer.cfg"}).status_code == 422


def test_macros(cliente, dono, klipper):
    imp = impressora(cliente, dono)
    assert cliente.get(f"/api/impressoras/{imp}/macros", headers=dono).json() == [{"nome": "LIMPAR_BICO"}, {"nome": "PURGE"}]

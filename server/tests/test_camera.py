import uuid

import pytest

from app.klipper import moonraker

LISTA_REAL = [{"name": "Webcam", "enabled": True, "service": "mjpegstreamer",
               "stream_url": "/webcam/?action=stream", "snapshot_url": "/webcam/?action=snapshot"}]


def impressora(cliente, h):
    return cliente.put(f"/api/impressoras/{uuid.uuid4()}", headers=h,
                       json={"nome": "V3", "moonraker_url": "http://192.168.1.110:7125"}).json()


@pytest.fixture
def camera(monkeypatch):
    estado = {"fechado": False}

    async def abrir_video(url):
        assert url == "http://192.168.1.110/webcam/?action=stream"

        async def quadros():
            yield b"--frame\r\nContent-Type: image/jpeg\r\n\r\n\xff\xd8A\xff\xd9\r\n"
            yield b"--frame\r\nContent-Type: image/jpeg\r\n\r\n\xff\xd8B\xff\xd9\r\n"

        async def fechar():
            estado["fechado"] = True

        return "multipart/x-mixed-replace; boundary=frame", quadros(), fechar

    monkeypatch.setattr(moonraker, "webcam", lambda url, chave: moonraker.urls_webcam(url, LISTA_REAL))
    monkeypatch.setattr(moonraker, "foto", lambda url: b"\xff\xd8foto\xff\xd9")
    monkeypatch.setattr(moonraker, "abrir_video", abrir_video)
    return estado


def test_urls_webcam_resolvem_no_host_da_impressora():
    cam = moonraker.urls_webcam("http://192.168.1.110:7125", LISTA_REAL)
    assert cam == {"foto": "http://192.168.1.110/webcam/?action=snapshot",
                   "video": "http://192.168.1.110/webcam/?action=stream"}
    assert moonraker.urls_webcam("http://192.168.1.110:7125", [{**LISTA_REAL[0], "enabled": False}]) is None
    absoluta = [{**LISTA_REAL[0], "stream_url": "http://cam.local/s", "snapshot_url": "http://cam.local/f"}]
    assert moonraker.urls_webcam("http://192.168.1.110:7125", absoluta)["video"] == "http://cam.local/s"


def test_foto_para_membro(cliente, dono, membro, camera):
    imp = impressora(cliente, dono)
    r = cliente.get(f"/api/impressoras/{imp['id']}/camera/foto", headers=membro)
    assert r.status_code == 200 and r.headers["content-type"] == "image/jpeg" and r.content == b"\xff\xd8foto\xff\xd9"


def test_sem_camera_404(cliente, dono, monkeypatch):
    monkeypatch.setattr(moonraker, "webcam", lambda url, chave: None)
    imp = impressora(cliente, dono)
    r = cliente.get(f"/api/impressoras/{imp['id']}/camera/foto", headers=dono)
    assert r.status_code == 404 and r.json()["detail"] == "Sem câmera"


def test_video_pelo_link(cliente, dono, membro, camera):
    imp = impressora(cliente, dono)
    link = cliente.post(f"/api/impressoras/{imp['id']}/camera/link", headers=membro).json()["url"]
    assert link.startswith("/api/camera/")
    r = cliente.get(link)  # sem cabeçalho de login: o link é a autorização
    assert r.status_code == 200 and r.headers["content-type"] == "multipart/x-mixed-replace; boundary=frame"
    assert r.content.count(b"--frame") == 2
    assert camera["fechado"] is True  # a conexão com a impressora é fechada quando o repasse acaba


def test_link_de_outra_empresa_e_token_errado(cliente, dono, outro, camera):
    imp = impressora(cliente, dono)
    assert cliente.post(f"/api/impressoras/{imp['id']}/camera/link", headers=outro).status_code == 404
    acesso = dono["Authorization"].removeprefix("Bearer ")
    assert cliente.get(f"/api/camera/{acesso}").status_code == 401
    assert cliente.get("/api/camera/lixo").status_code == 401

import time
import uuid

from conftest import SENHA


def _canal(nome="Shopee", taxa=20):
    return {"nome": nome, "taxa_pct": taxa, "taxa_fixa": 4}


def test_put_idempotente(cliente, dono):
    i = uuid.uuid4()
    for _ in range(2):
        assert cliente.put(f"/api/canais/{i}", headers=dono, json=_canal()).status_code == 200
    nomes = [c["nome"] for c in cliente.get("/api/canais", headers=dono).json()]
    assert nomes.count("Shopee") == 1


def test_put_id_de_outra_empresa_404(cliente, dono, outro):
    i = uuid.uuid4()
    cliente.put(f"/api/canais/{i}", headers=dono, json=_canal())
    assert cliente.put(f"/api/canais/{i}", headers=outro, json=_canal("Hack", 99)).status_code == 404
    assert cliente.get(f"/api/canais/{i}", headers=outro).status_code == 404
    assert cliente.delete(f"/api/canais/{i}", headers=outro).status_code == 404
    c = cliente.get(f"/api/canais/{i}", headers=dono).json()
    assert (c["nome"], c["taxa_pct"], c["excluido"]) == ("Shopee", 20, False)


def test_excluido_some_da_lista_mas_get_funciona(cliente, dono):
    i = uuid.uuid4()
    cliente.put(f"/api/canais/{i}", headers=dono, json=_canal())
    assert cliente.delete(f"/api/canais/{i}", headers=dono).status_code == 200
    assert str(i) not in [c["id"] for c in cliente.get("/api/canais", headers=dono).json()]
    assert cliente.get(f"/api/canais/{i}", headers=dono).json()["excluido"] is True
    todos = cliente.get("/api/canais?incluir_excluidos=true", headers=dono).json()
    assert str(i) in [c["id"] for c in todos]


def test_atualizado_desde(cliente, dono):
    cliente.put(f"/api/canais/{uuid.uuid4()}", headers=dono, json=_canal("Antigo"))
    marco = cliente.get("/api/canais", headers=dono).json()[-1]["atualizado_em"]
    time.sleep(0.01)
    cliente.put(f"/api/canais/{uuid.uuid4()}", headers=dono, json=_canal("Novo"))
    novos = cliente.get("/api/canais", headers=dono, params={"atualizado_desde": marco}).json()
    assert [c["nome"] for c in novos] == ["Novo"]


def test_canal_direto_criado(cliente, dono):
    canais = cliente.get("/api/canais", headers=dono).json()
    assert [(c["nome"], c["taxa_pct"], c["taxa_fixa"]) for c in canais] == [("Direto", 0, 0)]


def test_impressora_custo_hora(cliente, dono):
    i = uuid.uuid4()
    r = cliente.put(f"/api/impressoras/{i}", headers=dono, json={"nome": "V3", "modelo": "Ender 3 V3"})
    assert r.status_code == 200, r.text
    imp = r.json()
    assert imp["custo_hora"] == 0.3414
    assert imp["tem_api_key"] is False and "api_key" not in imp
    imp = cliente.put(f"/api/impressoras/{i}", headers=dono, json={"api_key": "segredo"}).json()
    assert imp["tem_api_key"] is True and "api_key" not in imp and imp["nome"] == "V3"


def test_config_so_dono(cliente, dono, membro):
    cfg = cliente.get("/api/empresa/config", headers=membro).json()
    assert cfg == {"eficiencia": 1.1, "mao_obra_hora": 10, "kwh": 0.656, "reserva": 1.3, "margens": [20, 30, 50]}
    novo = {**cfg, "mao_obra_hora": 20}
    assert cliente.put("/api/empresa/config", headers=membro, json=novo).status_code == 403
    assert cliente.put("/api/empresa/config", headers=dono, json=novo).status_code == 200
    assert cliente.get("/api/empresa/config", headers=dono).json()["mao_obra_hora"] == 20

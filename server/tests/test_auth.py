from conftest import SENHA


def _login(cliente, email, senha=SENHA):
    return cliente.post("/api/auth/login", json={"email": email, "senha": senha})


def test_login_ok_e_eu(cliente, dono, empresa_a_id):
    eu = cliente.get("/api/eu", headers={"Authorization": dono["Authorization"]}).json()
    assert eu["email"] == "dono@a.com"
    assert eu["empresas"] == [{"id": str(empresa_a_id), "nome": "Empresa A", "papel": "dono"}]


def test_login_senha_errada_401(cliente, empresas):
    assert _login(cliente, "dono@a.com", "errada-errada").status_code == 401


def test_login_bloqueia_apos_5_falhas(cliente, empresas):
    for _ in range(5):
        assert _login(cliente, "dono@b.com", "errada-errada").status_code == 401
    assert _login(cliente, "dono@b.com").status_code == 429


def test_atacante_de_outro_ip_nao_trava_o_dono(cliente, empresas):
    def de(ip, senha=SENHA):
        return cliente.post("/api/auth/login", json={"email": "dono@b.com", "senha": senha},
                            headers={"CF-Connecting-IP": ip})
    for _ in range(5):
        assert de("6.6.6.6", "errada-errada").status_code == 401
    assert de("6.6.6.6").status_code == 429
    assert de("200.1.2.3").status_code == 200  # o dono, de casa, entra
    for i in range(44):  # ataque espalhado: o teto por e-mail (50) ainda segura
        de(f"10.0.{i}.1", "errada-errada")
    assert de("10.9.9.9").status_code == 429


def test_refresh(cliente, empresas):
    tokens = _login(cliente, "dono@a.com").json()
    r = cliente.post("/api/auth/refresh", json={"refresh": tokens["refresh"]})
    assert r.status_code == 200 and r.json()["acesso"]
    assert cliente.post("/api/auth/refresh", json={"refresh": tokens["acesso"]}).status_code == 401


def test_empresa_alheia_403(cliente, outro, empresa_a_id):
    h = {**outro, "X-Empresa": str(empresa_a_id)}
    assert cliente.get("/api/empresa/membros", headers=h).status_code == 403


def test_sem_token_401(cliente, empresas):
    assert cliente.get("/api/eu").status_code == 401


def test_membro_nao_adiciona_membro(cliente, membro):
    r = cliente.post("/api/empresa/membros", headers=membro,
                     json={"email": "x@a.com", "nome": "X", "senha_inicial": SENHA, "papel": "membro"})
    assert r.status_code == 403


def test_novo_membro_troca_senha(cliente, dono):
    r = cliente.post("/api/empresa/membros", headers=dono,
                     json={"email": "Novo@A.com", "nome": "Novo", "senha_inicial": SENHA, "papel": "membro"})
    assert r.status_code == 200, r.text
    nomes = [m["email"] for m in cliente.get("/api/empresa/membros", headers=dono).json()]
    assert "novo@a.com" in nomes
    tokens = _login(cliente, "novo@a.com").json()
    assert tokens["trocar_senha"] is True
    antigo = {"Authorization": f"Bearer {tokens['acesso']}"}
    r = cliente.post("/api/auth/senha", headers=antigo, json={"atual": SENHA, "nova": "outra-senha-456"})
    assert r.status_code == 200
    assert cliente.get("/api/eu", headers=antigo).status_code == 401
    novo = {"Authorization": f"Bearer {r.json()['acesso']}"}
    assert cliente.get("/api/eu", headers=novo).json()["trocar_senha"] is False


def test_nao_remove_ultimo_dono(cliente, dono):
    eu = cliente.get("/api/eu", headers=dono).json()
    assert cliente.delete(f"/api/empresa/membros/{eu['id']}", headers=dono).status_code == 409


def test_dono_remove_membro(cliente, dono):
    m = [x for x in cliente.get("/api/empresa/membros", headers=dono).json() if x["email"] == "membro@a.com"][0]
    assert cliente.delete(f"/api/empresa/membros/{m['id']}", headers=dono).status_code == 200
    assert _login(cliente, "membro@a.com").status_code == 200  # conta continua, só perde a empresa
    assert len(cliente.get("/api/empresa/membros", headers=dono).json()) == 1


def test_cadastro_fechado(cliente, empresas):
    r = cliente.post("/api/auth/cadastro", json={"nome": "Z", "email": "z@z.com", "senha": SENHA, "empresa": "Z"})
    assert r.status_code == 403


def test_senha_curta_422(cliente, dono):
    r = cliente.post("/api/empresa/membros", headers=dono,
                     json={"email": "c@a.com", "nome": "C", "senha_inicial": "123", "papel": "membro"})
    assert r.status_code == 422

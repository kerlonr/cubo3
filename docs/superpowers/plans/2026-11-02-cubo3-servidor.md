# Cubo³ — Servidor (Plano 1 de 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** API do Cubo³ (FastAPI + Postgres) com autenticação multiempresa, estoque por movimentos, catálogo com arquivos, impressões com integração Klipper, pedidos, painel financeiro e notificações ao vivo, publicada no `.150` em `https://cubo3.kerlonr.com.br`.

**Architecture:** Um processo FastAPI (`server/app`) com um módulo por domínio (auth, estoque, catalogo, impressoes, klipper, vendas, financeiro). Todas as tabelas de negócio herdam `DaEmpresa` e todo acesso passa por `Ctx` (usuário + empresa). Criações usam `PUT /{id}` com UUID gerado pelo cliente, o que torna a fila offline do app idempotente. O worker Klipper roda no mesmo processo (asyncio). Deploy em Docker Compose (api, db, backup, tunnel).

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, Pydantic v2, Alembic, psycopg 3, PyJWT, argon2-cffi, python-multipart, httpx, websockets, pytest. Postgres 16. cloudflared.

**Spec:** `docs/superpowers/specs/2026-11-02-cubo3-design.md` (leia antes de começar). O Plano 2 (app Flutter) será escrito depois que este estiver no ar.

## Global Constraints

- Commits **somente no nome do Kerlon** (git config já está certo). Nunca `Co-Authored-By`, nunca mencionar Claude. Mensagens em português, estilo `feat: ...`, `fix: ...`, `chore: ...`.
- Identificadores, rotas e mensagens de erro em português (padrão do Meu Frete). Comentários só para o porquê.
- Toda tabela de negócio: `id` UUID (aceito do cliente), `empresa_id`, `criado_em`, `atualizado_em` (UTC), `excluido` (soft delete). Toda consulta filtra `empresa_id` **e** `excluido = false` (exceto quando resolvendo referência histórica).
- Percentuais na API e no banco sempre em 0–100 (`taxa_pct: 20` = 20%). Multiplicadores (`eficiencia` 1,1, `reserva` 1,3) como número.
- Dinheiro: `Decimal` nos cálculos, `Numeric(12,4)` no banco, número JSON arredondado a 2 casas (ROUND_HALF_UP) nas respostas. Arredondar só a saída final; nunca somar valores já arredondados para formar outro total (exceto onde o teste fixa).
- Relatórios agrupam datas no fuso `America/Sao_Paulo`; banco guarda UTC.
- Upload: limite padrão **95 MB** por arquivo (o túnel Cloudflare gratuito corta requisições acima de 100 MB; a spec dizia 200 MB — decisão do builder, registrar na spec). Extensões aceitas: `.stl .3mf .gcode .obj .step .stp .png .jpg .jpeg .webp`.
- Senha mínima: 8 caracteres. Login: 5 falhas por e-mail em 15 min → 429.
- No `.150`: pasta `/home/server/projects/cubo3`, API só em `127.0.0.1:8096`, volumes por **caminho absoluto**, túnel próprio `cubo3`. Não tocar em nenhum outro serviço, túnel ou compose. Docker exige `sudo` (senha): peça ao Kerlon para rodar o comando, ou use a senha que ele forneceu na conversa via `sudo -S` sem gravá-la em arquivo, script, log ou commit.
- Segredos (`.env`, credenciais do túnel) nunca entram no git.
- Testes rodam localmente em SQLite (`TEST_DATABASE_URL` vazio) e no servidor contra Postgres (Task 11). Não usar recursos exclusivos do Postgres nos modelos.

## Review Focus

1. **Arquivo maior que o limite pelo túnel** — upload de 120 MB: a API deve recusar com 413 e mensagem clara antes de gravar o arquivo inteiro, sem deixar arquivo parcial no disco. Teste em Task 6.
2. **Virada de mês no fuso** — venda entregue às 23:30 de 31/out em Brasília (02:30Z de 1/nov) conta em outubro no painel. Teste em Task 9.
3. **Evento repetido do Klipper** — Moonraker reenviando o mesmo `finished` (reconexão) ou trazer manualmente um trabalho já registrado não pode criar duas impressões. Teste em Task 10.
4. **Item excluído com histórico** — filamento/modelo/cliente excluído continua resolvendo em carretéis, impressões e pedidos antigos (nome aparece), mas some das listas. Teste em Task 5 (filamento) e Task 8 (modelo em pedido).
5. **Venda sem estoque** — entregar pedido de modelo com 0 peças prontas é permitido, estoque fica negativo e a resposta traz aviso. Teste em Task 8.

---

## Estrutura de arquivos

```
server/
  requirements.txt            requirements-dev.txt     Dockerfile   alembic.ini
  migrations/                 (Alembic, Task 11)
  app/
    main.py        config.py      db.py        crud.py      custos.py     cli.py    ao_vivo.py
    auth/          modelos.py  seguranca.py  deps.py  servico.py  rotas.py
    empresa/       rotas.py (config da empresa, canais, impressoras)  modelos.py
    estoque/       modelos.py  servico.py  rotas.py
    catalogo/      modelos.py  custo.py    arquivos.py  rotas.py  calculadora.py
    impressoes/    modelos.py  servico.py  rotas.py
    klipper/       moonraker.py  monitor.py  servico.py  rotas.py
    vendas/        modelos.py  servico.py  rotas.py
    financeiro/    modelos.py  painel.py   rotas.py
  tests/           conftest.py  fixtures/moonraker_historico.json  test_<modulo>.py
deploy/
  docker-compose.yml  .env.example  backup.sh  deploy.sh  tunnel/config.yml.example
docs/servidor.md
```

---

### Task 1: Esqueleto da API e base do banco

**Files:**
- Create: `server/requirements.txt`, `server/requirements-dev.txt`, `server/app/main.py`, `server/app/config.py`, `server/app/db.py`, `server/tests/conftest.py`, `server/tests/test_saude.py`

**Interfaces:**
- Produces:
  - `app.config.config() -> Config` (cacheado; lê env). Campos: `database_url` (padrão `sqlite+pysqlite:///./cubo3.db`), `jwt_segredo` (obrigatório fora de teste), `cadastro_aberto: bool=False`, `arquivos_dir: Path`, `web_dir: Path|None`, `apk_dir: Path|None`, `max_upload_mb: int=95`, `fuso: str="America/Sao_Paulo"`.
  - `app.db`: `Base(DeclarativeBase)`; `UtcDateTime` (TypeDecorator que sempre devolve datetime aware UTC, inclusive no SQLite); mixin `Registro` (`id: Uuid pk default uuid4`, `criado_em`, `atualizado_em` com onupdate, `excluido: bool=False`); mixin `DaEmpresa(Registro)` (+ `empresa_id: Uuid FK empresas.id, index`); `get_db()` dependency (Session); `agora() -> datetime` UTC.
  - `app.main.criar_app() -> FastAPI`; `app = criar_app()`; `GET /api/saude -> {"ok": true}`.
  - `tests/conftest.py`: fixture `db` (Session; engine de `TEST_DATABASE_URL` ou SQLite em `tmp_path`; `create_all` antes, `drop_all` depois) e fixture `cliente` (`TestClient` com `get_db` sobrescrito).

- [ ] **Step 1: Teste** `test_saude`: `cliente.get("/api/saude").json() == {"ok": True}`; e `test_utc_datetime`: grava um `Registro` concreto de teste com `criado_em`, relê e confere `obj.criado_em.tzinfo is not None`.
- [ ] **Step 2:** `cd server && python -m pytest -q` → FAIL (módulos não existem).
- [ ] **Step 3:** Implementar `config.py`, `db.py`, `main.py` conforme Interfaces. Criar venv em `server/.venv` com `requirements-dev.txt` (inclui `-r requirements.txt`, pytest, httpx).
- [ ] **Step 4:** `python -m pytest -q` → PASS.
- [ ] **Step 5:** Commit `chore: esqueleto da API do Cubo³`.

---

### Task 2: Cálculo de custos (fiel à planilha)

**Files:**
- Create: `server/app/custos.py`, `server/tests/test_custos.py`

**Interfaces:**
- Produces (`app.custos`, tudo `Decimal`):
  - `@dataclass(frozen=True) ParamEmpresa(eficiencia=1.1, mao_obra_hora=10, kwh=0.656, reserva=1.3, margens=(20, 30, 50))`
  - `@dataclass(frozen=True) ParamImpressora(preco=1660, adicionais=0, manutencao_pct_ano=10, vida_anos=3, uso_pct=50, potencia_w=150)`
  - `custo_hora_impressora(imp: ParamImpressora, emp: ParamEmpresa) -> Decimal` (sem arredondar; fórmulas da spec §7)
  - `@dataclass ItemFilamento(gramas, preco_kg)`; `@dataclass ItemCusto(qtd, custo_unitario)`
  - `@dataclass Receita(filamentos: list[ItemFilamento], horas, mao_obra_min, insumos: list[ItemCusto]=[], embalagem: list[ItemCusto]=[], custo_envio=0, aplicar_eficiencia: bool=True)`
  - `@dataclass Custo(material, mao_obra, maquina, insumos, embalagem, total)` — cada campo arredondado a 0,01; `total` = soma dos valores **não** arredondados, arredondada.
  - `calcular_custo(r: Receita, imp: ParamImpressora, emp: ParamEmpresa) -> Custo`
  - `preco_com_margem(custo, margem_pct) -> Decimal` = custo / (1 − m/100), 2 casas
  - `preco_com_canal(custo, margem_pct, taxa_pct, taxa_fixa) -> Decimal` = (custo + fixa)/(1 − m/100 − t/100), 2 casas; `ValueError` se denominador ≤ 0
  - `lucro_venda(preco, custo, taxa_pct, taxa_fixa) -> Decimal`, 2 casas

- [ ] **Step 1: Testes** (`D = Decimal`):

```python
def test_custo_hora_planilha():
    h = custo_hora_impressora(ParamImpressora(), ParamEmpresa())
    assert h.quantize(D("0.0001")) == D("0.3414")

def test_peca_da_planilha():
    r = Receita([ItemFilamento(D(33), D(100))], horas=D(3), mao_obra_min=D(10))
    c = calcular_custo(r, ParamImpressora(), ParamEmpresa())
    assert (c.material, c.mao_obra, c.maquina, c.total) == (D("3.63"), D("1.67"), D("1.02"), D("6.32"))
    assert [preco_com_margem(c.total, m) for m in (20, 30, 50)] == [D("7.90"), D("9.03"), D("12.64")]

def test_sem_eficiencia_e_extras():
    r = Receita([ItemFilamento(D(33), D(100))], horas=D(0), mao_obra_min=D(0),
                insumos=[ItemCusto(D(4), D("0.50"))], embalagem=[ItemCusto(D(1), D("1.20"))],
                custo_envio=D(5), aplicar_eficiencia=False)
    c = calcular_custo(r, ParamImpressora(), ParamEmpresa())
    assert (c.material, c.insumos, c.embalagem, c.total) == (D("3.30"), D("2.00"), D("6.20"), D("11.50"))

def test_canal_e_lucro():
    assert preco_com_canal(D("6.32"), 30, 20, D(4)) == D("20.64")
    assert lucro_venda(D("12.64"), D("6.32"), 20, D(4)) == D("-0.21")
    with pytest.raises(ValueError):
        preco_com_canal(D(1), 60, 40, D(0))
```

(`embalagem` inclui `custo_envio`.)
- [ ] **Step 2:** `python -m pytest tests/test_custos.py -q` → FAIL.
- [ ] **Step 3:** Implementar `app/custos.py`.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: cálculo de custo igual à planilha`.

---

### Task 3: Usuários, empresas e login

**Files:**
- Create: `server/app/auth/{modelos,seguranca,deps,servico,rotas}.py`, `server/app/cli.py`, `server/tests/test_auth.py`
- Modify: `server/app/main.py` (incluir router), `server/tests/conftest.py` (fixtures de usuários)

**Interfaces:**
- Consumes: `Registro`, `get_db`, `config()`.
- Produces:
  - Modelos: `Usuario(Registro)`: `email` (único, minúsculo), `nome`, `senha_hash`, `token_versao: int=0`, `trocar_senha: bool`. `Empresa(Registro)`: `nome`, `config: JSON` (campos de `ParamEmpresa`, percentuais 0–100). `Membro(Registro)`: `usuario_id`, `empresa_id`, `papel: "dono"|"membro"`, único (usuario, empresa).
  - `seguranca`: `hash_senha(s) -> str` (argon2), `confere_senha(s, h) -> bool`, `emitir_tokens(u) -> {"acesso", "refresh"}` (acesso 30 min, refresh 60 dias, claims `sub`, `tipo`, `v`=token_versao), `ler_token(t, tipo) -> dict` (401 se inválido/expirado/tipo errado).
  - `deps`: `@dataclass Ctx(usuario: Usuario, empresa_id: UUID, papel: str)`; `usuario_atual` (Bearer; 401 se `v` ≠ `token_versao`); `ctx` (lê header `X-Empresa`; 403 se não for membro); `so_dono(ctx) -> Ctx` (403 se papel ≠ dono).
  - `servico`: `criar_dono(db, email, nome, senha, empresa_nome) -> tuple[Usuario, Empresa]` (cria também canal "Direto" 0%/0 depois que a Task 4 existir — deixe um gancho `ao_criar_empresa: list[Callable[[Session, Empresa], None]]`); `adicionar_membro(db, empresa_id, email, nome, senha_inicial, papel="membro") -> Membro` (`trocar_senha=True`; se o e-mail já existe, só vincula).
  - Rotas: `POST /api/auth/login {email, senha} -> {acesso, refresh, trocar_senha}`; `POST /api/auth/refresh {refresh} -> {acesso, refresh}`; `POST /api/auth/senha {atual, nova}` (incrementa `token_versao`, zera `trocar_senha`, devolve tokens novos); `GET /api/eu -> {id, nome, email, trocar_senha, empresas: [{id, nome, papel}]}`; `GET /api/empresa/membros`; `POST /api/empresa/membros {email, nome, senha_inicial, papel}` (dono); `DELETE /api/empresa/membros/{usuario_id}` (dono; 409 ao remover o último dono); `POST /api/auth/cadastro {nome, email, senha, empresa}` (403 se `cadastro_aberto` falso).
  - `python -m app.cli criar-dono --email E --nome N --empresa "Cubo³"` (senha via `getpass`, pedida duas vezes).
  - Fixtures conftest: `dono` → `dict` de headers (`Authorization`, `X-Empresa`) do dono da empresa A; `membro` → headers de um membro da A; `outro` → headers do dono da empresa B; `empresa_a_id`.

- [ ] **Step 1: Testes** em `test_auth.py`:
  - `test_login_ok_e_eu`: login devolve tokens; `GET /api/eu` lista a empresa A com papel `dono`.
  - `test_login_senha_errada_401` e `test_login_bloqueia_apos_5_falhas`: 6ª tentativa (mesmo com senha certa) → 429.
  - `test_empresa_alheia_403`: headers do dono B com `X-Empresa` = A → 403 em `GET /api/empresa/membros`.
  - `test_membro_nao_adiciona_membro`: 403.
  - `test_novo_membro_troca_senha`: dono adiciona; login do novo → `trocar_senha: true`; após `POST /api/auth/senha`, token antigo → 401.
  - `test_nao_remove_ultimo_dono`: 409.
  - `test_cadastro_fechado`: 403.
  - `test_senha_curta_422`.
- [ ] **Step 2:** → FAIL.
- [ ] **Step 3:** Implementar. Limite de tentativas em memória (dict email → timestamps), suficiente para um processo.
- [ ] **Step 4:** → PASS (todas as tasks anteriores também).
- [ ] **Step 5:** Commit `feat: login, empresas e membros`.

---

### Task 4: CRUD genérico, configuração da empresa, canais e impressoras

**Files:**
- Create: `server/app/crud.py`, `server/app/empresa/{modelos,rotas}.py`, `server/tests/test_crud_empresa.py`

**Interfaces:**
- Consumes: `Ctx`, `ctx`, `so_dono`, `DaEmpresa`, `custos.*`, gancho `ao_criar_empresa`.
- Produces:
  - `crud.rotas_crud(modelo: type[DaEmpresa], entrada: type[BaseModel], saida: Callable[[Session, Any], dict], prefixo: str, *, so_dono_escreve=False, ao_salvar: Callable[[Session, Ctx, Any, bool], None] | None = None) -> APIRouter` com:
    - `GET {prefixo}?atualizado_desde=ISO&incluir_excluidos=false` → lista
    - `GET {prefixo}/{id}` → 404 se de outra empresa (ou inexistente); devolve mesmo se `excluido` (referência histórica)
    - `PUT {prefixo}/{id}` → upsert; `ao_salvar(db, ctx, obj, criado)` depois do flush; **se o id existe em outra empresa → 404 e nada muda**
    - `DELETE {prefixo}/{id}` → `excluido=True`
  - `crud.obter(db, ctx, modelo, id) -> obj` (404 cross-tenant) — usado pelos módulos seguintes.
  - Config: `GET /api/empresa/config`, `PUT /api/empresa/config` (dono) com `{eficiencia, mao_obra_hora, kwh, reserva, margens}`; padrões = `ParamEmpresa()`. `param_empresa(db, empresa_id) -> ParamEmpresa`.
  - `CanalVenda(DaEmpresa)`: `nome`, `taxa_pct`, `taxa_fixa`. Rotas `/api/canais`. Canal "Direto" (0, 0) criado via gancho `ao_criar_empresa`.
  - `Impressora(DaEmpresa)`: `nome`, `modelo`, `preco`, `adicionais`, `manutencao_pct_ano`, `vida_anos`, `uso_pct`, `potencia_w` (padrões = `ParamImpressora()`), `moonraker_url: str|None`, `api_key: str|None`. Saída sem `api_key`; inclui `tem_api_key: bool` e `custo_hora` (exceção à regra de 2 casas: 4 casas, ex. `0.3414`). `param_impressora(imp) -> ParamImpressora`. Rotas `/api/impressoras`.

- [ ] **Step 1: Testes**:
  - `test_put_idempotente`: dois `PUT /api/canais/{id}` iguais → 1 item na lista.
  - `test_put_id_de_outra_empresa_404`: B faz PUT no id de um canal da A → 404; A relê o canal inalterado.
  - `test_excluido_some_da_lista_mas_get_funciona`.
  - `test_atualizado_desde`: só itens alterados depois do timestamp.
  - `test_canal_direto_criado`: empresa nova já tem "Direto".
  - `test_impressora_custo_hora`: PUT com padrões → `custo_hora == 0.3414`; `api_key` não aparece; `tem_api_key` true quando informada.
  - `test_config_so_dono`: membro → 403 no PUT; GET devolve padrões da planilha.
- [ ] **Step 2:** → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: CRUD genérico, canais e impressoras`.

---

### Task 5: Estoque por movimentos

**Files:**
- Create: `server/app/estoque/{modelos,servico,rotas}.py`, `server/tests/test_estoque.py`

**Interfaces:**
- Consumes: `rotas_crud`, `obter`, `Ctx`.
- Produces:
  - `Filamento(DaEmpresa)`: `marca`, `material`, `cor_nome`, `cor_hex`, `diametro=1.75`, `densidade=1.24`, `preco_kg`, `peso_carretel_vazio_g: Decimal|None`, `estoque_minimo_g=0`.
  - `Carretel(DaEmpresa)`: `filamento_id`, `peso_inicial_g`, `preco_pago`, `data_compra: date`, `local`, `aberto: bool`, `arquivado: bool`. Propriedade de serviço `preco_kg_real = preco_pago / peso_inicial_g × 1000`.
  - `Insumo(DaEmpresa)`: `nome`, `unidade`, `categoria: "insumo"|"embalagem"`, `custo_unitario`, `estoque_minimo=0`.
  - `Movimento(DaEmpresa)`: `item_tipo: "carretel"|"insumo"|"peca"`, `item_id` (para `peca` = `modelo_id`), `tipo: "compra"|"consumo"|"perda"|"ajuste"|"producao"|"venda"`, `quantidade` (com sinal; gramas para carretel), `valor: Decimal|None` (dinheiro total do movimento), `impressao_id`, `pedido_id`, `usuario_id`, `data`.
  - `servico.lancar(db, ctx, *, id, item_tipo, item_id, tipo, quantidade, valor=None, impressao_id=None, pedido_id=None, data=None) -> Movimento` — idempotente por `id`; valida sinal (`compra`/`producao` > 0; `consumo`/`perda`/`venda` < 0; `ajuste` ≠ 0) → `ValueError` vira 422.
  - `servico.saldo(db, empresa_id, item_tipo, item_id) -> Decimal`; `servico.saldos(db, empresa_id, item_tipo) -> dict[UUID, Decimal]`; `servico.custo_medio_peca(db, empresa_id, modelo_id) -> Decimal|None` (Σ valor de `producao` / Σ quantidade de `producao`).
  - `servico.id_derivado(base: UUID, chave: str) -> UUID` = `uuid5(base, chave)` — usado por todas as tasks para movimentos automáticos.
  - Carretel criado (`ao_salvar`, `criado=True`) → movimento `compra` id `id_derivado(carretel.id, "compra")`, `+peso_inicial_g`, `valor=preco_pago`, `data=data_compra`.
  - Rotas: CRUD `/api/filamentos`, `/api/carreteis` (saída com `saldo_g` e `filamento` resumido, mesmo se o filamento estiver excluído), `/api/insumos` (saída com `saldo`); `PUT /api/movimentos/{id}`; `GET /api/movimentos?item_tipo=&item_id=`; `POST /api/carreteis/{id}/pesagem {movimento_id, peso_balanca_g}` → ajuste = `(peso_balanca_g − peso_carretel_vazio_g) − saldo` (422 se `peso_carretel_vazio_g` nulo; sem movimento se diferença 0); `GET /api/estoque -> {carreteis: [...], filamentos: [{id, nome, total_g, baixo}], insumos: [{id, nome, saldo, baixo}], pecas: [{modelo_id, saldo}]}`.

- [ ] **Step 1: Testes**:
  - `test_compra_automatica_e_consumo`: carretel 1000 g/R$ 100 → saldo 1000; movimento consumo −33 → 967.
  - `test_pesagem`: filamento com vazio 200, saldo 967, balança 900 → ajuste −267, saldo 700.
  - `test_movimento_idempotente`: mesmo `PUT /api/movimentos/{id}` duas vezes → saldo muda uma vez.
  - `test_sinal_invalido_422`: consumo com quantidade positiva.
  - `test_estoque_baixo`: filamento mínimo 500, total 400 → `baixo: true`.
  - `test_filamento_excluido_resolve_no_carretel` (Review Focus 4): excluir filamento → some de `GET /api/filamentos`, mas `GET /api/carreteis/{id}` ainda traz `filamento.material`.
  - `test_carretel_outra_empresa`: B não lança movimento em carretel da A → 404.
- [ ] **Step 2:** → FAIL. **Step 3:** Implementar. **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: estoque de filamento, insumos e peças por movimentos`.

---

### Task 6: Catálogo, arquivos e calculadora

**Files:**
- Create: `server/app/catalogo/{modelos,custo,arquivos,rotas,calculadora}.py`, `server/tests/test_catalogo.py`

**Interfaces:**
- Consumes: `custos.*`, `param_empresa`, `param_impressora`, `Filamento`, `Insumo`, `CanalVenda`, `saldo`, `rotas_crud`, `obter`.
- Produces:
  - `Modelo(DaEmpresa)`: `nome`, `descricao`, `categoria`, `tags: JSON list[str]`, `links: JSON list[{titulo, url}]`, `receita: JSON {filamentos: [{filamento_id, gramas}], horas, mao_obra_min, insumos: [{insumo_id, qtd}], custo_envio}`, `impressora_id|None`, `preco_venda|None`, `nomes_arquivo: JSON list[str]`, `capa_id|None`.
  - `Arquivo(DaEmpresa)`: `modelo_id`, `nome_original`, `tipo: "stl"|"3mf"|"gcode"|"obj"|"step"|"foto"`, `tamanho`, `caminho` (relativo a `arquivos_dir`: `{empresa_id}/{modelo_id}/{arquivo_id}{ext}`).
  - `custo.custo_do_modelo(db, empresa_id, modelo) -> Custo` (preços de `Filamento.preco_kg` e `Insumo.custo_unitario`; impressora = `modelo.impressora_id`, senão a primeira ativa da empresa, senão `ParamImpressora()`; insumos com `categoria=embalagem` vão para `embalagem`).
  - Saída de modelo: campos + `custo` (objeto `Custo`), `lucro_unitario` (`preco_venda − custo.total` ou null), `estoque` (saldo de `peca`), `vendidos: 0` (Task 8 preenche), `arquivos: [...]`, `capa_url`.
  - Rotas: CRUD `/api/modelos` com `?busca=&categoria=&tag=&ordem=nome|recentes`; `POST /api/modelos/{id}/arquivos` (multipart `arquivo`; primeira foto vira capa se `capa_id` nulo); `GET /api/arquivos/{id}` (download, `Content-Disposition` com nome original); `DELETE /api/arquivos/{id}` (apaga do disco).
  - `arquivos.salvar_upload(upload: UploadFile, destino: Path, limite_bytes: int) -> int` — grava em blocos de 1 MiB num arquivo `.parcial`, aborta com 413 ao passar do limite (apagando o parcial), renomeia no fim; devolve o tamanho.
  - `POST /api/calculadora` `{filamentos: [{filamento_id?|preco_kg, gramas}], horas, mao_obra_min, insumos: [{insumo_id?|custo_unitario, qtd, embalagem: bool}], custo_envio, impressora_id?}` → `{custo, precos: [{margem, preco}], por_canal: [{canal_id, nome, margem, preco, lucro}]}` (margens da config; `por_canal` usa a margem do meio).

- [ ] **Step 1: Testes**:
  - `test_calculadora_planilha`: `{filamentos:[{preco_kg:100, gramas:33}], horas:3, mao_obra_min:10}` sem impressora cadastrada → `custo.total == 6.32`, `precos == [7.90, 9.03, 12.64]`.
  - `test_custo_do_modelo_igual_calculadora`: modelo com receita equivalente (filamento R$ 100/kg) → mesmo `custo.total`.
  - `test_upload_e_download`: STL pequeno → 200; download devolve os mesmos bytes; foto vira capa.
  - `test_upload_grande_413` (Review Focus 1): `max_upload_mb=1` via override, 2 MiB → 413 e nenhum arquivo (nem `.parcial`) no diretório.
  - `test_extensao_proibida_415`: `.exe`.
  - `test_download_outra_empresa_404`.
  - `test_busca_e_tag`.
- [ ] **Step 2:** → FAIL. **Step 3:** Implementar. **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: catálogo de modelos, arquivos e calculadora`.

---

### Task 7: Impressões e confirmação

**Files:**
- Create: `server/app/impressoes/{modelos,servico,rotas}.py`, `server/tests/test_impressoes.py`

**Interfaces:**
- Consumes: `lancar`, `id_derivado`, `Carretel.preco_kg_real`, `custo_hora_impressora`, `param_*`, `obter`, `rotas_crud`.
- Produces:
  - `Impressao(DaEmpresa)`: `impressora_id|None`, `modelo_id|None`, `origem: "manual"|"klipper"`, `job_id|None` (único com `impressora_id`), `arquivo`, `inicio`, `fim`, `duracao_s`, `status: "a_confirmar"|"confirmada"|"arquivada"|"descartada"`, `situacao_klipper|None`, `finalidade: "venda"|"pessoal"|"teste"|"falhou"|None`, `pecas_boas: int`, `estimativa: JSON {gramas_total, filamentos: [{tipo, marca, cor, gramas|None}]}`, `miniatura: str|None` (caminho relativo), `custo_total|None`, `custo_unitario|None`, `confirmada_por|None`, `confirmada_em|None`.
  - `Confirmacao(BaseModel)`: `finalidade`, `pecas_boas: int=0`, `consumos: list[{carretel_id, gramas}]`, `perdas: list[{carretel_id, gramas}]=[]`, `mao_obra_min: Decimal|None`, `modelo_id: UUID|None`.
  - `servico.confirmar(db, ctx, imp, dados: Confirmacao) -> Impressao`:
    - já `confirmada` → devolve sem mudar nada (idempotente para a fila offline);
    - movimentos `consumo` e `perda` (ids `id_derivado(imp.id, f"consumo:{carretel_id}")` / `"perda:..."`), carretéis validados na empresa (404);
    - custo = Σ gramas(consumo+perda) × `preco_kg_real`/1000 (sem eficiência) + horas(`duracao_s`) × `custo_hora` da impressora + `mao_obra_min` (ou o da receita do modelo, ou 0)/60 × `mao_obra_hora` + insumos da receita × `pecas_boas`;
    - `finalidade == "venda"` com modelo e `pecas_boas > 0` → movimento `producao` de `peca` (`+pecas_boas`, `valor = custo_total`, id `id_derivado(imp.id, "producao")`);
    - modelo informado e `arquivo` fora de `nomes_arquivo` → acrescenta.
  - `servico.descartar(db, ctx, imp)` → `status="descartada"`, nenhum movimento.
  - `servico.casar_modelo(db, empresa_id, arquivo) -> UUID|None` (igualdade exata em `nomes_arquivo`).
  - Rotas: CRUD `/api/impressoes` (`?status=`; PUT manual nasce `a_confirmar`, `origem="manual"`); `POST /api/impressoes/{id}/confirmar`; `POST /api/impressoes/{id}/descartar`; `GET /api/impressoes/{id}/miniatura`.

- [ ] **Step 1: Testes**:
  - `test_confirmar_gera_custo_e_estoque`: impressora padrão, carretel 1000 g por R$ 100, impressão manual 3 h (`duracao_s=10800`), modelo com receita `mao_obra_min=10`; confirmar `{finalidade:"venda", pecas_boas:1, consumos:[{carretel, 33}]}` → `custo_total == 5.99`, saldo carretel 967, saldo `peca` do modelo 1, `custo_medio_peca == 5.99`.
  - `test_perda_entra_no_custo_e_no_estoque`: consumo 33 + perda 10 → saldo 957.
  - `test_confirmar_duas_vezes`: segundo POST → mesmo resultado, saldo continua 967.
  - `test_descartar_sem_movimentos`.
  - `test_aprende_nome_do_arquivo`: confirmar com `modelo_id` → `casar_modelo(arquivo)` devolve o modelo.
  - `test_carretel_de_outra_empresa_404`.
- [ ] **Step 2:** → FAIL. **Step 3:** Implementar. **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: impressões com confirmação e baixa de estoque`.

---

### Task 8: Clientes, pedidos e vendas

**Files:**
- Create: `server/app/vendas/{modelos,servico,rotas}.py`, `server/tests/test_vendas.py`
- Modify: `server/app/catalogo/rotas.py` (ordens `mais_vendidos`, `lucro`, campo `vendidos`, parâmetro `periodo_dias`)

**Interfaces:**
- Consumes: `lancar`, `saldo`, `custo_medio_peca`, `custo_do_modelo`, `CanalVenda`, `id_derivado`.
- Produces:
  - `Cliente(DaEmpresa)`: `nome`, `telefone`, `email`, `obs`.
  - `Pedido(DaEmpresa)`: `cliente_id|None`, `canal_id|None`, `status: "orcamento"|"aprovado"|"produzindo"|"pronto"|"entregue"|"cancelado"`, `desconto=0`, `frete_cobrado=0`, `custo_envio=0`, `pago: bool`, `forma_pagamento|None`, `data`, `entregue_em|None`; congelados na entrega: `taxa_pct`, `taxa_fixa`, `bruto`, `receita`, `custo_itens`, `taxas`, `lucro`.
  - `PedidoItem(DaEmpresa)`: `pedido_id`, `modelo_id|None`, `descricao`, `quantidade`, `preco_unitario`, `custo_unitario|None` (congelado).
  - Fórmulas: `bruto = Σ qtd × preco`; `receita = bruto − desconto + frete_cobrado`; `taxas = bruto × taxa_pct/100 + taxa_fixa`; `lucro = receita − custo_itens − taxas − custo_envio`. Custo do item = `custo_medio_peca` do modelo, senão `custo_do_modelo().total`, senão 0.
  - `servico.salvar_pedido(db, ctx, id, dados) -> (Pedido, avisos: list[str])`: `PUT /api/pedidos/{id}` com `itens` (substitui itens enquanto não entregue; 409 se tentar mudar itens de pedido entregue). Se vier `status="entregue"` (venda rápida) executa `entregar`.
  - `servico.mudar_status(db, ctx, pedido, status) -> (Pedido, avisos)`:
    - → `entregue`: congela custos/taxas, `entregue_em=agora`, movimento `venda` por item com modelo (id `id_derivado(item.id, "venda")`, `−qtd`, `valor = custo_unitario × qtd`); aviso `"Estoque de <modelo> ficou em <n>"` quando saldo < 0;
    - `entregue` → `cancelado`: movimento `ajuste` `+qtd` (id `id_derivado(item.id, "estorno")`);
    - repetir o mesmo status → nada muda.
  - Rotas: CRUD `/api/clientes`; `GET /api/clientes/{id}/historico -> {cliente, pedidos, total_comprado}`; `PUT /api/pedidos/{id}`, `GET /api/pedidos?status=&cliente_id=`, `GET /api/pedidos/{id}`, `POST /api/pedidos/{id}/status {status}`. Respostas de escrita incluem `avisos`.
  - Catálogo: `vendidos` = Σ quantidade de itens de pedidos `entregue` no período; `ordem=mais_vendidos` (desc) e `ordem=lucro` (Σ (preço − custo) × qtd, desc); `periodo_dias` nulo = sempre.

- [ ] **Step 1: Testes**:
  - `test_venda_rapida_lucro`: modelo com 1 peça produzida a custo 6.32 (movimento `producao` direto), venda rápida canal Direto, 2 × 12,64, `custo_envio=5` → `bruto 25.28`, `custo_itens 12.64`, `lucro 7.64`.
  - `test_venda_sem_estoque_avisa` (Review Focus 5): o mesmo pedido → saldo da peça −1 e `avisos` não vazio.
  - `test_cancelar_estorna`: cancelar → saldo volta a 1; cancelar de novo → continua 1.
  - `test_taxa_do_canal_congelada`: mudar a taxa do canal depois da entrega não altera `lucro` do pedido.
  - `test_itens_de_pedido_entregue_409`.
  - `test_modelo_excluido_no_pedido` (Review Focus 4): excluir o modelo → `GET /api/pedidos/{id}` ainda mostra `descricao` e `modelo.nome`.
  - `test_mais_vendidos`: modelos X (3 vendidos), Y (1) → `GET /api/modelos?ordem=mais_vendidos` começa por X; `vendidos == 3`.
  - `test_historico_cliente`: `total_comprado` = soma das receitas entregues.
- [ ] **Step 2:** → FAIL. **Step 3:** Implementar. **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: clientes, pedidos e vendas`.

---

### Task 9: Despesas e painel

**Files:**
- Create: `server/app/financeiro/{modelos,painel,rotas}.py`, `server/tests/test_painel.py`

**Interfaces:**
- Consumes: `Movimento`, `Pedido`, `PedidoItem`, `Impressao`, `saldos`, `config().fuso`.
- Produces:
  - `Despesa(DaEmpresa)`: `data: date`, `categoria: "equipamento"|"manutencao"|"energia"|"ferramenta"|"outros"`, `valor`, `descricao`. CRUD `/api/despesas`.
  - `painel.calcular(db, empresa_id, inicio: date, fim: date, fuso: str) -> dict` (intervalo inclusivo em dias locais):
    `{receita, gastos, resultado, lucro_vendas, por_mes: [{mes: "AAAA-MM", receita, gastos}] (12 meses terminando no mês de fim), mais_vendidos: [{modelo_id, nome, qtd}] (top 5), a_confirmar: int, estoque_baixo: [{tipo, id, nome, saldo}], horas_impressao, kg_filamento}`
    - receita/lucro: pedidos `entregue` com `entregue_em` no período (convertido ao fuso);
    - gastos: despesas + movimentos `compra` com `valor` no período;
    - horas: Σ `duracao_s` das impressões `confirmada` com `fim` no período / 3600;
    - kg: |Σ consumo + perda de carretel| no período / 1000.
  - `GET /api/painel?inicio=&fim=` (padrão: mês atual no fuso).

- [ ] **Step 1: Testes**:
  - `test_painel_numeros`: carretel R$ 100 comprado no mês, despesa R$ 50, venda do Task 8 (receita 25,28, lucro 7,64), impressão confirmada de 3 h e 33 g → `receita 25.28`, `gastos 150.00`, `resultado -124.72`, `lucro_vendas 7.64`, `horas_impressao 3.0`, `kg_filamento 0.033`.
  - `test_virada_de_mes_no_fuso` (Review Focus 2): pedido com `entregue_em = 2026-11-01T02:30Z` → conta em outubro/2026, não em novembro.
  - `test_a_confirmar_ignora_arquivadas`.
  - `test_por_mes_tem_12_meses`.
- [ ] **Step 2:** → FAIL. **Step 3:** Implementar. **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: despesas e painel financeiro`.

---

### Task 10: Integração Klipper e eventos ao vivo

**Files:**
- Create: `server/app/klipper/{moonraker,monitor,servico,rotas}.py`, `server/app/ao_vivo.py`, `server/tests/fixtures/moonraker_historico.json`, `server/tests/test_klipper.py`
- Modify: `server/app/main.py` (lifespan inicia/para `GerenciadorMonitores`), `server/app/empresa/rotas.py` (`ao_salvar` de impressora reinicia o monitor dela)

**Interfaces:**
- Consumes: `Impressao`, `casar_modelo`, `Impressora`, `ler_token`, `Membro`, `config().arquivos_dir`.
- Produces:
  - `moonraker.DadosTrabalho` (dataclass): `job_id, arquivo, status, inicio, fim, duracao_s, gramas_total|None, filamentos: list[{tipo, marca, cor, gramas: None}], miniatura_rel|None`.
  - `moonraker.trabalho_de_historico(job: dict) -> DadosTrabalho` — `filament_type`/`filament_name` chegam como **string JSON** de lista (ex.: `"[\"PLA\", \"PLA\"]"`); `filament_colors` como lista; peso por filamento não existe, só `filament_weight_total` (com 1 filamento, `gramas` dele = total); miniatura = maior `thumbnails[]`, caminho `{dir do arquivo}/{relative_path}`; `inicio`/`fim` de epoch para UTC; `duracao_s = print_duration`.
  - `moonraker.mesclar_estado(estado: dict, status: dict) -> dict` — aplica um `notify_status_update` e devolve `{estado, arquivo, progresso (0–1), duracao_s, restante_s|None, bico, bico_alvo, mesa, mesa_alvo}`; `restante_s = duracao/progresso − duracao` quando progresso > 0.
  - `ao_vivo.Hub`: `async conectar(empresa_id, ws)`, `desconectar(empresa_id, ws)`, `async publicar(empresa_id, evento: dict)`. Instância global `hub`. Rota WS `/api/ao-vivo?token=<acesso>&empresa=<id>` (fecha com 4401/4403 se token inválido ou não membro); ao conectar, envia `{"tipo": "estado", "impressora_id", ...}` de cada impressora da empresa.
  - `servico.registrar_trabalho(db, empresa_id, impressora_id, dados, arquivada=False) -> Impressao|None` — `None` se `(impressora_id, job_id)` já existe; `status="arquivada"` ou `"a_confirmar"`; `origem="klipper"`; `modelo_id = casar_modelo(...)`; baixa a miniatura (`GET {url}/server/files/gcodes/{rel}`, falha ignorada) para `{empresa_id}/miniaturas/{impressao_id}.png`; publica `{"tipo": "impressao_terminou", impressao_id, arquivo, situacao}` quando não arquivada.
  - `monitor.Monitor(impressora_id, empresa_id, url, api_key, sessoes: Callable[[], Session], hub)`: `async rodar()` — WS `ws://{host}/websocket` (header `X-Api-Key` se houver), `server.connection.identify`, `printer.objects.subscribe` (`print_stats`, `display_status`, `virtual_sdcard`, `extruder`, `heater_bed`); `notify_status_update` → `mesclar_estado` + `hub.publicar({"tipo":"estado", ...})` no máximo a cada 2 s; `notify_history_changed` com `action == "finished"` → `registrar_trabalho`; reconexão com espera 2 s → 60 s (dobrando). `estado -> dict|None`.
  - `monitor.GerenciadorMonitores`: `iniciar_todos()`, `reiniciar(impressora)`, `parar(impressora_id)`, `parar_todos()`, `estado(impressora_id)`.
  - Rotas: `GET /api/impressoras/{id}/ao-vivo`; `GET /api/impressoras/{id}/historico?limite=50` (proxy de `/server/history/list`, cada item com `ja_trazido: bool`; 502 se a impressora não responder); `POST /api/impressoras/{id}/historico/{job_id}/trazer` → `registrar_trabalho(..., arquivada=True)` (200 com a existente se já trazido).

- [ ] **Step 1: Capturar fixture real:** `curl -s "http://192.168.1.110:7125/server/history/list?limit=3"` executado no `.150` via `ssh server@192.168.1.150 "curl ..."` (a impressora só é garantida na rede dele), salvar em `server/tests/fixtures/moonraker_historico.json`. Conferir que contém o job `0000A8` (`TQZ2G08_PLA_21m58s.gcode`, BambuStudio, 2 filamentos PLA `#FFFFFF`/`#000000`, `filament_weight_total` 1.71); se o histórico tiver andado, usar o primeiro job concluído e ajustar os valores do teste.
- [ ] **Step 2: Testes**:
  - `test_parser_trabalho_real`: `arquivo == "TQZ2G08_PLA_21m58s.gcode"`, `gramas_total == 1.71`, tipos `["PLA","PLA"]`, cores `["#FFFFFF","#000000"]`, `miniatura_rel` termina em `-50x50.png`, `status == "completed"`.
  - `test_mesclar_estado`: progresso 0.25 e duração 600 → `restante_s == 1800`; atualização parcial só com `extruder.temperature` mantém o resto.
  - `test_registrar_duas_vezes` (Review Focus 3): mesmo job 2× → uma impressão; `trazer` do mesmo job → 200 com a existente.
  - `test_arquivada_nao_publica_nem_pendencia`.
  - `test_hub_isola_empresas`: dois clientes WS (A e B); evento publicado para A chega só em A; token de B com `empresa=A` → fechado com 4403.
  - `test_monitor_com_moonraker_falso`: servidor `websockets.serve` em `127.0.0.1:porta livre` que responde identify/subscribe e envia `notify_history_changed` com o job da fixture → após `rodar()` (cancelado depois de receber), existe uma `Impressao` `a_confirmar` com `job_id` do fixture e o hub recebeu `impressao_terminou`.
- [ ] **Step 3:** → FAIL. **Step 4:** Implementar. **Step 5:** → PASS.
- [ ] **Step 6: Verificação real (sem commit de dados):** rodar a API local com SQLite, cadastrar impressora com `moonraker_url=http://192.168.1.110:7125` (só funciona se o PC estiver na mesma rede; senão pular para a Task 11) e conferir `GET /api/impressoras/{id}/ao-vivo` com `estado` preenchido.
- [ ] **Step 7:** Commit `feat: integração com Klipper e eventos ao vivo`.

---

### Task 11: Web estático, versão, migrações e deploy no `.150`

**Files:**
- Create: `server/Dockerfile`, `server/alembic.ini`, `server/migrations/` (env + `0001_inicial`), `deploy/docker-compose.yml`, `deploy/.env.example`, `deploy/backup.sh`, `deploy/deploy.sh`, `deploy/tunnel/config.yml.example`, `docs/servidor.md`, `server/tests/test_web.py`
- Modify: `server/app/main.py`, `.gitignore` (`deploy/.env`, `deploy/tunnel/*.json`, `deploy/tunnel/config.yml`), `docs/superpowers/specs/2026-11-02-cubo3-design.md` (limite de upload 95 MB e motivo)

**Interfaces:**
- Produces:
  - `GET /api/versao -> {versao, build, apk_url}` lido de `{apk_dir}/versao.json` (404 se não houver); `GET /baixar` → APK mais recente (`FileResponse`, 404 se não houver).
  - Se `web_dir` existir: arquivos estáticos em `/` com fallback para `index.html` em rotas desconhecidas que não começam com `/api`.
  - Contêiner: entrypoint roda `alembic upgrade head` e depois `uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers`; usuário não-root UID 1000; inclui `tests/`.
  - Compose (`/home/server/projects/cubo3/deploy/docker-compose.yml`): `db` (`postgres:16-alpine`, volume `/home/server/projects/cubo3/dados/postgres`), `api` (build `../server`, `127.0.0.1:8096:8000`, volumes `/home/server/projects/cubo3/dados/arquivos:/dados/arquivos`, `.../web:/web:ro`, `.../apk:/apk:ro`, `TZ=America/Sao_Paulo`), `backup` (`postgres:16-alpine` rodando `backup.sh`: `pg_dump` diário + `tar` de `arquivos/` em `/home/server/projects/cubo3/dados/backups`, apaga > 30 dias), `tunnel` (`cloudflare/cloudflared` com tag de versão fixa de pelo menos duas semanas, `tunnel run` com `config.yml` + credencial em `/home/server/projects/cubo3/deploy/tunnel`, ingress `cubo3.kerlonr.com.br → http://api:8000`, fallback `http_status:404`). Todos `restart: unless-stopped`.

- [ ] **Step 1: Testes** `test_web.py`: com `web_dir` temporário contendo `index.html`, `GET /catalogo/abc` → 200 com o HTML; `GET /api/inexistente` → 404 JSON; `GET /api/versao` sem arquivo → 404; com `versao.json` → campos corretos.
- [ ] **Step 2:** → FAIL. **Step 3:** Implementar `main.py`; Alembic (`alembic revision --autogenerate -m inicial` contra SQLite limpo; revisar que cria todas as tabelas). **Step 4:** → PASS.
- [ ] **Step 5: Túnel** (no `.150`, sem sudo): `cloudflared tunnel create cubo3`; `cloudflared tunnel route dns cubo3 cubo3.kerlonr.com.br`; copiar a credencial `~/.cloudflared/<uuid>.json` para `~/projects/cubo3/deploy/tunnel/` e gerar `config.yml` a partir do exemplo. Conferir que `cloudflared tunnel list` mostra `cubo3` e que os túneis existentes continuam listados intactos.
- [ ] **Step 6: Deploy:** `deploy/deploy.sh` empacota `server/` e `deploy/` (sem `.venv`, `.env`, credenciais) via `tar | ssh` para `~/projects/cubo3`; criar `deploy/.env` no servidor (senha forte gerada para o Postgres, `JWT_SEGREDO` aleatório de 64 chars) com permissão 600; `sudo docker compose -f ~/projects/cubo3/deploy/docker-compose.yml up -d --build`.
- [ ] **Step 7: Testes no Postgres:** criar banco `cubo3_teste` no contêiner `db` e rodar `sudo docker compose ... run --rm -e TEST_DATABASE_URL=postgresql+psycopg://...@db/cubo3_teste api python -m pytest -q` → todos PASS.
- [ ] **Step 8: Conta inicial:** perguntar ao Kerlon o e-mail dele; `sudo docker compose ... exec api python -m app.cli criar-dono --email <dele> --nome Kerlon --empresa "Cubo³"` (ele digita a senha).
- [ ] **Step 9: Verificação ponta a ponta** pela internet: `curl https://cubo3.kerlonr.com.br/api/saude` → `{"ok":true}`; login com a conta criada; cadastrar a impressora (`http://192.168.1.110:7125`) via API e ver `GET /api/impressoras/{id}/ao-vivo` com estado real; `ls ~/projects/cubo3/dados/backups` mostra o primeiro backup após rodar `backup.sh` uma vez manualmente.
- [ ] **Step 10: Documentação:** `docs/servidor.md` (sem segredos): onde fica cada coisa, comandos de log/atualizar/backup/restauração, como criar membro. Atualizar a memória `servidor-150-layout` com a pasta, a porta 8096 e o túnel `cubo3`.
- [ ] **Step 11:** Commit `chore: deploy do servidor do Cubo³ no .150` e `git push`.

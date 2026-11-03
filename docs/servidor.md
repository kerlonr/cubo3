# Servidor do Cubo³

Sem segredos aqui. Senhas e chaves ficam só em `~/projects/cubo3/deploy/.env` no servidor (permissão 600).

## Onde fica cada coisa

| Item | Onde |
|---|---|
| Máquina | `server@192.168.1.150` (Docker exige `sudo`) |
| Endereço público | https://cubo3.kerlonr.com.br (app web em `/`, API em `/api`, documentação em `/api/docs`) |
| Pasta | `/home/server/projects/cubo3` (`server/`, `deploy/`, `dados/`) |
| Containers | `cubo3-db-1` (Postgres 16), `cubo3-api-1` (FastAPI, porta interna 8100 → `127.0.0.1:8096`), `cubo3-backup-1`, `cubo3-tunnel-1` |
| Banco | `dados/postgres/` (banco `cubo3`; `cubo3_teste` só para a suíte de testes) |
| Arquivos enviados (STL, 3MF, fotos, miniaturas) | `dados/arquivos/<empresa>/...` |
| App web (build do Flutter) | `dados/web/` |
| APK + `versao.json` | `dados/apk/` |
| Backups | `dados/backups/banco/cubo3-AAAAMMDD.dump` (30 dias) e `dados/backups/arquivos/` (espelho) |
| Túnel | `cubo3` (id `cac52dc6-…`), config em `deploy/tunnel/config.yml`, credencial `deploy/tunnel/<id>.json`. Separado dos túneis `cloudflared`, `cloudflared-kerlonr` e `viagens` |
| Impressora | Klipper/Moonraker em `http://192.168.1.110:7125` (rede local) |

**Por que a porta interna é 8100:** o host tem uma regra `DOCKER-USER` que descarta tráfego para a porta 8000 vindo de fora de `192.168.1.0/24` (protege o painel do Crafty). Ela também derrubava o tráfego túnel → API.

## Comandos (no servidor)

```bash
cd ~/projects/cubo3/deploy
sudo docker compose ps                          # estado
sudo docker compose logs -f api                 # logs da API (Klipper aparece como cubo3.klipper)
sudo docker compose logs --tail 20 backup       # último backup
sudo docker compose up -d --build               # atualizar depois de um deploy
```

## Atualizar (do PC, na raiz do repositório)

```bash
sh deploy/deploy.sh                             # envia server/ e deploy/ (sem .env nem credenciais)
ssh server@192.168.1.150 "cd ~/projects/cubo3/deploy && sudo docker compose up -d --build api"
```

A API roda `alembic upgrade head` sozinha ao iniciar. Mudou um modelo? Gere a migração antes do deploy:
`cd server && DATABASE_URL=sqlite+pysqlite:///./mig.db JWT_SEGREDO=<32+ chars> KLIPPER_ATIVO=0 .venv/Scripts/alembic upgrade head && ... alembic revision --autogenerate -m "<o que mudou>"`.

## Testes contra o Postgres do servidor

```bash
cd ~/projects/cubo3/deploy && . ./.env
sudo docker compose run --rm --no-deps -e KLIPPER_ATIVO=0 \
  -e TEST_DATABASE_URL=postgresql+psycopg://cubo3:$POSTGRES_PASSWORD@db/cubo3_teste api python -m pytest -q
```

## Contas

- Primeiro dono (pede a senha duas vezes):
  `sudo docker compose exec api python -m app.cli criar-dono --email <email> --nome <nome> --empresa "Cubo³"`
- Sócios: o dono adiciona pelo app (Empresa → Usuários) ou `POST /api/empresa/membros`. Eles trocam a senha no primeiro login.
- Cadastro aberto ao público está desligado (`CADASTRO_ABERTO=false`).

## Restaurar backup

```bash
cd ~/projects/cubo3/deploy
sudo docker compose stop api
sudo docker compose exec -T db pg_restore -U cubo3 -d cubo3 --clean --if-exists < ../dados/backups/banco/cubo3-AAAAMMDD.dump
sudo cp -an ../dados/backups/arquivos/. ../dados/arquivos/
sudo docker compose start api
```

**Atenção:** o backup fica no mesmo disco do servidor. Ele protege contra erro e exclusão, não contra perda do disco. Copie `dados/backups/` para outro lugar de tempos em tempos.

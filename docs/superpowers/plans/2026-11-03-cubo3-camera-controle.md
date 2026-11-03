# Cubo³ — Câmera e controle (Plano 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Tasks 1–2 (servidor) primeiro; Tasks 3–4 (app) depois que a API estiver publicada. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ver a câmera ao vivo e controlar a impressora (pausar/continuar/cancelar, temperaturas, emergência, imprimir G-code do catálogo) pelo app, só para o dono.

**Architecture:** O servidor vira o intermediário único: rotas novas em `server/app/klipper/` repassam câmera (foto e MJPEG em streaming) e comandos ao Moonraker pela LAN. O app ganha a tela da impressora e o botão "Imprimir" no arquivo `.gcode`.

**Tech Stack:** FastAPI (`StreamingResponse` + `httpx` async), Flutter (`http` streaming no Android, `<img>` via `HtmlElementView` no web).

**Spec:** `docs/superpowers/specs/2026-11-03-cubo3-camera-controle-design.md` (+ `2026-11-02-cubo3-design.md`).

## Global Constraints

- Commits só no nome do Kerlon; nunca `Co-Authored-By`/`Claude-Session`/menção ao Claude.
- Controle e imprimir: **só dono** (`so_dono`) → membro 403. Câmera: qualquer membro.
- Comandos nunca passam pela fila offline do app.
- Limites: bico 0–300 °C, mesa 0–120 °C → fora 422.
- Testes do servidor sem impressora real: `httpx.MockTransport`/monkeypatch das funções de `app/klipper/moonraker.py`. Verificação real só com GETs (câmera) — **nunca** enviar comando à impressora real em teste automático.

## Review Focus

1. **Membro tentando controlar** por rota direta → 403, nada chega ao Moonraker. Teste na Task 1.
2. **Vídeo com a tela fechada** — ao sair da tela o app fecha a conexão; no servidor, cliente que desconecta encerra o repasse (sem conexão órfã com a impressora). Teste na Task 2 (servidor) e Task 3 (app).
3. **Imprimir com a impressora ocupada** → 409, arquivo não é enviado. Teste na Task 1.
4. **Impressora fora do ar** → 502 com mensagem, app mostra "Impressora não respondeu" sem travar. Teste nas Tasks 1–3.
5. **Link de câmera vencido/reutilizado por outra empresa** → 401/404. Teste na Task 2.

---

### Task 1: Comandos e imprimir (servidor)

**Files:** `server/app/klipper/{moonraker,rotas}.py`, `server/app/catalogo/rotas.py`, `server/tests/test_controle.py`.

**Interfaces:**
- `moonraker.comando(url, chave, caminho: str, params: dict | None = None) -> dict` (POST; levanta `httpx.HTTPError`).
- `moonraker.enviar_e_imprimir(url, chave, nome: str, conteudo_path: Path) -> dict` (multipart `file`, `print=true`).
- `POST /api/impressoras/{id}/comando` body `{acao: "pausar"|"continuar"|"cancelar"|"emergencia"|"temperatura", alvo?: "bico"|"mesa", valor?: number}` → `{ok: true}`; mapa: pausar→`/printer/print/pause`, continuar→`/printer/print/resume`, cancelar→`/printer/print/cancel`, emergencia→`/printer/emergency_stop`, temperatura→`/printer/gcode/script?script=SET_HEATER_TEMPERATURE HEATER=extruder|heater_bed TARGET=<valor>`.
- `POST /api/arquivos/{id}/imprimir {impressora_id}` → `{ok: true, arquivo}`; só `tipo == "gcode"` (senão 422); estado ao vivo `printing`/`paused` (do `monitores.estado`, ou consulta `/printer/objects/query?print_stats` quando sem monitor) → 409.

- [ ] Testes: membro → 403 em comando e imprimir (e o mock do Moonraker não é chamado); dono pausar chama `/printer/print/pause`; temperatura bico 210 monta o script exato; bico 301 / mesa 121 → 422; Moonraker fora → 502; imprimir STL → 422; imprimir com estado `printing` → 409 sem upload; imprimir gcode ok envia multipart com `print=true` e nome original; impressora de outra empresa → 404.
- [ ] FAIL → implementar → PASS (suíte toda). Commit `feat: comandos da impressora e imprimir do catálogo`.

### Task 2: Câmera (servidor)

**Files:** `server/app/klipper/{moonraker,rotas}.py`, `server/app/auth/seguranca.py`, `server/tests/test_camera.py`.

**Interfaces:**
- `moonraker.webcam(url, chave) -> {"foto": url_absoluta, "video": url_absoluta} | None` (de `/server/webcams/list`, primeira habilitada; URLs relativas resolvidas contra o host da impressora; cache por impressora 5 min).
- `GET /api/impressoras/{id}/camera/foto` → `image/jpeg` (membro).
- `POST /api/impressoras/{id}/camera/link` → `{url: "/api/camera/<token>"}` (token tipo `camera`, sub impressora_id, 60 s).
- `GET /api/camera/{token}` → `StreamingResponse` repassando o MJPEG (`multipart/x-mixed-replace` com o boundary original); fecha a conexão com a impressora quando o cliente desconecta.

- [ ] Testes: foto repassa bytes e content-type; impressora sem câmera → 404 "Sem câmera"; link de outra empresa → 404; token de acesso no lugar do de câmera → 401; streaming repassa os primeiros quadros de um gerador falso e o gerador é fechado ao encerrar o cliente.
- [ ] FAIL → implementar → PASS. Commit `feat: câmera da impressora`. Publicar no `.150` (`sh deploy/deploy.sh` + `docker compose up -d --build api`), rodar a suíte no Postgres e conferir com GET real: `/api/impressoras/{id}/camera/foto` só se houver credencial de teste fornecida pelo Kerlon; senão, conferir pelo `curl` local no servidor que `http://192.168.1.110/webcam/?action=snapshot` responde.

### Task 3: Tela da impressora (app)

**Files:** `app/lib/telas/impressoes/impressora_tela.dart`, `app/lib/widgets/camera_mjpeg.dart` (+ `_web.dart`/`_io.dart` por import condicional), `app/lib/api/controle.dart`, `app/test/controle_test.dart`.

- `CameraAoVivo(impressoraId)`: pede o link, Android lê o stream e decodifica quadros por marcadores JPEG (`FFD8`…`FFD9`) desenhando com `Image.memory(gaplessPlayback: true)`; web usa `<img src=link>`; ao sair da tela cancela a assinatura/remove o elemento; erro → "Câmera indisponível — tocar para tentar de novo"; tocar abre tela cheia.
- Tela: câmera, estado, progresso, temperaturas atual/alvo; **dono**: Pausar/Continuar/Cancelar conforme estado (cancelar confirma), Temperaturas (campo + PLA 200/60, PETG 235/80, Desligar 0/0), Parada de emergência separada em vermelho com confirmação explicando o reinício. Membro: sem controles. Sem conexão: botões desabilitados com aviso. Comandos chamam a API direto (nunca a fila).
- Abrir pela toque no cartão da impressora (Início e Impressões).
- [ ] Testes: extrator MJPEG separa 2 quadros de um buffer com lixo entre eles; membro não vê controles; cancelar sem confirmar não chama a API; comando com 502 mostra "Impressora não respondeu"; atalho PETG manda bico 235 e mesa 80.
- [ ] FAIL → implementar → PASS + `flutter analyze`. Commit `feat: tela da impressora com câmera e controles`.

### Task 4: Imprimir do catálogo (app) e versão

- Arquivo `.gcode` no perfil do modelo: "Imprimir na <impressora>" (só dono; escolhe impressora se houver mais de uma; confirmação com nome do arquivo); 409 → "A impressora está ocupada".
- Subir `version` no `pubspec.yaml` (build +1), `sh deploy/publicar_app.sh`, release no GitHub com o APK (`gh release create vX.Y.Z <apk> --repo kerlonr/cubo3`).
- [ ] Testes: não-dono não vê o botão; STL não mostra o botão; 409 mostra a mensagem.
- [ ] FAIL → implementar → PASS. Commit `feat: imprimir G-code do catálogo`.

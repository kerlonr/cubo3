# Cubo³ — Câmera e controle da impressora (adendo ao design)

Data: 2026-11-03 · Status: decisões do Kerlon registradas em 2026-11-03 · Complementa `2026-11-02-cubo3-design.md` (que deixava controle fora da v1).

## Intenção

Ver a impressora e agir nela pelo app, de qualquer lugar, sem abrir o Mainsail: acompanhar a câmera ao vivo, pausar/continuar/cancelar, mexer em temperatura, parada de emergência e mandar um G-code do catálogo imprimir.

## Decisões do Kerlon

- Controles: **pausar / continuar / cancelar**, **temperaturas** (bico e mesa, com atalhos de pré-aquecimento), **parada de emergência**, **enviar G-code do catálogo e iniciar a impressão**.
- **Só o dono** controla. Membros veem câmera e estado.
- Câmera em **vídeo ao vivo** enquanto a tela estiver aberta.

## Como funciona (decisões do builder)

- Tudo passa pelo servidor do Cubo³, que fala com o Moonraker pela rede local (`192.168.1.110:7125`). O app nunca fala direto com a impressora e não depende do túnel público dela.
- **Câmera:** o servidor descobre os endereços em `GET /server/webcams/list` do Moonraker (crowsnest: foto `/webcam/?action=snapshot`, vídeo MJPEG `/webcam/?action=stream`, relativos ao host da impressora) e repassa:
  - `GET /api/impressoras/{id}/camera/foto` (qualquer membro, com login normal).
  - `POST /api/impressoras/{id}/camera/link` → URL assinada que vale 60 s para **abrir** o vídeo (`/api/camera/{token}`); o vídeo segue enquanto a conexão estiver aberta. Motivo: no navegador o vídeo é um `<img>` que não manda cabeçalho de login (mesmo padrão do link de download).
  - App Android lê o MJPEG (quadros JPEG) e desenha; app web usa um elemento `<img>` com o link. Tela cheia ao tocar. O vídeo fecha ao sair da tela (economia de 4G).
- **Comandos** (`POST /api/impressoras/{id}/comando`, só dono → 403 para membro):
  - `{acao: "pausar"|"continuar"|"cancelar"}` → `/printer/print/pause|resume|cancel`.
  - `{acao: "emergencia"}` → `/printer/emergency_stop`.
  - `{acao: "temperatura", alvo: "bico"|"mesa", valor}` → `SET_HEATER_TEMPERATURE HEATER=extruder|heater_bed TARGET=<valor>` via `/printer/gcode/script`. Limites: bico 0–300 °C, mesa 0–120 °C (fora → 422).
  - Falha do Moonraker → 502 com mensagem clara; impressora sem endereço do Klipper → 422.
- **Imprimir do catálogo** (`POST /api/arquivos/{id}/imprimir {impressora_id}`, só dono): só arquivo tipo `gcode`; impressora imprimindo/pausada → 409 "A impressora está ocupada"; envia o arquivo ao Moonraker (`POST /server/files/upload` com `print=true`). O nome no Moonraker é o nome original, para o Cubo³ casar a impressão com o modelo quando terminar.
- **No app:**
  - Tela da impressora (aberta pelo cartão ao vivo em Início/Impressões): câmera no topo, estado e progresso, temperaturas atual/alvo; para o dono, botões Pausar/Continuar/Cancelar conforme o estado, Temperaturas (campo + atalhos **PLA 200/60**, **PETG 235/80**, **Desligar 0/0**) e a Parada de emergência separada, em vermelho.
  - Confirmações: cancelar pede confirmação; parada de emergência pede confirmação explicando que reinicia o Klipper ("FIRMWARE_RESTART" depois); iniciar impressão mostra arquivo e impressora antes.
  - Arquivo `.gcode` no perfil do modelo ganha "Imprimir na <impressora>" (só dono).
  - Comandos nunca vão para a fila offline: sem conexão, o botão avisa e não guarda (um "cancelar" executado horas depois seria perigoso).

## Fora do escopo

Mover eixos/home, macros personalizadas, gravação ou timelapse da câmera, controle de mais de uma câmera por impressora, controle de ventoinha/velocidade.

## Anti-objetivos

- Comando executado atrasado (por fila ou reenvio automático).
- Membro conseguindo controlar por qualquer caminho (inclusive rota direta).
- Vídeo continuar baixando com a tela fechada.

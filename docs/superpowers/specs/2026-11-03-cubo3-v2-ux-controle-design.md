# Cubo³ 2.0 — Controle total da impressora e interface mais fácil (adendo ao design)

Data: 2026-11-03 · Pedido do Kerlon: "quero quase que seja como o Mobileraker", "setar home e mandar algo imprimir", "lugares quebrando a responsividade", "não está intuitiva para cadastros e configurações", "dinâmica, fácil, rápida, a um clique". Complementa `2026-11-02-cubo3-design.md` e `2026-11-03-cubo3-camera-controle-design.md`.

## Intenção

1. A impressora vira um lugar de primeira classe no app, com o que se espera de um app de Klipper (referência: Mobileraker — controle total da máquina, eixos, aquecedores, ventoinhas, arquivos G-code para iniciar impressão, macros agrupadas, console).
2. A interface fica óbvia para quem nunca usou: cada tela diz o que é e qual o próximo passo, formulários pedem o mínimo com padrões inteligentes, e nada quebra em nenhuma largura de tela.

## Decisões (Kerlon + builder)

- Controle continua **só para o dono** (decisão anterior do Kerlon). Membro vê painel, câmera, arquivos e console sem botões de ação.
- Comandos continuam **fora da fila offline** (nunca executam atrasados).

### Impressora (estilo Mobileraker)

Aba nova **Impressora** no lugar de "Impressões" na barra (as impressões a confirmar continuam lá dentro, com selo de quantidade no ícone da aba). Com mais de uma impressora, seletor no topo. Seções (abas internas):

- **Painel:** câmera ao vivo, estado, progresso, tempo restante, arquivo com miniatura, temperaturas atual/alvo com atalhos (PLA 200/60, PETG 235/80, Desligar), Pausar/Continuar/Cancelar, faixa "N impressões a confirmar".
- **Controle:** Home (Tudo / XY / Z), mover X/Y/Z com passos 0,1 · 1 · 10 · 100 mm (setas em cruz para XY e ±Z), posição atual e eixos já em home, desligar motores, extrudar/retrair (5 · 10 · 25 mm, só com bico ≥ 170 °C), ventoinha (0–100 %), velocidade (10–300 %), fluxo (50–150 %), ajuste fino de Z (±0,01 · ±0,05 mm), reiniciar firmware (após emergência). Parada de emergência sempre visível.
- **Arquivos:** G-codes que estão na impressora (mais recentes primeiro), com miniatura, tempo estimado e peso; tocar → detalhes → **Imprimir** (confirmação). Arquivos do catálogo seguem com "Imprimir" no perfil do modelo.
- **Macros:** macros do Klipper (exceto as que começam com `_`), um toque para rodar (confirmação).
- **Console:** últimas respostas do Klipper ao vivo e campo para mandar G-code (histórico dos últimos comandos para repetir em um toque).
- **Histórico/Confirmar:** o que hoje é a aba Impressões.

Servidor: estado ao vivo passa a incluir `toolhead` (posição, eixos em home), `gcode_move` (velocidade, fluxo, offset de Z) e `fan`; respostas do console chegam pelo mesmo WebSocket ao vivo. Rotas novas (só dono para ações): G-code livre, home/mover/motores/ventoinha/velocidade/fluxo/ajuste de Z/extrudar/macro/reiniciar firmware, listar arquivos e macros, miniatura de arquivo, imprimir arquivo da impressora.

### Interface mais fácil

- **Layout adaptativo Material 3:** compacto (< 600 dp) barra inferior; médio (600–839) trilho; expandido (≥ 840) trilho + lista e detalhe lado a lado onde fizer sentido (catálogo, pedidos, impressora). Nada de largura fixa; textos longos quebram ou encurtam com reticências; teste automático procura estouro de layout em todas as telas principais nas larguras 320, 360, 412, 600, 840 e 1280, claro e escuro.
- **Primeiros passos:** enquanto faltar algo, o Início mostra um cartão com a lista (Cadastrar impressora → Cadastrar filamento → Registrar um carretel → Criar um modelo → Fazer a primeira venda), cada item com um toque; some quando tudo estiver feito.
- **Ações rápidas no Início:** botões grandes Vender, Lançar impressão, Novo carretel, Orçar (além do "+").
- **Telas vazias que ensinam:** cada lista vazia explica para que serve e tem o botão do próximo passo.
- **Formulários:** rótulo acima do campo, uma coluna, texto de ajuda em linguagem simples ("R$/kg: quanto você pagou por 1 kg de filamento"), padrões inteligentes (data de hoje, canal Direto, preço sugerido pela margem do meio, último filamento usado), chips/botões segmentados e +/− no lugar de listas suspensas e texto livre quando houver poucas opções, botão Salvar fixo no rodapé, cálculo ao vivo onde houver dinheiro.
- **Configurações reorganizadas** em seções com ícone e uma linha explicando cada uma: Empresa (nome, usuários), Custos (mão de obra, energia, margens — com exemplo ao vivo "uma peça de 33 g e 3 h custa R$ 6,32"), Canais de venda (taxas com exemplo), Impressoras, Notificações, Conta (trocar senha, sair), Avançado (servidor, fila de envio).

## Fora do escopo

Timelapse, bed mesh, exclude object, editar arquivos de configuração do Klipper, várias câmeras, LEDs/pinos, leitura de QR/código de barras (fica como ideia).

## Anti-objetivos

Comando executado atrasado; membro controlando por qualquer caminho; qualquer tela com estouro de layout em celular; formulário que obrigue a ler manual.

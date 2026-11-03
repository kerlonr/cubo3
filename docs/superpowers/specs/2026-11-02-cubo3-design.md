# Cubo³ — gestão de impressão 3D

Data: 2026-11-02 · Status: aprovado pelo Kerlon em 2026-11-02 (com troca da cor de destaque)

Commits deste repositório saem somente no nome do Kerlon, sem `Co-Authored-By` nem qualquer menção ao Claude.

## 1. Intenção

Cubo³ é a empresa de impressão 3D do Kerlon e do sócio (Thales). Hoje o orçamento é feito numa planilha do Google ("Preço Impressao 3D") e o resto (estoque de filamento, o que foi impresso, o que foi vendido, quanto se ganhou) não é controlado em lugar nenhum.

O app Cubo³ é um ERP pequeno para impressão 3D: **simples, minimalista, tudo a um toque**. O celular é o principal e precisa fazer tudo. O mesmo app roda no navegador do PC, onde é mais confortável anexar STL/3MF. A pergunta que o app responde todo dia é: **quanto gastamos, quanto vendemos, quanto lucramos, e o que temos em estoque.**

Nasce para uma empresa com 2 usuários, mas o modelo de dados já é multiempresa (cada empresa com seus sócios, sem limite de usuários), porque a ideia é poder vender o mesmo produto para outras pessoas depois.

## 2. Objetivos

1. Login com e-mail e senha; um usuário pode pertencer a mais de uma empresa e trocar entre elas.
2. Cadastro da empresa e dos usuários dela (papéis: dono, membro).
3. Inventário modular: filamentos (por carretel), insumos (ímãs, parafusos, embalagem), peças prontas, impressoras.
4. Banco de modelos / catálogo: cada modelo tem um "perfil" com fotos, arquivos STL/3MF/G-code, links de origem, custo calculado, preço, estoque de peças prontas, histórico de impressões e de vendas. Filtro e ordenação por mais vendidos, mais lucrativos, mais recentes.
5. Calculadora de custo idêntica à planilha (seção 7), mais taxas de marketplace.
6. Impressões: integração com Klipper (Moonraker) que cria automaticamente uma impressão "a confirmar" quando um trabalho termina; lançamento manual fácil.
7. Clientes (nome, telefone, e-mail, histórico) e pedidos com status.
8. Painel com gastos, receita, lucro, horas de impressão, filamento consumido, mais vendidos, estoque baixo e impressões a confirmar.
9. Notificações no celular estilo Mobileraker (progresso da impressão, fim, falha), **sem Firebase**.
10. Funciona com internet ruim/ausente no Android (seção 9).

## 3. Fora do escopo agora (não-objetivos)

- Vitrine pública/loja e landing page de marketing (depois de tudo pronto).
- Controlar a impressora pelo app (pausar, cancelar, mover eixos). O Mainsail continua para isso.
- Proteger o túnel público do Moonraker (`v3.thalesgmartins.com.br` hoje aceita qualquer um como confiável). Fica registrado como pendência; o Cubo³ não depende desse túnel.
- Reorganizar o resto do servidor `.150`. Só o Cubo³ fica organizado; o resto é outro projeto.
- Importação em massa do histórico do Klipper (seção 8.4: importação item a item, opcional).
- iOS, NF-e/fiscal, API de marketplace (Shopee/ML), envio de e-mail, sincronização com Spoolman.

## 4. Anti-objetivos (falharia mesmo funcionando)

- Parecer planilha: telas cheias de campos. Todo formulário abre com o mínimo e esconde o resto em "mais detalhes".
- Registrar uma venda ou confirmar uma impressão levar mais que alguns toques.
- Ficar cobrando confirmação de impressões que não eram para venda (teste, pessoal). Impressão importada ou marcada como não-venda nunca vira pendência.
- Descontar estoque de filamento sozinho com a estimativa do fatiador. Estoque só muda quando um humano confirma os gramas reais.
- Mexer em qualquer outro serviço do `.150` (Crafty, Factorio, Meu Frete, Acervo, túneis existentes `cloudflared`, `cloudflared-kerlonr`, `cloudflared-viagens`).
- Exigir Firebase.

## 5. Decisões do Kerlon

- Plataformas: Android + navegador.
- Servidor e banco no `192.168.1.150`, tudo em Docker, pasta do projeto organizada; acesso de qualquer lugar por túnel Cloudflare.
- Arquivos STL/3MF, fotos, nome e links guardados no servidor.
- Uma impressora hoje (Klipper, `192.168.1.110:7125`, mesma rede do servidor); integração automática + opção manual fácil.
- Consumo de filamento informado manualmente ao fim da impressão (pode dar erro e gastar mais que o previsto). Inventário modular.
- Taxas de marketplace e energia entram no cálculo do lucro.
- Pedidos com status e clientes (nome, telefone, e-mail) para histórico.
- Nome Cubo³, marca simples e minimalista, sem aprofundar; Kerlon muda depois se quiser.
- Ordem: servidor + app primeiro; web/PC e o resto depois. O app é o principal.
- Sem Firebase.

## 6. Arquitetura

```
Android (Flutter) ─┐                         ┌─ Postgres 16 (volume)
                   ├─ HTTPS ─ Cloudflare ─ cubo3.kerlonr.com.br ─ API FastAPI ─┼─ arquivos/ (volume: STL, 3MF, fotos)
Navegador (Flutter web, servido pela API) ─┘        (túnel próprio)            └─ worker Klipper ── ws://192.168.1.110:7125/websocket
```

- **Monorepo** `C:\Users\mitok\Desktop\cubo3`, repo GitHub privado `kerlonr/cubo3`:
  - `app/` Flutter (Android + web), `server/` FastAPI, `deploy/` compose e scripts, `docs/`.
- **Base de código:** partir dos padrões do Meu Frete (`D:\ProjetoViagens`: Flutter + provider + http, FastAPI em Docker, backup diário) e do SetremRobot (`D:\SetremRobot\app`: tema, `fl_chart`, verificação de atualização). Copiar o que servir; não depender deles.
- **Servidor** (`~/projects/cubo3` no `.150`, dono `server:server`):
  - `docker compose` com 4 serviços: `api` (FastAPI + worker Klipper no mesmo processo, assíncrono), `db` (Postgres 16), `backup` (pg_dump diário + cópia de `arquivos/`, guarda 30 dias), `tunnel` (cloudflared).
  - API publicada só em `127.0.0.1:8096` (porta livre conferida em 2026-11-02).
  - Volumes com **caminho absoluto** ou nomeados — nunca relativos (incidente de 18/06/2026: mover pasta com bind mount relativo recriou diretórios vazios).
  - Túnel novo `cubo3`, criado por CLI com o `~/.cloudflared/cert.pem` que já existe, hostname `cubo3.kerlonr.com.br`. A mesma origem serve o app web em `/` e a API em `/api`, então não há CORS.
  - Segredos (`.env`: senha do Postgres, chave JWT) fora do git.
- **Web:** o build `flutter build web` é servido pela própria API como arquivos estáticos. O APK fica disponível em `/baixar` para instalar em outros celulares.
- **Distribuição Android:** APK assinado, instalado à mão. O app consulta `/api/versao` e oferece atualizar quando houver versão nova (padrão do SetremRobot).

## 7. Cálculo de custo (fiel à planilha)

Parâmetros da **empresa** (padrões da planilha): eficiência do material 1,1; mão de obra R$ 10,00/h; energia R$ 0,656/kWh; fator de reserva 1,3; margens sugeridas 20%, 30%, 50%.

Parâmetros de cada **impressora**: preço (R$ 1.660), custos adicionais (0), manutenção 10% do preço ao ano, vida útil 3 anos, uso 50% do ano, potência 150 W.

```
investimento       = preço + custos_adicionais
custo_vida         = investimento + (preço × 0,10 × anos_vida)
horas_ano          = 8760 × uso
capital_por_hora   = custo_vida / (horas_ano × anos_vida)
energia_por_hora   = (potência_W / 1000) × R$_kWh
impressora_por_hora = (capital_por_hora + energia_por_hora) × fator_reserva

material  = Σ por filamento (gramas / 1000 × R$_kg) × eficiência   (no orçamento)
mão_obra  = minutos / 60 × R$_h_mão_obra
máquina   = horas × impressora_por_hora
insumos   = Σ qtd × custo_unitário            (ímãs, parafusos...)
embalagem = Σ qtd × custo_unitário + custo médio de envio
custo     = material + mão_obra + máquina + insumos + embalagem

preço_com_margem = custo / (1 − margem)                         (planilha)
com canal de venda: preço = (custo + taxa_fixa) / (1 − margem − taxa_%)
lucro_da_venda   = preço − custo − taxa_% × preço − taxa_fixa
```

**Caso de teste obrigatório** (valores da planilha): PLA R$ 100/kg, 33 g, 3 h, 10 min de mão de obra, sem insumos → material R$ 3,63; mão de obra R$ 1,67; impressora R$ 0,3414/h → R$ 1,02; **custo R$ 6,32**; preços 20% = R$ 7,90, 30% = R$ 9,03, 50% = R$ 12,64. O cálculo existe no servidor e no app (para orçar sem internet); os dois são testados contra esse caso.

Orçamento usa gramas estimados × 1,1. **Impressão confirmada usa os gramas reais** (sem o 1,1); a perda é lançada à parte e entra no custo daquela impressão.

A calculadora ("Orçar peça") funciona sem modelo cadastrado; o resultado pode virar um modelo novo ou um pedido com status `orçamento` em um toque.

Canais de venda são cadastráveis por empresa (ex.: Direto 0%; Shopee x% + R$ y; Mercado Livre x% + R$ y). Os percentuais não vêm pré-preenchidos com valores "oficiais": o usuário digita os atuais.

## 8. Módulos

### 8.1 Empresa e usuários
- Usuário (e-mail, nome, senha com hash argon2/bcrypt). Membro = usuário × empresa × papel (`dono` gerencia usuários e configurações; `membro` faz o resto). Isolamento por `empresa_id` em todas as tabelas e em todas as consultas — testado.
- Cadastro aberto **desligado** por configuração (`CADASTRO_ABERTO=false`): a primeira conta e empresa são criadas por um comando no servidor; o dono adiciona sócios com e-mail e senha inicial, que eles trocam no primeiro login. Ligar o cadastro aberto é uma linha de config quando for vender.
- Sessão com token de acesso curto + refresh; o celular guarda o refresh em armazenamento seguro.

### 8.2 Inventário (modelo inspirado no Spoolman)
- **Filamento** (o "produto"): marca, material (PLA, PETG...), cor (nome + hex), diâmetro, densidade, R$/kg de referência, peso do carretel vazio, estoque mínimo para alerta.
- **Carretel** (cada rolo físico): filamento, peso líquido inicial, preço pago, data de compra, local, aberto/fechado, arquivado.
- **Insumo** (ímã, parafuso, caixa, plástico bolha...): nome, unidade, custo unitário, estoque mínimo.
- **Peça pronta**: estoque por modelo.
- Todo saldo é **soma de movimentos**, nunca um número sobrescrito. Movimento = (item, tipo `compra | consumo | perda | ajuste | produção | venda`, quantidade ±, vínculo opcional com impressão/pedido, usuário, data). Assim dois aparelhos lançando ao mesmo tempo (ou offline) não geram conflito, e todo saldo tem histórico explicável.
- Ajuste por pesagem: o usuário informa "o carretel pesa X g na balança", o app desconta o peso do carretel vazio e lança o ajuste da diferença.

### 8.3 Catálogo / banco de modelos
- Modelo: nome, descrição, categoria e tags, links (Printables, MakerWorld...), arquivos (STL, 3MF, G-code, fotos; primeira foto vira capa), receita padrão (filamentos e gramas, tempo, minutos de mão de obra, insumos, embalagem), preço de venda definido, custo calculado na hora.
- Perfil do modelo: capa, preço × custo × lucro, estoque de peças prontas, impressões feitas, vendas, arquivos para baixar.
- Lista: busca, filtro por categoria e tags, ordenação por **mais vendidos**, mais lucrativos, recentes e nome; período (mês, 3 meses, sempre).
- Upload de arquivo funciona no celular (seletor de arquivos) e no navegador (seletor e arrastar-e-soltar). Limite por arquivo configurável (padrão 95 MB: o túnel Cloudflare gratuito recusa requisições acima de 100 MB). Arquivos ficam no volume `arquivos/`, por empresa, e só são servidos a membros autenticados.

### 8.4 Impressoras e Klipper
- Impressora: nome, modelo, parâmetros de custo (seção 7), URL do Moonraker (`http://192.168.1.110:7125`), chave de API opcional.
- **Worker** no servidor mantém um WebSocket com cada Moonraker configurado (reconecta sozinho), assina `print_stats`, `display_status`, `virtual_sdcard` e as temperaturas, e acompanha o histórico de trabalhos.
- Quando um trabalho termina (`completed`, `cancelled`, `error`), cria uma **impressão "a confirmar"** com: arquivo, duração real, gramas estimados (`filament_weight_total` do fatiador), filamentos e cores (`filament_type`, `filament_colors`, incluindo multicor), miniatura, `job_id`. Tenta casar com um modelo do catálogo pelo nome do arquivo; se não casar, o usuário escolhe ou deixa sem modelo, e o app guarda aquele nome de arquivo no modelo para casar sozinho da próxima vez.
- **Confirmar impressão** (tela de poucos toques): finalidade (`venda/estoque | pessoal | teste | falhou`); peças boas; para cada filamento, qual carretel e gramas reais (pré-preenchido com a estimativa, editável); perda extra. Ao confirmar: movimentos de consumo/perda nos carretéis e, se `venda/estoque`, produção de peças prontas. Botão "Não é venda — descartar" fecha sem cobrar nada além do consumo, se quiser lançar.
- **Histórico da impressora:** tela que lista os trabalhos do Moonraker ainda não trazidos. Nada é importado em massa; o usuário toca nos que quer trazer. Itens antigos entram como `arquivada` (contam nas estatísticas de horas/filamento se o usuário informar consumo, nunca viram pendência).
- **Estado ao vivo** na tela da impressora: estado, arquivo, % e tempo restante, temperaturas do bico e da mesa, miniatura.
- Impressão manual: modelo, impressora, tempo, filamentos/gramas — os mesmos campos da confirmação.

### 8.5 Clientes, pedidos e vendas
- Cliente: nome, telefone, e-mail, observações; perfil com histórico de pedidos e total comprado.
- Pedido: cliente (opcional), canal, itens (modelo, quantidade, preço unitário — sugerido pelo modelo), desconto, frete cobrado, custo de envio, pago (sim/não, forma), status `orçamento → aprovado → produzindo → pronto → entregue` (ou `cancelado`).
- **Venda rápida:** um pedido criado já como entregue e pago, em uma tela. É o caminho do botão "+".
- Ao marcar como entregue: baixa as peças prontas (se faltar estoque, avisa mas permite). O custo de cada item é congelado no momento da venda (custo médio das peças produzidas daquele modelo; sem produção registrada, custo calculado da receita).

### 8.6 Despesas e painel
- Despesa avulsa: data, categoria (equipamento, manutenção, energia, ferramenta, outros), valor, descrição. Compras de carretel e de insumo entram automaticamente como gasto na data da compra.
- **Painel** (período selecionável, padrão mês atual):
  - Receita (vendas entregues), Gastos (compras + despesas), **Resultado** (receita − gastos) e **Lucro das vendas** (receita − custo dos itens − taxas − envio).
  - Gráfico receita × gastos por mês (`fl_chart`).
  - Mais vendidos, impressões a confirmar, estoque baixo (filamento/insumo/peça), horas de impressão e kg de filamento no período, impressora ao vivo.

## 9. Sem internet (decisão do builder, documentada)

O servidor é a fonte da verdade. No navegador o app só funciona online. No Android:
- **Leitura:** as respostas das telas principais ficam em cache local; sem conexão, o app mostra a última versão com uma faixa "sem conexão — dados de HH:MM".
- **Escrita:** toda criação/alteração gera o ID (UUID) no aparelho e vai para uma **fila local** (método, rota, corpo). A fila é enviada em ordem quando a conexão volta; como os IDs vêm do aparelho e o servidor trata o mesmo ID como a mesma operação (idempotência), reenviar não duplica nada.
- Conflitos: estoque não conflita (movimentos se somam); edição do mesmo cadastro por duas pessoas usa "a última gravação vence" pelo `atualizado_em`.
- A calculadora funciona 100% offline.

Motivo: offline completo com sincronização bidirecional (como no Meu Frete) é caro para dados compartilhados entre sócios; cache + fila cobre o caso de "sem sinal na hora de lançar" com muito menos código.

## 10. Notificações (sem Firebase)

- A API expõe um WebSocket `/api/ao-vivo` com os eventos da empresa (progresso, fim/falha de impressão, estoque baixo).
- No Android, um **serviço em primeiro plano** (opcional, ligado em Configurações → "Monitorar impressoras") mantém essa conexão:
  - Durante uma impressão, a notificação fixa mostra barra de progresso, % e tempo restante (como o Mobileraker).
  - No fim ou na falha, notificação de alerta com som; tocar abre a tela de confirmar.
  - Ocioso, a notificação fixa fica discreta ("Cubo³ monitorando"). O Android exige uma notificação visível para serviços em primeiro plano.
- Pedir ao usuário para tirar o app da otimização de bateria (alguns fabricantes matam serviços).
- Tipo de serviço `specialUse` (o APK não passa pela Play Store; se um dia for publicado, revisar).
- No navegador: notificação do navegador enquanto a aba estiver aberta.
- Riscos aceitos: gasto de bateria um pouco maior; em aparelhos agressivos (Xiaomi etc.) o serviço pode morrer — ao reabrir o app ele volta e as pendências aparecem do mesmo jeito.

## 11. Identidade visual (decisão do builder; Kerlon pode mudar depois)

- **Nome:** Cubo³. **Logo:** cubo isométrico em traço (3 faces visíveis, a de cima preenchida com o índigo) + "Cubo³" em peso semibold; versão só-símbolo para o ícone do app. SVG no repositório.
- **Cor:** neutros cinza-zinco + um único destaque **índigo `#5E5CE6`** (no tema escuro, `#7D7AFF`). Laranja foi recusado pelo Kerlon. Verde/vermelho só para lucro/prejuízo e alertas. Tema claro e escuro, seguindo o sistema.
- **Tipografia:** Inter empacotada no app (sem buscar fonte da internet), números tabulares nos valores.
- **Navegação Android:** barra inferior com 5 abas — Início (painel), Impressões, Catálogo, Estoque, Vendas. Botão "+" global com: Venda rápida, Lançar impressão, Novo carretel, Orçar peça. Resto (Clientes, Impressoras, Calculadora, Despesas, Empresa e usuários, Configurações) no menu "Mais".
- **Navegador/tela larga:** a mesma app com trilho lateral em vez da barra inferior; listas viram tabelas com mais colunas.
- **Tom:** cartões limpos, muito espaço, números grandes nos totais, sem ícones decorativos em excesso. Valores em R$ no padrão brasileiro.

## 12. Testes e verificação

- Servidor (pytest): caso de teste da planilha (seção 7); isolamento entre empresas (usuário da empresa A nunca lê/escreve dados da B, inclusive arquivos); saldo por movimentos; idempotência da fila (mesmo UUID duas vezes = uma operação); confirmação de impressão gerando os movimentos certos; parser de eventos do Moonraker com o JSON real capturado em 2026-11-02.
- App (flutter test): mesmo caso de teste da calculadora; fila offline; formatação de R$.
- Verificação final: subir no `.150`, login pelo celular via `cubo3.kerlonr.com.br`, imprimir algo pequeno de verdade e ver a notificação de progresso, a pendência e a confirmação descontando o carretel.

## 13. Deixado para o builder

Estrutura interna de pastas e nomes de tabelas; ORM (SQLAlchemy + Alembic recomendado); gerenciamento de estado no Flutter (provider, como no Meu Frete); pacotes exatos (`file_picker`, `flutter_local_notifications`, `flutter_foreground_task` ou equivalentes); layout fino das telas dentro do que está na seção 11; política de rotação de logs.

## 14. Pendências fora deste projeto

- Proteger `v3.thalesgmartins.com.br` (Cloudflare Access ou `force_logins`): hoje qualquer pessoa na internet controla a impressora.
- Senha fraca do usuário `server` no `.150`.
- Reorganização geral do `.150`.
- Fase 2: vitrine pública e landing page.

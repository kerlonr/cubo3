import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ao_vivo/canal_ao_vivo.dart';
import '../ao_vivo/servico_notificacao.dart';
import '../api/fila.dart';
import '../atualizacao.dart';
import '../widgets/adaptativo.dart';

import '../widgets/animacoes.dart';

import 'catalogo/catalogo_aba.dart';
import 'catalogo/modelo_form.dart';
import 'estoque/carretel_form.dart';
import 'impressoes/confirmar_tela.dart';
import 'impressora/impressora_aba.dart';
import 'inicio/inicio_aba.dart';
import 'orcar/orcar_tela.dart';
import 'mais/financeiro_tela.dart';
import 'mais/mais_tela.dart';
import 'vendas/venda_rapida_tela.dart';
import 'vendas/vendas_aba.dart';

/// Navegação principal: 4 abas + "+" global. Compacto (< 600 dp): barra inferior; médio e expandido: trilho lateral.
/// Aba pedida de fora da árvore (toque na notificação). A casca vai para ela e limpa o pedido.
final abaPedida = ValueNotifier<int?>(null);

class Casca extends StatefulWidget {
  const Casca({super.key});

  @override
  State<Casca> createState() => CascaState();
}

class CascaState extends State<Casca> with SingleTickerProviderStateMixin {
  int aba = 0;
  int aConfirmar = 0;
  final impressoes = GlobalKey<ImpressoraAbaState>();
  StreamSubscription<Map>? _eventos;

  @override
  void initState() {
    super.initState();
    _troca = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: 1);
    _eventos = context.read<CanalAoVivo>().eventos.listen(_aoEvento);
    abaPedida.addListener(_irParaPedida);
    WidgetsBinding.instance.addPostFrameCallback((_) => _irParaPedida()); // pedido feito antes da casca existir
  }

  @override
  void dispose() {
    _troca.dispose();
    abaPedida.removeListener(_irParaPedida);
    _eventos?.cancel();
    super.dispose();
  }

  /// Impressões já avisadas: o servidor pode mandar o mesmo fim de novo (reconexão).
  final _avisadas = <String>{};

  /// Fim de impressão com o app aberto: recarrega a lista, avisa na tela e, no navegador, notifica.
  void _aoEvento(Map e) {
    if (e['tipo'] != 'impressao_terminou' || !mounted) return;
    impressoes.currentState?.recarregar();
    final a = alertaFim(e);
    final id = '${e['impressao_id'] ?? ''}';
    if (id.isNotEmpty && !_avisadas.add(id)) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(a.titulo),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        persist: false, // com ação, o padrão do Flutter é ficar na tela até alguém tocar
        showCloseIcon: true,
        action: id.isEmpty
            ? null
            : SnackBarAction(
                label: 'Confirmar',
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ConfirmarTela(impressaoId: id)))),
      ));
    if (kIsWeb) mostrarAlertaFim(e).catchError((_) {});
  }

  static const _destinos = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Início'),
    (Icons.print_outlined, Icons.print, 'Impressora'),
    (Icons.category_outlined, Icons.category, 'Catálogo'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Vendas'),
  ];

  late final AnimationController _troca;

  /// Bolhas do "+" à mostra.
  bool _acoesAbertas = false;

  void _alternarAcoes() => setState(() => _acoesAbertas = !_acoesAbertas);

  Future<void> _escolher(String acao) async {
    setState(() => _acoesAbertas = false);
    await abrirTela(context, telaDaAcao(acao));
  }

  void _irParaPedida() {
    final i = abaPedida.value;
    if (i == null || !mounted) return;
    abaPedida.value = null;
    irPara(i);
  }

  void irPara(int i) {
    if (i == aba) return;
    setState(() => aba = i);
    if (MediaQuery.maybeDisableAnimationsOf(context) != true) _troca.forward(from: 0);
  }

  List<Widget> get _abas => [
        const InicioAba(),
        ImpressoraAba(key: impressoes, ativa: aba == 1, aoContar: (n) => setState(() => aConfirmar = n)),
        const CatalogoAba(),
        const VendasAba(),
      ];

  Widget _icone(int i, bool selecionado) {
    final icone = Icon(selecionado ? _destinos[i].$2 : _destinos[i].$1);
    if (i != 1) return icone;
    return Badge(isLabelVisible: aConfirmar > 0, label: Text('$aConfirmar'), child: icone);
  }

  @override
  Widget build(BuildContext context) {
    final conteudo = Column(children: [
      const FaixaAtualizacao(),
      Expanded(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _troca, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                .animate(CurvedAnimation(parent: _troca, curve: Curves.easeOutCubic)),
            child: IndexedStack(index: aba, children: _abas),
          ),
        ),
      ),
    ]);
    // Véu sob as bolhas: escurece o que está atrás e fecha ao tocar fora.
    final corpo = Stack(children: [
      conteudo,
      Positioned.fill(
        child: IgnorePointer(
          ignoring: !_acoesAbertas,
          child: AnimatedOpacity(
            opacity: _acoesAbertas ? 1 : 0,
            duration: duracaoAnimacao(context, 180),
            child: GestureDetector(
              key: const Key('veu'),
              onTap: _alternarAcoes,
              child: ColoredBox(color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.45)),
            ),
          ),
        ),
      ),
    ]);
    if (ClasseLargura.de(context) != ClasseLargura.compacto) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: aba,
            onDestinationSelected: irPara,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              // No trilho não há espaço para as bolhas: aqui as ações saem num menu ao lado.
              child: MenuAnchor(
                menuChildren: [
                  for (final (icone, rotulo) in acoesRapidas)
                    MenuItemButton(
                        leadingIcon: Icon(icone), onPressed: () => _escolher(rotulo), child: Text(rotulo)),
                ],
                builder: (_, menu, _) => FloatingActionButton(
                  heroTag: 'novo',
                  elevation: 0,
                  tooltip: 'Novo',
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  child: const Icon(Icons.add),
                ),
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(tooltip: 'Mais', icon: const Icon(Icons.menu), onPressed: () => abrirMais(context)),
                ),
              ),
            ),
            destinations: [
              for (var i = 0; i < _destinos.length; i++)
                NavigationRailDestination(
                    icon: _icone(i, false), selectedIcon: _icone(i, true), label: Text(_destinos[i].$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: corpo),
        ]),
      );
    }
    return Scaffold(
      body: corpo,
      // Na aba Impressora o "+" cobriria o envio do console e os controles; lá o "+" fica no topo.
      floatingActionButton: aba == 1
          ? null
          : BotaoAcoes(aberto: _acoesAbertas, aoAlternar: _alternarAcoes, aoEscolher: _escolher),
      bottomNavigationBar: NavigationBar(
        selectedIndex: aba,
        onDestinationSelected: irPara,
        destinations: [
          for (var i = 0; i < _destinos.length; i++)
            NavigationDestination(icon: _icone(i, false), selectedIcon: _icone(i, true), label: _destinos[i].$3),
        ],
      ),
    );
  }
}

/// Abre um cadastro e, na volta, as telas abertas recarregam (mostram o que acabou de ser lançado).
Future<void> abrirTela(BuildContext context, Widget tela) async {
  await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
  dadosMudaram.value++;
}

void abrirMais(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MaisTela()));

/// Tudo que se lança no dia a dia, a um toque do "+": vender, orçar, gastar, repor e cadastrar.
/// A ordem é a de uso, da mais comum para a mais rara.
const acoesRapidas = <(IconData, String)>[
  (Icons.point_of_sale_outlined, 'Venda rápida'),
  (Icons.note_add_outlined, 'Novo pedido'),
  (Icons.calculate_outlined, 'Orçar peça'),
  (Icons.payments_outlined, 'Lançar gasto'),
  (Icons.album_outlined, 'Comprar filamento'),
  (Icons.category_outlined, 'Novo modelo'),
];

/// Tela de cada ação do "+".
Widget telaDaAcao(String acao) => switch (acao) {
      'Venda rápida' => const VendaRapidaTela(),
      'Novo pedido' => const VendaRapidaTela(orcamento: true),
      'Orçar peça' => const OrcarTela(),
      'Lançar gasto' => const DespesaForm(),
      'Comprar filamento' => const CarretelForm(),
      _ => const ModeloForm(),
    };

/// "+" que abre as ações em bolhas logo acima dele: a tela de baixo continua à vista e um
/// toque fora fecha. As bolhas sobem escalonadas, a primeira ação mais perto do polegar.
class BotaoAcoes extends StatefulWidget {
  const BotaoAcoes({super.key, required this.aberto, required this.aoAlternar, required this.aoEscolher});
  final bool aberto;
  final VoidCallback aoAlternar;
  final void Function(String acao) aoEscolher;

  @override
  State<BotaoAcoes> createState() => _BotaoAcoesState();
}

class _BotaoAcoesState extends State<BotaoAcoes> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void didUpdateWidget(BotaoAcoes velho) {
    super.didUpdateWidget(velho);
    if (widget.aberto == velho.aberto) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.value = widget.aberto ? 1 : 0;
    } else if (widget.aberto) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Bolha [i] (0 = a mais próxima do "+"): etiqueta à esquerda e botão pequeno à direita.
  Widget _bolha(int i, IconData icone, String rotulo) {
    final t = Theme.of(context);
    final inicio = i / (acoesRapidas.length * 1.6);
    final anima = CurvedAnimation(
        parent: _c, curve: Interval(inicio, 1, curve: Curves.easeOutBack), reverseCurve: const Interval(0, 1));
    return FadeTransition(
      opacity: _c,
      child: ScaleTransition(
        scale: anima,
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Card(
              elevation: 2,
              margin: EdgeInsets.zero,
              color: t.colorScheme.surfaceContainerHigh,
              // A etiqueta também abre: alvo maior que a bolha sozinha.
              child: InkWell(
                onTap: () => widget.aoEscolher(rotulo),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(rotulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FloatingActionButton.small(
              heroTag: null,
              tooltip: rotulo,
              backgroundColor: t.colorScheme.primaryContainer,
              foregroundColor: t.colorScheme.onPrimaryContainer,
              onPressed: () => widget.aoEscolher(rotulo),
              child: Icon(icone),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      AnimatedBuilder(
        animation: _c,
        builder: (_, _) => _c.isDismissed
            ? const SizedBox.shrink()
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (i, (icone, rotulo)) in acoesRapidas.indexed.toList().reversed)
                  _bolha(i, icone, rotulo),
              ]),
      ),
      FloatingActionButton(
        heroTag: 'novo',
        tooltip: widget.aberto ? 'Fechar' : 'Novo',
        onPressed: widget.aoAlternar,
        child: AnimatedRotation(
          turns: widget.aberto ? 0.125 : 0,
          duration: duracaoAnimacao(context, 220),
          curve: Curves.easeOutBack,
          child: const Icon(Icons.add),
        ),
      ),
    ]);
  }
}

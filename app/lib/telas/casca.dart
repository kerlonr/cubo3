import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ao_vivo/canal_ao_vivo.dart';
import '../ao_vivo/servico_notificacao.dart';
import '../api/fila.dart';
import '../atualizacao.dart';
import '../widgets/adaptativo.dart';

import 'catalogo/catalogo_aba.dart';
import 'estoque/carretel_form.dart';
import 'estoque/estoque_aba.dart';
import 'impressoes/confirmar_tela.dart';
import 'impressora/impressora_aba.dart';
import 'inicio/inicio_aba.dart';
import 'mais/calculadora_tela.dart';
import 'mais/mais_tela.dart';
import 'vendas/venda_rapida_tela.dart';
import 'vendas/vendas_aba.dart';

/// Navegação principal: 5 abas + "+" global. Compacto (< 600 dp): barra inferior; médio e expandido: trilho lateral.
class Casca extends StatefulWidget {
  const Casca({super.key});

  @override
  State<Casca> createState() => CascaState();
}

class CascaState extends State<Casca> {
  int aba = 0;
  int aConfirmar = 0;
  final impressoes = GlobalKey<ImpressoraAbaState>();
  StreamSubscription<Map>? _eventos;

  @override
  void initState() {
    super.initState();
    _eventos = context.read<CanalAoVivo>().eventos.listen(_aoEvento);
  }

  @override
  void dispose() {
    _eventos?.cancel();
    super.dispose();
  }

  /// Fim de impressão com o app aberto: recarrega a lista, avisa na tela e, no navegador, notifica.
  void _aoEvento(Map e) {
    if (e['tipo'] != 'impressao_terminou' || !mounted) return;
    impressoes.currentState?.recarregar();
    final a = alertaFim(e);
    final id = '${e['impressao_id'] ?? ''}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(a.titulo),
      duration: const Duration(seconds: 10),
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
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Estoque'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Vendas'),
  ];

  void irPara(int i) => setState(() => aba = i);

  List<Widget> get _abas => [
        const InicioAba(),
        ImpressoraAba(key: impressoes, ativa: aba == 1, aoContar: (n) => setState(() => aConfirmar = n)),
        const CatalogoAba(),
        const EstoqueAba(),
        const VendasAba(),
      ];

  Widget _icone(int i, bool selecionado) {
    final icone = Icon(selecionado ? _destinos[i].$2 : _destinos[i].$1);
    if (i != 1) return icone;
    return Badge(isLabelVisible: aConfirmar > 0, label: Text('$aConfirmar'), child: icone);
  }

  @override
  Widget build(BuildContext context) {
    final corpo = Column(children: [
      const FaixaAtualizacao(),
      Expanded(child: IndexedStack(index: aba, children: _abas)),
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
              child: FloatingActionButton(
                heroTag: 'mais-acoes',
                elevation: 0,
                tooltip: 'Novo',
                onPressed: () => abrirAcoesRapidas(context),
                child: const Icon(Icons.add),
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
          : FloatingActionButton(
              tooltip: 'Novo',
              onPressed: () => abrirAcoesRapidas(context),
              child: const Icon(Icons.add),
            ),
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

/// Botão "+": Venda rápida, Lançar impressão, Novo carretel, Orçar peça.
Future<void> abrirAcoesRapidas(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        Future<void> abrir(Widget tela) {
          Navigator.pop(c);
          return abrirTela(context, tela);
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.point_of_sale),
                title: const Text('Venda rápida'),
                onTap: () => abrir(const VendaRapidaTela())),
            ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Lançar impressão'),
                onTap: () => abrir(const ConfirmarTela())),
            ListTile(
                leading: const Icon(Icons.album_outlined),
                title: const Text('Novo carretel'),
                onTap: () => abrir(const CarretelForm())),
            ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Orçar peça'),
                onTap: () => abrir(const CalculadoraTela())),
          ]),
        );
      },
    );

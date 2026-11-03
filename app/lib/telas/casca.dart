import 'package:flutter/material.dart';

import 'catalogo/catalogo_aba.dart';
import 'estoque/carretel_form.dart';
import 'estoque/estoque_aba.dart';
import 'impressoes/confirmar_tela.dart';
import 'impressoes/impressoes_aba.dart';
import 'mais/mais_tela.dart';
import 'vendas/venda_rapida_tela.dart';
import 'vendas/vendas_aba.dart';

/// Navegação principal: 5 abas + "+" global. Tela larga (≥ 840 px) troca a barra pelo trilho lateral.
class Casca extends StatefulWidget {
  const Casca({super.key});

  @override
  State<Casca> createState() => CascaState();
}

class CascaState extends State<Casca> {
  int aba = 0;
  int aConfirmar = 0;
  final impressoes = GlobalKey<ImpressoesAbaState>();

  static const _destinos = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Início'),
    (Icons.print_outlined, Icons.print, 'Impressões'),
    (Icons.category_outlined, Icons.category, 'Catálogo'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Estoque'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Vendas'),
  ];

  void irPara(int i) => setState(() => aba = i);

  List<Widget> get _abas => [
        _AbaProvisoria(_destinos[0].$3),
        ImpressoesAba(key: impressoes, aoContar: (n) => setState(() => aConfirmar = n)),
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
    final corpo = IndexedStack(index: aba, children: _abas);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 840) {
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
        floatingActionButton: FloatingActionButton(
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
    });
  }
}

void abrirMais(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MaisTela()));

/// Botão "+": Venda rápida, Lançar impressão, Novo carretel, Orçar peça.
Future<void> abrirAcoesRapidas(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        void abrir(Widget tela) {
          Navigator.pop(c);
          Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
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
                leading: const Icon(Icons.circle_outlined),
                title: const Text('Novo carretel'),
                onTap: () => abrir(const CarretelForm())),
            ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Orçar peça'),
                onTap: () => abrir(const _AbaProvisoria('Orçar peça'))),
          ]),
        );
      },
    );

class _AbaProvisoria extends StatelessWidget {
  const _AbaProvisoria(this.titulo);
  final String titulo;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(titulo)));
}

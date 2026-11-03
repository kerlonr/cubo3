import 'package:flutter/material.dart';

/// Classes de largura do Material 3 (dp): compacto < 600, médio 600–839, expandido ≥ 840.
enum ClasseLargura {
  compacto,
  medio,
  expandido;

  static ClasseLargura daLargura(double largura) => largura < 600 ? compacto : (largura < 840 ? medio : expandido);

  static ClasseLargura de(BuildContext context) => daLargura(MediaQuery.sizeOf(context).width);
}

/// Conteúdo principal e lista lado a lado em tela expandida; numa coluna só (lista embaixo) nas outras.
class ListaDetalhe extends StatelessWidget {
  const ListaDetalhe({super.key, required this.detalhe, required this.lista, this.larguraLista = 400});

  final List<Widget> detalhe;
  final List<Widget> lista;
  final double larguraLista;

  static const _margem = EdgeInsets.fromLTRB(16, 0, 16, 96);

  @override
  Widget build(BuildContext context) {
    if (detalhe.isEmpty || ClasseLargura.de(context) != ClasseLargura.expandido) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: _margem, children: [...detalhe, ...lista]),
        ),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: ListView(padding: _margem, children: detalhe)),
      const VerticalDivider(width: 1),
      SizedBox(width: larguraLista, child: ListView(padding: _margem, children: lista)),
    ]);
  }
}

/// Cartões em colunas com a altura do conteúdo (sem proporção fixa, que corta texto em tela estreita).
class GradeCartoes extends StatelessWidget {
  const GradeCartoes({super.key, required this.colunas, required this.children, this.espaco = 8});

  final int colunas;
  final List<Widget> children;
  final double espaco;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < children.length; i += colunas)
          Padding(
            padding: EdgeInsets.only(bottom: espaco),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var j = i; j < i + colunas; j++) ...[
                  if (j > i) SizedBox(width: espaco),
                  Expanded(child: j < children.length ? children[j] : const SizedBox()),
                ],
              ]),
            ),
          ),
      ]);
}

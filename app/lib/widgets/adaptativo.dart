import 'package:flutter/material.dart';

/// Classes de largura do Material 3 (dp): compacto < 600, médio 600–839, expandido ≥ 840.
enum ClasseLargura {
  compacto,
  medio,
  expandido;

  static ClasseLargura daLargura(double largura) => largura < 600 ? compacto : (largura < 840 ? medio : expandido);

  static ClasseLargura de(BuildContext context) => daLargura(MediaQuery.sizeOf(context).width);
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

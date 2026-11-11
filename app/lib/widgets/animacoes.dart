import 'package:flutter/material.dart';

import '../util/formatos.dart';

/// Duração que respeita o "reduzir animações" do aparelho.
Duration duracaoAnimacao(BuildContext context, int ms) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : Duration(milliseconds: ms);

/// Aparece subindo e clareando uma vez; [ordem] escalona a entrada dos cartões de uma lista.
class Entrada extends StatelessWidget {
  const Entrada({super.key, required this.child, this.ordem = 0});
  final Widget child;
  final int ordem;

  @override
  Widget build(BuildContext context) {
    final atraso = (ordem.clamp(0, 8)) * 70;
    final total = 450 + atraso;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duracaoAnimacao(context, total),
      curve: Interval(atraso / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (_, v, filho) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 24), child: filho),
      ),
    );
  }
}

/// Valor em R$ que desliza até o número novo quando muda.
class ValorAnimado extends StatelessWidget {
  const ValorAnimado(this.valor, {super.key, this.estilo, this.chaveTexto});
  final double valor;
  final TextStyle? estilo;

  /// Chave do Text (os testes leem o valor final por ela).
  final Key? chaveTexto;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        // begin só vale na primeira vez: ao abrir conta do zero; depois desliza do valor anterior.
        tween: Tween(begin: 0, end: valor),
        duration: duracaoAnimacao(context, 600),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(moeda(v), key: chaveTexto, softWrap: false, style: estilo),
      );
}

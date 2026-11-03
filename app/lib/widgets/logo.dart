import 'package:flutter/material.dart';

/// Cubo isométrico em traço; a face de cima é preenchida com o índigo.
class LogoCubo3 extends StatelessWidget {
  const LogoCubo3({super.key, this.tamanho = 48, this.comNome = false, this.corTraco});

  final double tamanho;
  final bool comNome;
  final Color? corTraco;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cubo = CustomPaint(
      size: Size.square(tamanho),
      painter: PintorCubo(traco: corTraco ?? t.colorScheme.onSurface, topo: t.colorScheme.primary),
    );
    if (!comNome) return cubo;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      cubo,
      SizedBox(width: tamanho * 0.25),
      Text('Cubo³', style: TextStyle(fontSize: tamanho * 0.6, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
    ]);
  }
}

class PintorCubo extends CustomPainter {
  PintorCubo({required this.traco, required this.topo});

  final Color traco;
  final Color topo;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final esp = w * 0.06;
    final c = Offset(w / 2, h / 2);
    final r = w * 0.42;
    // Hexágono isométrico: topo, sup. dir., inf. dir., base, inf. esq., sup. esq.
    final pTopo = Offset(c.dx, c.dy - r);
    final pSupDir = Offset(c.dx + r * 0.866, c.dy - r / 2);
    final pInfDir = Offset(c.dx + r * 0.866, c.dy + r / 2);
    final pBase = Offset(c.dx, c.dy + r);
    final pInfEsq = Offset(c.dx - r * 0.866, c.dy + r / 2);
    final pSupEsq = Offset(c.dx - r * 0.866, c.dy - r / 2);

    final faceTopo = Path()..addPolygon([pTopo, pSupDir, c, pSupEsq], true);
    canvas.drawPath(faceTopo, Paint()..color = topo);

    final linha = Paint()
      ..color = traco
      ..style = PaintingStyle.stroke
      ..strokeWidth = esp
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()..addPolygon([pTopo, pSupDir, pInfDir, pBase, pInfEsq, pSupEsq], true), linha);
    canvas.drawLine(pSupEsq, c, linha);
    canvas.drawLine(pSupDir, c, linha);
    canvas.drawLine(c, pBase, linha);
  }

  @override
  bool shouldRepaint(PintorCubo old) => old.traco != traco || old.topo != topo;
}

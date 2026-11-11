import 'package:flutter/material.dart';

/// Classes de largura do Material 3 (dp): compacto < 600, médio 600–839, expandido ≥ 840.
enum ClasseLargura {
  compacto,
  medio,
  expandido;

  static ClasseLargura daLargura(double largura) => largura < 600 ? compacto : (largura < 840 ? medio : expandido);

  static ClasseLargura de(BuildContext context) => daLargura(MediaQuery.sizeOf(context).width);
}

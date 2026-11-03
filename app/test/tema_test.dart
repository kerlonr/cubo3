import 'package:cubo3/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tema claro usa o índigo da marca e a Inter', () {
    final t = temaCubo3(Brightness.light);
    expect(t.colorScheme.primary, indigo);
    expect(t.textTheme.bodyMedium!.fontFamily, 'Inter');
  });

  test('tema escuro usa o índigo claro', () {
    expect(temaCubo3(Brightness.dark).colorScheme.primary, indigoEscuro);
  });
}

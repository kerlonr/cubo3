import 'package:cubo3/util/formatos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moeda no padrão brasileiro', () {
    expect(moeda(6.32), 'R\$ 6,32');
    expect(moeda(1234.5), 'R\$ 1.234,50');
  });

  test('lerNumero aceita padrão brasileiro e recusa lixo sem exceção', () {
    expect(lerNumero('1.234,56'), 1234.56);
    expect(lerNumero('33,5'), 33.5);
    expect(lerNumero('33,5 g'), 33.5);
    expect(lerNumero('R\$ 12,90'), 12.9);
    expect(lerNumero(''), isNull);
    expect(lerNumero(null), isNull);
    expect(lerNumero('abc'), isNull);
  });

  test('lerNumero: ponto só de milhar vira milhar ("1.000 g" é mil, não um)', () {
    expect(lerNumero('1.000'), 1000);
    expect(lerNumero('12.500 g'), 12500);
    expect(lerNumero('1.000.000'), 1000000);
    expect(lerNumero('33.5'), 33.5);
    expect(lerNumero('1.25'), 1.25);
  });

  test('arred2 arredonda meio para cima sem erro binário', () {
    expect(arred2(100.025), 100.03);
    expect(arred2(2.675), 2.68);
    expect(arred2(6.315), 6.32);
    expect(arred2(-0.205), -0.21);
  });

  test('gramas e paraCampo', () {
    expect(gramas(33.5), '33,5 g');
    expect(gramas(1000), '1.000 g');
    expect(paraCampo(33.5), '33,5');
    expect(paraCampo(null), '');
  });
}

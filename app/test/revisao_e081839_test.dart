import 'package:cubo3/dominio/custos.dart';
import 'package:cubo3/telas/vendas/pedido_tela.dart';
import 'package:flutter_test/flutter_test.dart';

int centavos(List<({double quantidade, double preco})> itens, List<double> precos) {
  var s = 0;
  for (var k = 0; k < itens.length; k++) {
    s += (precos[k] * 100).round() * itens[k].quantidade.toInt();
  }
  return s;
}

void main() {
  test('distribuirTotal sem item de 1 unidade: total digitado não fecha (e havia solução exata)', () {
    final itens = [(quantidade: 2.0, preco: 10.0), (quantidade: 3.0, preco: 10.0)];
    final precos = distribuirTotal(itens, 45.01);
    // 2 x 10,01 + 3 x 8,33 = 45,01 existe; o algoritmo entrega outro total.
    expect(centavos(itens, precos), isNot(4501), reason: '$precos');
  });

  test('distribuirTotal com um item de 2 unidades: 25,01 vira outro total sem aviso', () {
    final itens = [(quantidade: 2.0, preco: 12.5)];
    expect(centavos(itens, distribuirTotal(itens, 25.01)), isNot(2501));
  });

  test('peças por impressão: app e servidor (29,59 sem o campo; 6,32 com 6)', () {
    const emp = ParamEmpresa();
    const imp = ParamImpressora();
    final r6 = calcularCusto(Receita([ItemFilamento(198, 100)], 18, 10, rendimento: 6), imp, emp);
    final r1 = calcularCusto(Receita([ItemFilamento(198, 100)], 18, 10), imp, emp);
    final r0 = calcularCusto(Receita([ItemFilamento(198, 100)], 18, 10, rendimento: 0), imp, emp);
    expect([r6.total, r1.total, r0.total], [6.32, 29.59, 29.59]);
  });
}

import 'package:cubo3/telas/vendas/vendas_aba.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pedidos = [
    {'id': 'orc', 'status': 'orcamento', 'pago': false, 'itens': []},
    {'id': 'apr', 'status': 'aprovado', 'pago': false, 'itens': []},
    {'id': 'prod', 'status': 'produzindo', 'pago': true, 'itens': []},
    {'id': 'pronto', 'status': 'pronto', 'pago': false, 'itens': []},
    {'id': 'ent', 'status': 'entregue', 'pago': true, 'receita': 50, 'itens': []},
    {'id': 'ent2', 'status': 'entregue', 'pago': false, 'receita': 30, 'itens': []},
    {'id': 'canc', 'status': 'cancelado', 'pago': true, 'itens': []},
    {'id': 'orcpago', 'status': 'orcamento', 'pago': true, 'itens': []},
  ];
  List<String> ids(String filtro) => [for (final p in pedidos) if (filtrosPedido[filtro]!(p)) p['id'] as String];

  test('cada filtro de Vendas pega os pedidos certos', () {
    expect(filtrosPedido.keys, ['Em andamento', 'Entregues', 'Pagos', 'A receber', 'Orçamentos', 'Todos']);
    expect(ids('Em andamento'), ['apr', 'prod', 'pronto']);
    expect(ids('Entregues'), ['ent', 'ent2']);
    // Pago e não cancelado (orçamento já pago, como sinal, também conta).
    expect(ids('Pagos'), ['prod', 'ent', 'orcpago']);
    // Não pago, sem orçamento nem cancelado.
    expect(ids('A receber'), ['apr', 'pronto', 'ent2']);
    expect(ids('Orçamentos'), ['orc', 'orcpago']);
    expect(ids('Todos').length, pedidos.length);
  });

  test('total do filtro soma receita do entregue e a conta dos itens dos outros', () {
    expect(totalDe([]), 0);
    expect(
        totalDe([
          {'receita': 50, 'itens': []},
          {
            'desconto': 2,
            'frete_cobrado': 5,
            'itens': [
              {'quantidade': 2, 'preco_unitario': 10.5}
            ]
          },
        ]),
        closeTo(74, 0.001));
  });
}

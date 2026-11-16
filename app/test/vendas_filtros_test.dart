import 'package:cubo3/telas/vendas/vendas_aba.dart';
import 'package:cubo3/telas/vendas/pedido_tela.dart';
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

  test('com parcelas: selo e filtros saem do saldo', () {
    final parcial = {'status': 'entregue', 'pago': false, 'receita': 50, 'total': 50, 'recebido': 20, 'saldo': 30, 'itens': []};
    final quitado = {'status': 'entregue', 'pago': true, 'receita': 50, 'total': 50, 'recebido': 50, 'saldo': 0, 'itens': []};
    final nada = {'status': 'entregue', 'pago': false, 'receita': 50, 'total': 50, 'recebido': 0, 'saldo': 50, 'itens': []};
    expect(seloPagamento(parcial), 'Parcial');
    expect(seloPagamento(quitado), 'Pago');
    expect(seloPagamento(nada), 'A receber');
    expect(seloPagamento({'status': 'orcamento', 'pago': false, 'itens': []}), isNull);
    expect(seloPagamento({'status': 'orcamento', 'recebido': 10, 'saldo': 20, 'itens': []}), 'Parcial', reason: 'sinal');
    expect(seloPagamento({...quitado, 'status': 'cancelado'}), isNull);
    expect(filtrosPedido['A receber']!(parcial), isTrue);
    expect(filtrosPedido['Pagos']!(parcial), isFalse);
    expect(filtrosPedido['Pagos']!(quitado), isTrue);
    expect(totalAReceber([parcial, nada]), 80);
    // Pedido antigo, sem os campos novos: pago vale o total.
    expect(saldoPedido({'pago': false, 'receita': 30, 'itens': []}), 30);
    expect(saldoPedido({'pago': true, 'receita': 30, 'itens': []}), 0);
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

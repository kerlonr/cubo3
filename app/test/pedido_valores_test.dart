import 'package:cubo3/telas/vendas/pedido_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

Map<String, Object?> pedido({List<Map> anexos = const []}) => {
      'id': 'p1',
      'status': 'entregue',
      'pago': true,
      'forma_pagamento': 'Pix',
      'atualizado_em': '2026-11-15T12:00:00+00:00',
      'receita': 44.9,
      'bruto': 44.9,
      'lucro': 30,
      'desconto': 0,
      'frete_cobrado': 0,
      'cliente': {'id': 'k1', 'nome': 'Renan', 'telefone': null},
      'avisos': [],
      'anexos': anexos,
      'itens': [
        {'id': 'i1', 'modelo_id': 'm1', 'descricao': 'Vaso', 'quantidade': 1, 'preco_unitario': 19.9},
        {'id': 'i2', 'modelo_id': 'm2', 'descricao': 'Chaveiro', 'quantidade': 2, 'preco_unitario': 12.5},
      ],
    };

Future<Ambiente> abrir(WidgetTester tester, Map<String, Object?> p) async {
  final amb = Ambiente({'GET /api/pedidos/p1': (_) => p});
  await amb.preparar();
  await tamanhoTela(tester, 400, 1400);
  await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1')));
  await tester.pumpAndSettle();
  return amb;
}

Finder campo(String chave) => find.descendant(of: find.byKey(Key(chave)), matching: find.byType(TextField));

void main() {
  test('distribuirTotal: 45 em dois itens fecha exato, sobra de centavos no item de 1 unidade', () {
    final precos = distribuirTotal([(quantidade: 1, preco: 19.9), (quantidade: 2, preco: 12.5)], 45);
    expect(precos, [19.94, 12.53]);
    expect(precos[0] + precos[1] * 2, closeTo(45, 1e-9));
    expect(distribuirTotal([(quantidade: 1, preco: 30), (quantidade: 1, preco: 20)], 45), [27, 18]);
    expect(distribuirTotal([(quantidade: 1, preco: 0), (quantidade: 1, preco: 0)], 45), [22.5, 22.5]);
    final tres = distribuirTotal([(quantidade: 1, preco: 10), (quantidade: 1, preco: 10), (quantidade: 1, preco: 10)], 10);
    expect(tres, [3.33, 3.33, 3.34]);
  });

  testWidgets('comprovantes aparecem e apagar pede confirmação e manda o DELETE', (tester) async {
    final amb = await abrir(tester, pedido(anexos: [
      {'id': 'a1', 'nome_original': 'pix.jpg', 'tipo': 'foto', 'tamanho': 10, 'url': '/api/anexos/a1'},
      {'id': 'a2', 'nome_original': 'pix.pdf', 'tipo': 'pdf', 'tamanho': 10, 'url': '/api/anexos/a2'},
    ]));
    expect(find.byKey(const ValueKey('anexo-a1')), findsOneWidget);
    expect(find.text('pix.pdf'), findsOneWidget);
    expect(find.byTooltip('Anexar comprovante (foto ou PDF)'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('anexo-a1')), matching: find.byTooltip('Apagar comprovante')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('DELETE /api/anexos/a1'), isNotNull);
    expect(amb.ultimo('DELETE /api/anexos/a2'), isNull);
  });

  testWidgets('editar preço manda o PUT com os itens completos e a versão lida', (tester) async {
    final amb = await abrir(tester, pedido());
    await tester.tap(find.byTooltip('Editar valores'));
    await tester.pumpAndSettle();
    await tester.enterText(campo('preco0'), '2500');
    await tester.pump();
    expect(tester.widget<TextField>(campo('total-pedido')).controller!.text, '50,00');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final put = amb.ultimo('PUT /api/pedidos/p1')!;
    expect(put.headers['X-Versao-Base'], '2026-11-15T12:00:00+00:00');
    expect(amb.corpo('PUT /api/pedidos/p1'), {
      'itens': [
        {'id': 'i1', 'modelo_id': 'm1', 'descricao': 'Vaso', 'quantidade': 1, 'preco_unitario': 25.0},
        {'id': 'i2', 'modelo_id': 'm2', 'descricao': 'Chaveiro', 'quantidade': 2, 'preco_unitario': 12.5},
      ],
      'desconto': 0.0,
      'frete_cobrado': 0.0,
    });
  });

  testWidgets('total do pedido 45 distribui nos dois itens e soma R\$ 45,00 exato', (tester) async {
    final amb = await abrir(tester, pedido());
    await tester.tap(find.byTooltip('Editar valores'));
    await tester.pumpAndSettle();
    await tester.enterText(campo('total-pedido'), '4500');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final itens = amb.corpo('PUT /api/pedidos/p1')['itens'] as List;
    final centavos = itens.fold<int>(
        0, (s, i) => s + ((i['preco_unitario'] as num) * 100).round() * (i['quantidade'] as num).toInt());
    expect(centavos, 4500);
    expect([for (final i in itens) i['quantidade']], [1, 2]);
  });

  testWidgets('entregue: mais uma unidade, tirar item e item avulso vão no PUT (mesmos ids)', (tester) async {
    final amb = await abrir(tester, pedido());
    await tester.tap(find.byTooltip('Editar valores'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byKey(const Key('qtd0')), matching: find.byTooltip('Mais')));
    await tester.pump();
    expect(tester.widget<TextField>(campo('total-pedido')).controller!.text, '64,80');
    await tester.tap(find.byTooltip('Tirar item').last);
    await tester.pump();
    await tester.tap(find.text('Item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Modelo ou descrição'), 'Suporte avulso');
    await tester.enterText(campo('preco1'), '1000');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final itens = amb.corpo('PUT /api/pedidos/p1')['itens'] as List;
    expect(itens.first, {'id': 'i1', 'modelo_id': 'm1', 'descricao': 'Vaso', 'quantidade': 2, 'preco_unitario': 19.9});
    expect(itens.length, 2);
    expect(itens[1]['id'], isNot('i2'));
    expect(itens[1], containsPair('descricao', 'Suporte avulso'));
    expect(itens[1], containsPair('modelo_id', null));
    expect(itens[1], containsPair('preco_unitario', 10.0));
  });

  testWidgets('reabrir entregue confirma e volta para Produzindo', (tester) async {
    final amb = await abrir(tester, pedido());
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reabrir pedido'));
    await tester.pumpAndSettle();
    expect(find.textContaining('voltam ao estoque'), findsOneWidget);
    await tester.tap(find.text('Reabrir'));
    await tester.pumpAndSettle();
    expect(amb.corpo('POST /api/pedidos/p1/status'), {'status': 'produzindo'});
  });

  testWidgets('pedido cancelado não mostra editar valores', (tester) async {
    await abrir(tester, {...pedido(), 'status': 'cancelado'});
    expect(find.byTooltip('Editar valores'), findsNothing);
  });
}

import 'package:cubo3/telas/estoque/carretel_form.dart';
import 'package:cubo3/telas/mais/financeiro_tela.dart';
import 'package:cubo3/telas/vendas/pedido_tela.dart';
import 'package:cubo3/widgets/cartoes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

const extrato = {
  'entrou': 100,
  'saiu': 140,
  'resultado': -40,
  'lucro_vendas': 60,
  'perdas_g': 35,
  'perdas_valor': 3.5,
  'linhas': [
    {'tipo': 'venda', 'id': 'p1', 'data': '2026-11-10', 'descricao': 'Vaso · Ana', 'valor': 100, 'lucro': 60, 'pago': false},
    {'tipo': 'despesa', 'id': 'd1', 'data': '2026-11-09', 'descricao': null, 'valor': 20, 'categoria': 'desperdicio'},
    {
      'tipo': 'compra', 'id': 'mov1', 'data': '2026-11-08', 'descricao': 'Cola · 2 un', 'valor': 30,
      'categoria': 'insumo', 'item_tipo': 'insumo', 'item_id': 'i1'
    },
    {
      'tipo': 'compra', 'id': 'mov2', 'data': '2026-11-07', 'descricao': 'Carretel PLA · 1000 g', 'valor': 90,
      'categoria': 'filamento', 'item_tipo': 'carretel', 'item_id': 'car1'
    },
  ],
};

const carretel = {
  'id': 'car1',
  'filamento_id': 'f1',
  'filamento': {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Preto'},
  'peso_inicial_g': 1000,
  'preco_pago': 90,
  'data_compra': '2026-11-07',
  'saldo_g': 800,
  'atualizado_em': '2026-11-07T12:00:00Z',
};

Future<Ambiente> abrirFinanceiro(WidgetTester tester) async {
  final amb = Ambiente({
    'GET /api/extrato': (_) => extrato,
    'GET /api/carreteis/car1': (_) => carretel,
  });
  await amb.preparar();
  valoresOcultos.value = false;
  await tamanhoTela(tester, 360, 1600);
  await tester.pumpWidget(amb.tela(const FinanceiroTela()));
  await tester.pumpAndSettle();
  return amb;
}

void main() {
  testWidgets('Financeiro: extrato do mês pedido ao servidor, cartões, perdas e filtro de saídas', (tester) async {
    final amb = await abrirFinanceiro(tester);
    final q = amb.ultimo('GET /api/extrato')!.url.queryParameters;
    final hoje = DateTime.now();
    expect(q['inicio'], '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-01');
    expect(DateTime.parse(q['fim']!).add(const Duration(days: 1)).day, 1); // último dia do mês
    expect(find.text('R\$ 100,00'), findsOneWidget); // Entrou
    expect(find.text('-R\$ 40,00'), findsOneWidget); // Resultado
    expect(find.textContaining('Perdas: 35 g'), findsOneWidget);
    expect(find.text('Desperdício'), findsOneWidget); // despesa sem descrição mostra a categoria
    await tester.tap(find.widgetWithText(ChoiceChip, 'Saídas'));
    await tester.pumpAndSettle();
    expect(find.text('Vaso · Ana'), findsNothing);
    expect(find.text('Cola · 2 un'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Financeiro: olho esconde os valores', (tester) async {
    await abrirFinanceiro(tester);
    valoresOcultos.value = true;
    await tester.pumpAndSettle();
    expect(find.text('R\$ 100,00'), findsNothing);
    expect(find.text(mascaraValor), findsWidgets);
  });

  testWidgets('Financeiro: compra de insumo se desfaz com confirmação (DELETE do movimento)', (tester) async {
    final amb = await abrirFinanceiro(tester);
    await tester.tap(find.text('Cola · 2 un'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir este lançamento?'), findsOneWidget);
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('DELETE /api/movimentos/mov1'), isNotNull);
  });

  testWidgets('Financeiro: compra de carretel abre a edição do carretel', (tester) async {
    await abrirFinanceiro(tester);
    await tester.tap(find.text('Carretel PLA · 1000 g'));
    await tester.pumpAndSettle();
    expect(find.text('Editar carretel'), findsOneWidget);
    expect(find.text('Voolt PLA Preto'), findsOneWidget);
  });

  testWidgets('carretel: edição grava no mesmo id com a versão lida, sem trocar o filamento', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const CarretelForm(dados: carretel)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('preco')), '95,50');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final put = amb.ultimo('PUT /api/carreteis/car1')!;
    expect(put.headers['X-Versao-Base'], '2026-11-07T12:00:00Z');
    final corpo = amb.corpo('PUT /api/carreteis/car1');
    expect(corpo['preco_pago'], 95.5);
    expect(corpo['peso_inicial_g'], 1000);
    expect(corpo['data_compra'], '2026-11-07');
    expect(corpo.containsKey('filamento_id'), isFalse);
  });

  testWidgets('carretel: excluir avisa que o gasto sai do financeiro', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const CarretelForm(dados: carretel)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Excluir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sai do financeiro'), findsOneWidget);
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('DELETE /api/carreteis/car1'), isNotNull);
  });

  testWidgets('pedido: marcar como pago pergunta a forma; pago pode ser desfeito', (tester) async {
    var pago = false;
    final amb = Ambiente({
      'GET /api/pedidos/p1': (_) => {'id': 'p1', 'status': 'entregue', 'pago': pago, 'itens': [], 'receita': 50},
    });
    amb.rotasPrefixo['PUT /api/pedidos/p1'] = (r) {
      pago = !pago;
      return {'ok': true};
    };
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1')));
    await tester.pumpAndSettle();
    expect(find.text('A receber'), findsOneWidget);
    await tester.tap(find.text('Marcar como pago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pix'));
    await tester.pumpAndSettle();
    expect(amb.corpo('PUT /api/pedidos/p1'), {'pago': true, 'forma_pagamento': 'Pix'});
    await tester.tap(find.text('Desfazer pago'));
    await tester.pumpAndSettle();
    expect(amb.corpo('PUT /api/pedidos/p1'), {'pago': false, 'forma_pagamento': null});
  });
}

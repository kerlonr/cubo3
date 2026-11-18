import 'dart:convert';

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
  'total_linhas': 4,
  'por_mes': [
    {'mes': '2026-09', 'receita': 200, 'gastos': 100, 'lucro': 80},
    {'mes': '2026-10', 'receita': 0, 'gastos': 40, 'lucro': 0},
    {'mes': '2026-11', 'receita': 100, 'gastos': 140, 'lucro': 60},
  ],
  'por_categoria': [
    {'categoria': 'filamento', 'valor': 90},
    {'categoria': 'insumo', 'valor': 30},
    {'categoria': 'desperdicio', 'valor': 20},
  ],
  'linhas': [
    {'tipo': 'venda', 'id': 'p1', 'data': '2026-11-10', 'descricao': 'Vaso · Ana', 'valor': 100, 'lucro': 60, 'pago': false},
    {'tipo': 'despesa', 'id': 'd1', 'data': '2026-11-09', 'descricao': null, 'valor': 20, 'categoria': 'desperdicio'},
    {
      'tipo': 'compra', 'id': 'mov1', 'data': '2026-11-08', 'descricao': 'Cola · 2 un', 'valor': 30,
      'categoria': 'insumo', 'item_tipo': 'insumo', 'item_id': 'i1', 'quantidade': 2
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
  await tamanhoTela(tester, 360, 2600); // extrato + análise: a lista só constrói o que cabe na tela
  await tester.pumpWidget(amb.tela(const FinanceiroTela()));
  await tester.pumpAndSettle();
  return amb;
}

void main() {
  testWidgets('Financeiro: abre no geral (sem datas), cartões, perdas e filtro de saídas', (tester) async {
    final amb = await abrirFinanceiro(tester);
    expect(amb.ultimo('GET /api/extrato')!.url.queryParameters, isEmpty, reason: 'sem datas = desde sempre');
    expect(find.text('Resultado geral'), findsOneWidget);
    expect(find.text('R\$ 100,00'), findsOneWidget); // Entrou
    expect(find.text('-R\$ 40,00'), findsOneWidget); // Resultado
    expect(find.textContaining('Perdas: 35 g'), findsOneWidget);
    // Despesa sem descrição mostra a categoria (a outra "Desperdício" é a do resumo por categoria).
    expect(find.descendant(of: find.byType(ListTile), matching: find.text('Desperdício')), findsOneWidget);
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

  testWidgets('Financeiro: compra de insumo se exclui com confirmação (DELETE do movimento)', (tester) async {
    final amb = await abrirFinanceiro(tester);
    await tester.tap(find.text('Cola · 2 un'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir este lançamento?'), findsOneWidget);
    await tester.tap(find.text('Excluir').last);
    await tester.pumpAndSettle();
    expect(amb.ultimo('DELETE /api/movimentos/mov1'), isNotNull);
    expect(amb.recebidos.where((r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets('Financeiro: corrigir compra de insumo troca o lançamento (mesma data, valor novo)', (tester) async {
    final amb = await abrirFinanceiro(tester);
    await tester.tap(find.text('Cola · 2 un'));
    await tester.pumpAndSettle();
    expect(find.text('Corrigir compra'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const Key('compra_valor')), matching: find.byType(TextFormField)), '25,00');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final escritas = [for (final r in amb.recebidos) if (r.method != 'GET') r];
    expect([for (final r in escritas) r.method], ['DELETE', 'PUT']);
    expect(escritas.first.url.path, '/api/movimentos/mov1');
    final corpo = jsonDecode(escritas.last.body) as Map;
    expect([corpo['item_id'], corpo['tipo'], corpo['quantidade'], corpo['valor']], ['i1', 'compra', 2.0, 25.0]);
    expect(DateTime.parse(corpo['data'] as String).toLocal().day, 8);
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

  testWidgets('pedido antigo pago sem parcelas: desfazer pago volta para a receber', (tester) async {
    var pago = true;
    final amb = Ambiente({
      'GET /api/pedidos/p1': (_) => {'id': 'p1', 'status': 'entregue', 'pago': pago, 'itens': [], 'receita': 50},
    });
    amb.rotasPrefixo['PUT /api/pedidos/p1'] = (r) {
      pago = false;
      return {'ok': true};
    };
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1')));
    await tester.pumpAndSettle();
    expect(find.text('Pago'), findsOneWidget);
    await tester.tap(find.byTooltip('Desfazer pago'));
    await tester.pumpAndSettle();
    expect(amb.corpo('PUT /api/pedidos/p1'), {'pago': false, 'forma_pagamento': null});
    expect(find.text('A receber'), findsOneWidget);
    expect(find.text('Receber'), findsOneWidget);
  });

  testWidgets('pedido com parcelas: desfazer pago apaga a última parcela', (tester) async {
    final amb = Ambiente({
      'GET /api/pedidos/p1': (_) => {
            'id': 'p1', 'status': 'entregue', 'pago': true, 'itens': [], 'receita': 50, 'total': 50, 'recebido': 50,
            'saldo': 0,
            'pagamentos': [
              {'id': 'g1', 'valor': 20, 'forma': 'Pix', 'data': '2026-11-10T12:00:00+00:00'},
              {'id': 'g2', 'valor': 30, 'forma': 'Dinheiro', 'data': '2026-11-12T12:00:00+00:00', 'anexo_id': 'a1'},
            ],
          },
    });
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Com comprovante'), findsOneWidget);
    await tester.tap(find.byTooltip('Desfazer pago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('DELETE /api/pagamentos/g2'), isNotNull);
    expect(amb.ultimo('DELETE /api/pagamentos/g1'), isNull);
  });

  testWidgets('Financeiro: por mês, média e gastos por categoria; tocar em Mês pede o intervalo', (tester) async {
    final amb = await abrirFinanceiro(tester);
    expect(find.text('Para onde foi o dinheiro'), findsOneWidget);
    expect(find.text('Filamento'), findsOneWidget);
    expect(find.text('R\$ 90,00 · 64,29%'), findsOneWidget, reason: '90 de 140 que saíram');
    expect(tester.widget<Text>(find.byKey(const Key('media_mes'))).data,
        'Média por mês: entrou R\$ 100,00 · saiu R\$ 93,33 · sobra R\$ 6,67');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Mês'));
    await tester.pumpAndSettle();
    final q = amb.ultimo('GET /api/extrato')!.url.queryParameters;
    final hoje = DateTime.now();
    expect(q['inicio'], '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-01');
    expect(DateTime.parse(q['fim']!).add(const Duration(days: 1)).day, 1); // último dia do mês
    expect(find.textContaining('Resultado · '), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ano'));
    await tester.pumpAndSettle();
    final a = amb.ultimo('GET /api/extrato')!.url.queryParameters;
    expect([a['inicio'], a['fim']], ['${hoje.year}-01-01', '${hoje.year}-12-31']);
    expect(find.text('Resultado · ${hoje.year}'), findsOneWidget);
  });

  testWidgets('Financeiro: aviso quando o extrato vem cortado', (tester) async {
    final amb = Ambiente({
      'GET /api/extrato': (_) => {...extrato, 'total_linhas': 530},
    });
    await amb.preparar();
    valoresOcultos.value = false;
    await tamanhoTela(tester, 360, 1600);
    await tester.pumpWidget(amb.tela(const FinanceiroTela()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mostrando os 4 mais recentes de 530'), findsOneWidget);
  });
}

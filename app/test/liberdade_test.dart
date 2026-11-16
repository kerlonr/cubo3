import 'package:cubo3/telas/estoque/insumo_form.dart';
import 'package:cubo3/telas/impressoes/confirmar_tela.dart';
import 'package:cubo3/telas/impressora/historico.dart';
import 'package:cubo3/telas/orcar/orcar_tela.dart';
import 'package:cubo3/telas/vendas/pedido_tela.dart';
import 'package:cubo3/telas/vendas/venda_rapida_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

Map<String, Object?> _pedido() => {
      'id': 'p1',
      'status': 'entregue',
      'pago': false,
      'atualizado_em': '2026-11-15T12:00:00+00:00',
      'entregue_em': '2026-11-15T15:00:00+00:00',
      'data': '2026-11-15T15:00:00+00:00',
      'receita': 20,
      'total': 20,
      'recebido': 25,
      'saldo': 0,
      'excedente': 5,
      'cliente_id': 'k1',
      'cliente': {'id': 'k1', 'nome': 'Ana', 'telefone': null},
      'pagamentos': [],
      'anexos': [],
      'avisos': [],
      'itens': [
        {'id': 'i1', 'modelo_id': null, 'descricao': 'Vaso', 'quantidade': 1, 'preco_unitario': 20},
      ],
    };

Future<Ambiente> _abrirPedido(WidgetTester tester) async {
  final amb = Ambiente({
    'GET /api/pedidos/p1': (_) => _pedido(),
    'GET /api/clientes': (_) => [
          {'id': 'k1', 'nome': 'Ana'},
          {'id': 'k2', 'nome': 'Bruno'},
        ],
  });
  await amb.preparar();
  await tamanhoTela(tester, 400, 1600);
  await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1')));
  await tester.pumpAndSettle();
  return amb;
}

void main() {
  testWidgets('impressão confirmada: tocar oferece reabrir, chama a rota e abre a confirmação', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 1200);
    await tester.pumpWidget(amb.tela(Scaffold(
      body: Builder(
        builder: (context) => HistoricoImpressoes(
          impressoes: const [
            {'id': 'i1', 'arquivo': 'vaso.gcode', 'status': 'confirmada', 'duracao_s': 60, 'estimativa': {}},
          ],
          abrir: (tela) => Navigator.push(context, MaterialPageRoute(builder: (_) => tela)),
        ),
      ),
    )));
    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('vaso.gcode'));
    await tester.pumpAndSettle();
    expect(find.text('Reabrir impressão?'), findsOneWidget);
    await tester.tap(find.text('Reabrir'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('POST /api/impressoes/i1/reabrir'), isNotNull);
    expect(find.byType(ConfirmarTela), findsOneWidget);
  });

  testWidgets('editar pedido: data da venda e cliente vão no PUT; troco aparece', (tester) async {
    final amb = await _abrirPedido(tester);
    expect(find.text('Recebeu R\$ 5,00 a mais'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar valores'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('data-venda')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bruno').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final corpo = amb.corpo('PUT /api/pedidos/p1');
    expect(corpo['cliente_id'], 'k2');
    expect(DateTime.parse(corpo['entregue_em'] as String).toLocal().day, 10);
    expect(corpo.containsKey('data'), isFalse, reason: 'entregue: a data da venda é a da entrega');
  });

  testWidgets('excluir pedido confirma e manda o DELETE', (tester) async {
    final amb = await _abrirPedido(tester);
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir pedido'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('DELETE /api/pedidos/p1'), isNull, reason: 'pede confirmação antes');
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('DELETE /api/pedidos/p1'), isNotNull);
  });

  testWidgets('orçar → criar pedido leva a peça com o preço escolhido', (tester) async {
    final amb = Ambiente({
      'GET /api/empresa/config': (_) =>
          {'eficiencia': 1.1, 'mao_obra_hora': 10, 'kwh': 0.656, 'reserva': 1.3, 'margens': [20, 30, 50]},
    });
    await amb.preparar();
    await tamanhoTela(tester, 360, 1600);
    await tester.pumpWidget(amb.tela(const OrcarTela()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gramas0')), '33');
    await tester.enterText(find.byKey(const Key('tempo0')), '3');
    await tester.pumpAndSettle();
    final preco = tester.widget<Text>(find.byKey(const Key('preco'))).data!;
    await tester.ensureVisible(find.byKey(const Key('criar_pedido')));
    await tester.tap(find.byKey(const Key('criar_pedido')));
    await tester.pumpAndSettle();
    final tela = tester.widget<VendaRapidaTela>(find.byType(VendaRapidaTela));
    expect(tela.orcamento, isTrue);
    expect(tela.itensIniciais, hasLength(1));
    expect(tela.itensIniciais!.single['descricao'], 'Peça 1');
    expect('R\$ ${(tela.itensIniciais!.single['preco_unitario'] as num).toStringAsFixed(2).replaceAll('.', ',')}', preco);
  });

  testWidgets('lixeira do insumo confirma e manda o DELETE', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 1200);
    await tester.pumpWidget(amb.tela(const InsumoForm(dados: {'id': 'x1', 'nome': 'Argola', 'custo_unitario': 0.3})));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('DELETE /api/insumos/x1'), isNotNull);
  });
}

import 'dart:convert';

import 'package:cubo3/telas/vendas/clientes_tela.dart';
import 'package:cubo3/telas/vendas/pedido_tela.dart';
import 'package:cubo3/telas/vendas/venda_rapida_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

final uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

Ambiente ambiente() => Ambiente({
      'GET /api/modelos': (_) => [
            {'id': 'm1', 'nome': 'Vaso', 'preco_venda': 30, 'excluido': false},
            {'id': 'm2', 'nome': 'Antigo', 'preco_venda': 10, 'excluido': true},
          ],
      'GET /api/canais': (_) => [
            {'id': 'c1', 'nome': 'Direto', 'taxa_pct': 0, 'taxa_fixa': 0},
            {'id': 'c2', 'nome': 'Shopee', 'taxa_pct': 20, 'taxa_fixa': 4},
          ],
      'GET /api/clientes': (_) => [],
    });

/// Responde ao PUT de pedido (o id é gerado no aparelho, então o caminho muda).
void responderPedido(Ambiente amb, List<String> avisos) {
  amb.rotasPrefixo['PUT /api/pedidos/'] = (r) => {...jsonDecode(r.body) as Map, 'avisos': avisos};
}

Future<void> vender(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('modelo0')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Vaso').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Registrar venda'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('venda rápida monta itens com UUID, status entregue e entregue_em em UTC', (tester) async {
    final amb = ambiente();
    responderPedido(amb, []);
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.tela(const VendaRapidaTela()));
    await tester.pumpAndSettle();
    await vender(tester);
    final put = amb.recebidos.lastWhere((r) => r.method == 'PUT' && r.url.path.startsWith('/api/pedidos/'));
    expect(uuidV4.hasMatch(put.url.pathSegments.last), isTrue);
    final corpo = jsonDecode(put.body) as Map;
    expect(corpo['status'], 'entregue');
    expect(corpo['entregue_em'], endsWith('Z'));
    expect(DateTime.parse(corpo['entregue_em'] as String).isUtc, isTrue);
    expect(corpo['canal_id'], 'c1');
    final item = (corpo['itens'] as List).single as Map;
    expect(uuidV4.hasMatch(item['id'] as String), isTrue);
    expect(item['modelo_id'], 'm1');
    expect(item['descricao'], 'Vaso');
    expect(item['quantidade'], 1);
    expect(item['preco_unitario'], 30);
  });

  testWidgets('seletor de modelo da venda não lista modelo excluído', (tester) async {
    final amb = ambiente();
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.tela(const VendaRapidaTela()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modelo0')));
    await tester.pumpAndSettle();
    expect(find.text('Vaso'), findsWidgets);
    expect(find.text('Antigo'), findsNothing);
  });

  testWidgets('avisos de estoque aparecem depois da venda', (tester) async {
    final amb = ambiente();
    responderPedido(amb, ['Estoque de Vaso ficou em -1']);
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.tela(const VendaRapidaTela()));
    await tester.pumpAndSettle();
    await vender(tester);
    expect(find.text('Estoque de Vaso ficou em -1'), findsOneWidget);
  });

  testWidgets('sem conexão a venda fica salva no aparelho', (tester) async {
    final amb = ambiente();
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.tela(const VendaRapidaTela()));
    await tester.pumpAndSettle();
    amb.online = false;
    await vender(tester);
    expect(find.textContaining('Salvo no aparelho'), findsOneWidget);
    expect(amb.fila.pendentes, 1);
  });

  testWidgets('pedido antigo com modelo excluído mostra o nome com "(excluído)"', (tester) async {
    final amb = Ambiente({
      'GET /api/pedidos/p1': (_) => {
            'id': 'p1',
            'status': 'entregue',
            'pago': true,
            'receita': 30,
            'lucro': 20,
            'bruto': 30,
            'cliente': null,
            'avisos': [],
            'itens': [
              {
                'id': 'i1',
                'modelo_id': 'm2',
                'descricao': 'Antigo',
                'quantidade': 1,
                'preco_unitario': 30,
                'modelo': {'id': 'm2', 'nome': 'Antigo', 'excluido': true},
              }
            ],
          },
    });
    await amb.preparar();
    await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1')));
    await tester.pumpAndSettle();
    expect(find.text('Antigo (excluído)'), findsOneWidget);
  });

  testWidgets('editar cliente manda a versão lida (X-Versao-Base); cliente novo não manda', (tester) async {
    final amb = ambiente();
    await amb.preparar();
    Future<void> abrir(ClienteForm form) async {
      await tester.pumpWidget(amb.tela(Builder(
          builder: (c) => TextButton(
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => form)), child: const Text('abrir')))));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    await abrir(const ClienteForm(dados: {'id': 'k1', 'nome': 'Ana', 'atualizado_em': '2026-11-03T12:30:00.123456+00:00'}));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('PUT /api/clientes/k1')!.headers['X-Versao-Base'], '2026-11-03T12:30:00.123456+00:00');

    await abrir(const ClienteForm());
    await tester.enterText(find.byType(TextField).first, 'Bia');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final novo = amb.recebidos.lastWhere((r) => r.method == 'PUT' && r.url.path.startsWith('/api/clientes/'));
    expect(novo.url.path, isNot('/api/clientes/k1'));
    expect(novo.headers.containsKey('X-Versao-Base'), isFalse);
  });

  testWidgets('marcar Entregue grava pelo PUT do pedido com entregue_em em UTC; os outros status seguem no /status',
      (tester) async {
    var status = 'pronto';
    final amb = Ambiente({
      'GET /api/pedidos/p1': (_) => {'id': 'p1', 'status': status, 'pago': true, 'itens': [], 'avisos': []},
    });
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Entregue'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('POST /api/pedidos/p1/status'), isNull);
    final corpo = amb.corpo('PUT /api/pedidos/p1');
    expect(corpo.keys, unorderedEquals(['status', 'entregue_em']));
    expect(corpo['status'], 'entregue');
    expect(corpo['entregue_em'], endsWith('Z'));
    expect(DateTime.parse(corpo['entregue_em'] as String).difference(DateTime.now()).inMinutes.abs(), lessThan(1));

    status = 'aprovado';
    await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1', key: Key('de novo'))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Produzindo'));
    await tester.pumpAndSettle();
    expect(amb.corpo('POST /api/pedidos/p1/status'), {'status': 'produzindo'});
  });
}

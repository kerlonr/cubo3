import 'dart:convert';

import 'package:cubo3/telas/vendas/pedido_tela.dart';
import 'package:cubo3/telas/vendas/pix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

const pixDono = {
  'configurado': true,
  'tipo': 'cpf',
  'nome': 'Kerlon',
  'cidade': 'Ijui',
  'chave_mascarada': '529•••25',
  'chave': '52998224725',
};

/// Servidor falso de um pedido de R$ 50 que recebe parcelas como o de verdade (saldo, recebido, pago automático).
class PedidoFalso {
  final pagamentos = <Map>[];
  double get recebido => pagamentos.fold(0.0, (s, p) => s + (p['valor'] as num));
  Map get json => {
        'id': 'p1',
        'status': 'entregue',
        'pago': recebido >= 50,
        'receita': 50,
        'total': 50,
        'recebido': recebido,
        'saldo': 50 - recebido,
        'pagamentos': pagamentos,
        'cliente': {'id': 'k1', 'nome': 'Ana Souza', 'telefone': null},
        'itens': [
          {'id': 'i1', 'modelo_id': 'm1', 'descricao': 'Vaso', 'quantidade': 1, 'preco_unitario': 50},
        ],
        'anexos': [],
        'avisos': [],
      };
}

Future<Ambiente> abrirPedido(WidgetTester tester, PedidoFalso p, {Map<String, Object? Function(dynamic)> rotas = const {}}) async {
  final amb = Ambiente({'GET /api/pedidos/p1': (_) => p.json, ...rotas});
  amb.rotasPrefixo['PUT /api/pedidos/p1/pagamentos/'] = (r) {
    p.pagamentos.add({'id': r.url.pathSegments.last, ...jsonDecode(r.body) as Map});
    return p.json;
  };
  await amb.preparar();
  await tamanhoTela(tester, 400, 1600);
  await tester.pumpWidget(amb.tela(const PedidoTela(id: 'p1')));
  await tester.pumpAndSettle();
  return amb;
}

void main() {
  testWidgets('Pix do dono: chave mascarada, olho revela; membro só vê que existe', (tester) async {
    final amb = Ambiente({'GET /api/empresa/pix': (_) => pixDono});
    await amb.preparar();
    await tester.pumpWidget(amb.tela(const Scaffold(body: SecaoPix())));
    await tester.pumpAndSettle();
    expect(find.text('529•••25'), findsOneWidget);
    expect(find.text('52998224725'), findsNothing);
    await tester.tap(find.byTooltip('Mostrar chave'));
    await tester.pump();
    expect(find.text('52998224725'), findsOneWidget);
    expect(find.byTooltip('Editar Pix'), findsOneWidget);

    final membro = Ambiente({'GET /api/empresa/pix': (_) => {...pixDono}..remove('chave')});
    await membro.preparar(papel: 'membro');
    await tester.pumpWidget(membro.tela(const Scaffold(body: SecaoPix(key: ValueKey('m')))));
    await tester.pumpAndSettle();
    expect(find.text('Pix configurado: 529•••25 (Kerlon)'), findsOneWidget);
    expect(find.byTooltip('Mostrar chave'), findsNothing);
    expect(find.byTooltip('Editar Pix'), findsNothing);
  });

  testWidgets('cadastrar Pix: PUT direto e o motivo da recusa aparece na folha', (tester) async {
    var recusa = true;
    final amb = Ambiente({
      'GET /api/empresa/pix': (_) => {'configurado': false},
      'PUT /api/empresa/pix': (_) => recusa ? json({'detail': 'CPF inválido'}, 422) : pixDono,
    });
    await amb.preparar();
    await tester.pumpWidget(amb.tela(const Scaffold(body: SecaoPix())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();
    final campos = find.byType(TextField); // chave, nome, cidade
    await tester.enterText(campos.at(0), '529.982.247-25');
    await tester.enterText(campos.at(1), 'Kerlon');
    await tester.enterText(campos.at(2), 'Ijui');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('CPF inválido'), findsOneWidget);
    expect(amb.corpo('PUT /api/empresa/pix'), {'tipo': 'cpf', 'chave': '529.982.247-25', 'nome': 'Kerlon', 'cidade': 'Ijui'});
    recusa = false;
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('529•••25'), findsOneWidget);
    // Nada do Pix vai para a fila nem para o cache do aparelho.
    expect(amb.fila.pendentes, 0);
  });

  testWidgets('cobrar no Pix mostra o copia e cola e copia', (tester) async {
    String? copiado;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copiado = (c.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final amb = await abrirPedido(tester, PedidoFalso(), rotas: {
      'POST /api/pix/cobranca': (_) => {'valor': 50, 'copia_e_cola': '000201PIXDOPEDIDO', 'recebedor': 'Kerlon'},
    });
    await tester.tap(find.byTooltip('Cobrar no Pix'));
    await tester.pumpAndSettle();
    expect(amb.corpo('POST /api/pix/cobranca'), {'pedido_id': 'p1'});
    expect(find.text('000201PIXDOPEDIDO'), findsOneWidget);
    await tester.tap(find.text('Copiar'));
    await tester.pumpAndSettle();
    expect(copiado, '000201PIXDOPEDIDO');
    expect(find.text('Copiado'), findsOneWidget);
    expect(find.text('Enviar'), findsOneWidget, reason: 'cliente sem telefone: compartilhar');
  });

  testWidgets('cobrar sem Pix cadastrado oferece cadastrar (dono)', (tester) async {
    await abrirPedido(tester, PedidoFalso(), rotas: {
      'POST /api/pix/cobranca': (_) => json({'detail': 'Cadastre o seu Pix em Empresa → Pix'}, 409),
    });
    await tester.tap(find.byTooltip('Cobrar no Pix'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastre o seu Pix'), findsOneWidget);
    expect(find.text('Cadastrar'), findsOneWidget);
  });

  testWidgets('receber parte vira Parcial; receber o resto (padrão = saldo) vira Pago', (tester) async {
    final p = PedidoFalso();
    final amb = await abrirPedido(tester, p);
    expect(find.text('A receber'), findsOneWidget);
    await tester.tap(find.text('Receber'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('valor-pagamento')), matching: find.byType(TextField)), '2000');
    await tester.pump();
    await tester.tap(find.text('Receber R\$ 20,00'));
    await tester.pumpAndSettle();
    final corpo = jsonDecode(amb.recebidos.lastWhere((r) => r.method == 'PUT').body) as Map;
    expect(corpo['valor'], 20);
    expect(corpo['forma'], 'Pix');
    expect(corpo['data'], isNotNull);
    expect(find.text('Parcial'), findsOneWidget);
    expect(find.text('Recebido R\$ 20,00 de R\$ 50,00'), findsOneWidget);

    await tester.tap(find.text('Receber'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receber R\$ 30,00'));
    await tester.pumpAndSettle();
    expect(find.text('Pago'), findsOneWidget);
    expect(find.text('Receber'), findsNothing);
    expect(p.pagamentos.map((x) => x['id']).toSet().length, 2, reason: 'cada parcela com o seu id');
  });
}

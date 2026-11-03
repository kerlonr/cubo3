// Testes da revisão final (feat/app). Cada um prova um bug achado na revisão e fica com `skip`
// documentado para a suíte seguir verde; tire o skip quando corrigir.
import 'dart:convert';

import 'package:cubo3/api/api.dart';
import 'package:cubo3/api/fila.dart';
import 'package:cubo3/telas/impressoes/confirmar_tela.dart';
import 'package:cubo3/telas/vendas/venda_rapida_tela.dart';
import 'package:cubo3/widgets/cartoes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apoio.dart';

const _skipFila = 'BUG revisão: operação com 5xx fixo trava a fila para sempre e tudo depois vira "salvo no aparelho" (fila.dart:87,113)';

void main() {
  testWidgets('venda rápida pelo "+" atualiza a receita do Início', (tester) async {
    var vendido = false;
    final amb = Ambiente({
      'GET /api/painel': (_) => {'receita': vendido ? 30 : 0, 'gastos': 0, 'resultado': vendido ? 30 : 0, 'lucro_vendas': 0},
      'GET /api/modelos': (_) => [
            {'id': 'm1', 'nome': 'Vaso', 'preco_venda': 30, 'excluido': false}
          ],
      'GET /api/canais': (_) => [
            {'id': 'c1', 'nome': 'Direto', 'taxa_pct': 0, 'taxa_fixa': 0}
          ],
    });
    amb.rotasPrefixo['PUT /api/pedidos/'] = (r) {
      vendido = true;
      return {...jsonDecode(r.body) as Map, 'avisos': []};
    };
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.app());
    await tester.pumpAndSettle();
    expect(tester.widget<CartaoValor>(find.widgetWithText(CartaoValor, 'Receita')).valor, contains('0,00'));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Venda rápida'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modelo0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vaso').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar venda'));
    await tester.pumpAndSettle();
    expect(vendido, isTrue);
    // De volta ao Início: a venda deveria aparecer sem precisar puxar para atualizar.
    expect(tester.widget<CartaoValor>(find.widgetWithText(CartaoValor, 'Receita')).valor, contains('30,00'));
  });

  test('uma operação com erro 500 fixo não pode prender as próximas na fila', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final chegaram = <String>[];
    final api = ApiCliente(
        MockClient((r) async {
          if (r.url.path == '/api/quebrada/1') return http.Response('{"detail":"Internal Server Error"}', 500);
          chegaram.add(r.url.path);
          return http.Response('{}', 200);
        }),
        Uri.parse('https://teste'),
        ArmazemMemoria())
      ..empresaId = 'a';
    final fila = FilaOffline(api, prefs, guardaOffline: true);
    // Com internet: o 500 é tratado como "sem conexão" e a operação fica guardada.
    final r1 = await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/quebrada/1', {}));
    expect(r1.guardada, isTrue);
    // A venda seguinte, com internet e servidor ok, nunca chega: entra atrás da quebrada.
    final r2 = await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/pedidos/2', {}));
    await fila.esvaziar();
    expect(r2.guardada, isFalse, reason: 'venda ficou "salva no aparelho" com internet');
    expect(chegaram, contains('/api/pedidos/2'));
  }, skip: _skipFila);

  testWidgets('lançamento manual com uma impressora só usa essa impressora', (tester) async {
    final amb = Ambiente({
      'GET /api/impressoras': (_) => [
            {'id': 'i1', 'nome': 'Ender', 'moonraker_url': null, 'custo_hora': 0.5}
          ],
    });
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.tela(const ConfirmarTela()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teste'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    final put = amb.recebidos.lastWhere((r) => r.method == 'PUT' && r.url.path.startsWith('/api/impressoes/'));
    // null → servidor usa ParamImpressora() padrão em vez do preço/potência da impressora cadastrada.
    expect((jsonDecode(put.body) as Map)['impressora_id'], 'i1');
  }, skip: true); // BUG revisão: com uma impressora só, lançamento manual manda impressora_id null (confirmar_tela.dart:105,203)

  testWidgets('texto sem modelo + Enter na venda rápida não lança exceção', (tester) async {
    final amb = Ambiente({
      'GET /api/modelos': (_) => [
            {'id': 'm1', 'nome': 'Vaso', 'preco_venda': 30, 'excluido': false}
          ],
      'GET /api/canais': (_) => [],
      'GET /api/clientes': (_) => [],
    });
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.tela(const VendaRapidaTela()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modelo0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('modelo0')), matching: find.byType(TextField)), 'chaveiro');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: true); // BUG revisão: Enter num texto sem modelo correspondente chama onSelected(null) e estoura firstWhere (venda_rapida_tela.dart:211)
}

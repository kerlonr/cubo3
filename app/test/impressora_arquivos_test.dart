import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'apoio.dart';
import 'impressora_v2_test.dart' show abrirSecao, comandos, habilitado, irPara;

Ambiente ambiente({Object? Function(http.Request)? imprimir}) => Ambiente({
      'GET /api/impressoras': (_) => [
            {'id': 'i1', 'nome': 'Ender', 'moonraker_url': 'http://192.168.1.110:7125'}
          ],
      'GET /api/impressoes': (_) => [],
      'GET /api/impressoras/i1/ao-vivo': (_) => {'estado': 'standby', 'bico': 25},
      'POST /api/impressoras/i1/camera/link': (_) => json({'detail': 'Sem câmera'}, 404),
      'GET /api/impressoras/i1/arquivos': (_) => [
            {
              'nome': 'vaso.gcode',
              'tamanho': 123456,
              'modificado': '2026-11-03T12:00:00+00:00',
              'tempo_estimado_s': 11100,
              'gramas': 33.2,
              'miniatura': '.thumbs/vaso-300x300.png',
            },
            {'nome': 'chaveiro.gcode', 'tamanho': 100, 'modificado': null, 'tempo_estimado_s': null, 'gramas': null, 'miniatura': null},
          ],
      'GET /api/impressoras/i1/macros': (_) => [
            {'nome': 'PAUSE'},
            {'nome': 'AUTO_Z_OFFSET'},
          ],
      'GET /api/impressoras/i1/console': (_) => {
            'linhas': [
              {'hora': '2026-11-03T12:00:00+00:00', 'texto': '// Klipper pronto'}
            ]
          },
      'POST /api/impressoras/i1/arquivos/imprimir': ?imprimir,
    });

void main() {
  testWidgets('arquivos mostram tempo e peso; busca filtra pelo nome', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Arquivos');
    expect(find.text('vaso.gcode'), findsOneWidget);
    expect(find.textContaining('3h05 · 33,2 g'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Buscar arquivo'), 'chav');
    await tester.pumpAndSettle();
    expect(find.text('vaso.gcode'), findsNothing);
    expect(find.text('chaveiro.gcode'), findsOneWidget);
  });

  testWidgets('imprimir arquivo da impressora confirma, manda {nome} e desabilita no voo', (tester) async {
    final resposta = Completer<Object?>();
    final amb = ambiente(imprimir: (_) => resposta.future);
    await abrirSecao(tester, amb, 'Arquivos');
    await tester.tap(find.text('vaso.gcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprimir'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('POST /api/impressoras/i1/arquivos/imprimir'), isNull, reason: 'pede confirmação antes');
    await tester.tap(find.text('Imprimir agora'));
    await tester.pump();
    expect(habilitado(tester, 'Imprimir'), isFalse);
    await tester.tap(find.text('Imprimir'), warnIfMissed: false);
    await tester.pump();
    resposta.complete({'ok': true});
    await tester.pumpAndSettle();
    final pedidos = amb.recebidos.where((r) => r.url.path == '/api/impressoras/i1/arquivos/imprimir').toList();
    expect(pedidos, hasLength(1));
    expect(jsonDecode(pedidos.single.body), {'nome': 'vaso.gcode'});
    expect(find.text('Impressão iniciada'), findsOneWidget);
  });

  testWidgets('impressora ocupada (409) mostra "A impressora está ocupada"', (tester) async {
    final amb = ambiente(imprimir: (_) => json({'detail': 'A impressora está ocupada'}, 409));
    await abrirSecao(tester, amb, 'Arquivos');
    await tester.tap(find.text('vaso.gcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprimir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprimir agora'));
    await tester.pumpAndSettle();
    expect(find.text('A impressora está ocupada'), findsOneWidget);
  });

  testWidgets('macro roda com confirmação e manda {acao: macro, nome}', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Macros');
    await tester.tap(find.text('Rodar').first);
    await tester.pumpAndSettle();
    expect(comandos(amb), isEmpty);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Rodar')));
    await tester.pumpAndSettle();
    expect(comandos(amb).single, {'acao': 'macro', 'nome': 'PAUSE'});
  });

  testWidgets('console mostra o histórico, recebe linha ao vivo e manda G-code; o enviado vira atalho', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Console');
    amb.canal.iniciar();
    await tester.pump();
    expect(find.textContaining('// Klipper pronto', findRichText: true), findsOneWidget);
    amb.aoVivo.add(jsonEncode(
        {'tipo': 'console', 'impressora_id': 'i1', 'hora': '2026-11-03T12:01:00+00:00', 'texto': 'ok T:210.0 /210.0'}));
    amb.aoVivo.add(jsonEncode(
        {'tipo': 'console', 'impressora_id': 'outra', 'hora': '2026-11-03T12:01:00+00:00', 'texto': 'de outra'}));
    await tester.pumpAndSettle();
    expect(find.textContaining('ok T:210.0', findRichText: true), findsOneWidget);
    expect(find.textContaining('de outra', findRichText: true), findsNothing);

    await tester.enterText(find.byKey(const Key('gcode')), 'G28');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(amb.corpo('POST /api/impressoras/i1/gcode'), {'script': 'G28'});
    expect(find.widgetWithText(ActionChip, 'G28'), findsOneWidget);
    amb.canal.parar();
  });

  testWidgets('membro não vê o campo de G-code nem o botão de macro', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Console', papel: 'membro');
    expect(find.textContaining('// Klipper pronto', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('gcode')), findsNothing);
    await irPara(tester, 'Macros');
    expect(find.text('PAUSE'), findsOneWidget);
    expect(find.text('Rodar'), findsNothing);
    await irPara(tester, 'Arquivos');
    await tester.tap(find.text('vaso.gcode'));
    await tester.pumpAndSettle();
    expect(find.text('Imprimir'), findsNothing);
  });
}

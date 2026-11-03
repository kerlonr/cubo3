import 'dart:async';
import 'dart:convert';

import 'package:cubo3/telas/impressora/impressora_aba.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'apoio.dart';

const impressora = {'id': 'i1', 'nome': 'Ender', 'moonraker_url': 'http://192.168.1.110:7125'};

Ambiente ambiente({Object? Function(http.Request)? comando, num bico = 215}) => Ambiente({
      'GET /api/impressoras': (_) => [impressora],
      'GET /api/impressoes': (_) => [],
      'GET /api/impressoras/i1/ao-vivo': (_) => {
            'estado': 'standby',
            'bico': bico,
            'posicao': [10, 20, 5],
            'eixos_home': 'xy',
            'velocidade_pct': 100,
            'fluxo_pct': 100,
            'ventoinha_pct': 0,
            'z_offset': -0.05,
          },
      'POST /api/impressoras/i1/camera/link': (_) => json({'detail': 'Sem câmera'}, 404),
      'POST /api/impressoras/i1/comando': ?comando,
    });

/// Abre a aba Impressora e vai para a seção [secao].
Future<void> abrirSecao(WidgetTester tester, Ambiente amb, String secao, {String papel = 'dono'}) async {
  await amb.preparar(papel: papel);
  await tamanhoTela(tester, 420, 2400);
  await tester.pumpWidget(amb.tela(const ImpressoraAba()));
  await tester.pumpAndSettle();
  await irPara(tester, secao);
}

/// Toca numa seção (a barra rola: em tela estreita as últimas ficam escondidas à direita).
Future<void> irPara(WidgetTester tester, String secao) async {
  await tester.ensureVisible(find.text(secao));
  await tester.pumpAndSettle();
  await tester.tap(find.text(secao));
  await tester.pumpAndSettle();
}

List<Map> comandos(Ambiente amb) => [
      for (final r in amb.recebidos)
        if (r.url.path == '/api/impressoras/i1/comando') jsonDecode(r.body) as Map
    ];

bool habilitado(WidgetTester tester, String texto) => tester
    .widget<ButtonStyleButton>(find.ancestor(of: find.text(texto), matching: find.bySubtype<ButtonStyleButton>()))
    .enabled;

void main() {
  testWidgets('mover 10 mm em X manda {acao: mover, eixo: X, distancia: 10}', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Controle');
    await tester.tap(find.byTooltip('X+'));
    await tester.pumpAndSettle();
    expect(comandos(amb).single, {'acao': 'mover', 'eixo': 'X', 'distancia': 10});
    await tester.tap(find.text('0,1'));
    await tester.pump();
    await tester.tap(find.byTooltip('Z−'));
    await tester.pumpAndSettle();
    expect(comandos(amb).last, {'acao': 'mover', 'eixo': 'Z', 'distancia': -0.1});
  });

  testWidgets('toque duplo enquanto o comando está no ar manda uma vez só', (tester) async {
    final resposta = Completer<Object?>();
    final amb = ambiente(comando: (_) => resposta.future);
    await abrirSecao(tester, amb, 'Controle');
    await tester.tap(find.text('Home tudo'));
    await tester.pump();
    expect(habilitado(tester, 'Home tudo'), isFalse);
    await tester.tap(find.text('Home tudo'), warnIfMissed: false);
    await tester.tap(find.byTooltip('X+'), warnIfMissed: false);
    await tester.pump();
    resposta.complete({'ok': true});
    await tester.pumpAndSettle();
    expect(comandos(amb), [
      {'acao': 'home', 'eixos': 'XYZ'}
    ]);
    expect(habilitado(tester, 'Home tudo'), isTrue);
  });

  testWidgets('extrudar fica desabilitado com o bico a 25 °C', (tester) async {
    final amb = ambiente(bico: 25);
    await abrirSecao(tester, amb, 'Controle');
    expect(habilitado(tester, 'Extrudar'), isFalse);
    expect(habilitado(tester, 'Retrair'), isFalse);
    expect(find.textContaining('agora 25 °C'), findsOneWidget);
  });

  testWidgets('eixo sem home aparece como "sem home" e há aviso', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Controle');
    expect(find.text('sem home'), findsOneWidget, reason: 'Z ainda não fez home');
    expect(find.textContaining('Faça Home antes de mover'), findsOneWidget);
  });

  testWidgets('membro não vê a seção Controle nem a parada de emergência', (tester) async {
    final amb = ambiente();
    await amb.preparar(papel: 'membro');
    await tamanhoTela(tester, 420, 2400);
    await tester.pumpWidget(amb.tela(const ImpressoraAba()));
    await tester.pumpAndSettle();
    expect(find.text('Painel'), findsOneWidget);
    expect(find.text('Controle'), findsNothing);
    expect(find.byTooltip('Parada de emergência'), findsNothing);
  });

  testWidgets('Klipper recusa por falta de home: mostra a mensagem e oferece Home', (tester) async {
    const recusa = 'Klipper: Must home axis first: 10.000 20.000 5.000 [0.000]';
    var primeira = true;
    final amb = ambiente(comando: (_) {
      if (!primeira) return {'ok': true};
      primeira = false;
      return json({'detail': recusa}, 400);
    });
    await abrirSecao(tester, amb, 'Controle');
    await tester.tap(find.byTooltip('Y+'));
    await tester.pumpAndSettle();
    expect(find.text(recusa), findsOneWidget);
    await tester.tap(find.text('Fazer Home'));
    await tester.pumpAndSettle();
    expect(comandos(amb).last, {'acao': 'home', 'eixos': 'XYZ'});
  });

  testWidgets('ventoinha envia ao soltar o controle deslizante', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Controle');
    final slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(comandos(amb).single, {'acao': 'ventoinha', 'valor': 100});
  });
}

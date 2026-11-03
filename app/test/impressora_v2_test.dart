import 'dart:async';
import 'dart:convert';

import 'package:cubo3/telas/impressora/impressora_aba.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'apoio.dart';

const impressora = {'id': 'i1', 'nome': 'Ender', 'moonraker_url': 'http://192.168.1.110:7125'};

Ambiente ambiente({Object? Function(http.Request)? comando, num bico = 215, String estado = 'standby'}) => Ambiente({
      'GET /api/impressoras': (_) => [impressora],
      'GET /api/impressoes': (_) => [],
      'GET /api/impressoras/i1/ao-vivo': (_) => {
            'estado': estado,
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

/// Como [abrirSecao], para impressão em andamento: o Painel anima o progresso e pumpAndSettle não termina.
Future<void> abrirSecaoAnimada(WidgetTester tester, Ambiente amb, String secao) async {
  await amb.preparar();
  await tamanhoTela(tester, 420, 2400);
  await tester.pumpWidget(amb.tela(const ImpressoraAba()));
  await passar(tester);
  await tester.tap(find.text(secao));
  await passar(tester);
}

Future<void> passar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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
    await abrirSecao(tester, amb, 'Painel');
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
    await abrirSecao(tester, amb, 'Painel');
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
    await abrirSecao(tester, amb, 'Painel');
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
    expect(find.text('Arquivos'), findsOneWidget);
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
    await abrirSecao(tester, amb, 'Painel');
    await tester.tap(find.byTooltip('Y+'));
    await tester.pumpAndSettle();
    expect(find.text(recusa), findsOneWidget);
    await tester.tap(find.text('Fazer Home'));
    await tester.pumpAndSettle();
    expect(comandos(amb).last, {'acao': 'home', 'eixos': 'XYZ'});
  });

  testWidgets('pausada: Home e Desligar motores bloqueados; mover e extrudar liberados (troca de filamento)',
      (tester) async {
    final amb = ambiente(estado: 'paused');
    await abrirSecaoAnimada(tester, amb, 'Painel');
    for (final b in ['Home tudo', 'Home XY', 'Home Z']) {
      expect(habilitado(tester, b), isFalse, reason: b);
    }
    expect(find.textContaining('perdem a posição da peça'), findsOneWidget);
    await tester.tap(find.byTooltip('X+'));
    await passar(tester);
    expect(comandos(amb), [
      {'acao': 'mover', 'eixo': 'X', 'distancia': 10}
    ]);
    await tester.tap(find.text('Controle'));
    await passar(tester);
    expect(habilitado(tester, 'Desligar motores'), isFalse);
    expect(habilitado(tester, 'Extrudar'), isTrue);
  });

  testWidgets('imprimindo: aviso para pausar; ajuste fino de Z, ventoinha e temperaturas seguem', (tester) async {
    final amb = ambiente(estado: 'printing');
    await abrirSecaoAnimada(tester, amb, 'Painel');
    expect(find.text('Pause a impressão para mover os eixos'), findsOneWidget);
    for (final b in ['Home XY', 'Home Z']) {
      expect(habilitado(tester, b), isFalse, reason: b);
    }
    expect(habilitado(tester, 'Aplicar'), isTrue, reason: 'temperaturas seguem');
    await tester.tap(find.text('Controle'));
    await passar(tester);
    expect(find.text('Pause a impressão para mover os eixos'), findsOneWidget);
    expect(habilitado(tester, 'Retrair'), isFalse);
    expect(habilitado(tester, '+0,01'), isTrue);
    expect(habilitado(tester, 'Reiniciar firmware'), isTrue);
  });

  testWidgets('409 do servidor (estado ainda não chegou) mostra a mensagem dele, sem oferecer Home', (tester) async {
    const recusa = 'Com a impressão pausada, home e desligar motores perdem a posição da peça';
    final amb = ambiente(comando: (_) => json({'detail': recusa}, 409));
    await abrirSecao(tester, amb, 'Painel');
    await tester.tap(find.text('Home tudo'));
    await tester.pumpAndSettle();
    expect(find.text(recusa), findsOneWidget);
    expect(find.text('Fazer Home'), findsNothing);
  });

  testWidgets('Painel do dono: câmera, estado, temperaturas e mover, nessa ordem; Controle fica com o resto',
      (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Painel');
    double y(Finder f) => tester.getTopLeft(f.first).dy;
    final ordem = [
      find.text('Sem câmera'),
      find.text('Temperaturas'),
      find.text('Home tudo'),
      find.byTooltip('X+'),
    ];
    for (var i = 1; i < ordem.length; i++) {
      expect(y(ordem[i - 1]), lessThan(y(ordem[i])), reason: '${ordem[i - 1]} antes de ${ordem[i]}');
    }
    for (final t in ['0,1', '1', '10', '100']) {
      expect(find.text(t), findsWidgets, reason: 'passo $t');
    }
    await irPara(tester, 'Controle');
    expect(find.text('Home tudo'), findsNothing);
    expect(find.byTooltip('X+'), findsNothing);
    for (final t in ['Desligar motores', 'Extrudar', 'Ajuste fino de Z', 'Reiniciar firmware']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('mover pelo Painel não reabre o vídeo', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Painel');
    for (final t in ['X+', 'Y−', 'Z+']) {
      await tester.tap(find.byTooltip(t));
      await tester.pumpAndSettle();
    }
    expect(comandos(amb), hasLength(3));
    expect(amb.recebidos.where((r) => r.url.path == '/api/impressoras/i1/camera/link'), hasLength(1));
    expect(find.text('Sem câmera'), findsOneWidget);
  });

  testWidgets('em 1280 dp: câmera à esquerda, temperaturas e mover à direita, sem rolar', (tester) async {
    final amb = ambiente();
    await amb.preparar();
    await tamanhoTela(tester, 1280, 720);
    await tester.pumpWidget(amb.tela(const ImpressoraAba()));
    await tester.pumpAndSettle();
    final camera = tester.getRect(find.text('Sem câmera'));
    for (final f in [find.text('Temperaturas'), find.text('Home tudo'), find.byTooltip('X+'), find.byTooltip('Z−')]) {
      final r = tester.getRect(f);
      expect(r.left, greaterThan(camera.right), reason: '$f à direita da câmera');
      expect(r.bottom, lessThan(720), reason: '$f visível sem rolar');
    }
  });

  testWidgets('membro: Painel sem mover nem temperaturas', (tester) async {
    final amb = ambiente();
    await abrirSecao(tester, amb, 'Painel', papel: 'membro');
    expect(find.text('Sem câmera'), findsOneWidget);
    expect(find.text('Home tudo'), findsNothing);
    expect(find.byTooltip('X+'), findsNothing);
    expect(find.text('PETG'), findsNothing);
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

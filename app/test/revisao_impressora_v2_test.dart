// Revisão final feat/v2 (79c77a8..6dbbf7a).
// 1) Testes que faltavam nas Tasks A4/A5 (mutações que sobreviviam): passam hoje.
// 2) Provas dos bugs achados na revisão (corrigidos no 2.0.1).
import 'dart:async';

import 'package:cubo3/telas/impressora/impressora_aba.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';
import 'controle_test.dart' show abrir, abrirModelo, catalogo;
import 'impressora_v2_test.dart' show abrirSecao, comandos, habilitado;

const _impressora = {'id': 'i1', 'nome': 'Ender', 'moonraker_url': 'http://192.168.1.110:7125'};

Ambiente _ambiente({String estado = 'standby', num bico = 215}) => Ambiente({
      'GET /api/impressoras': (_) => [_impressora],
      'GET /api/impressoes': (_) => [],
      'GET /api/impressoras/i1/ao-vivo': (_) => {
            'estado': estado,
            'bico': bico,
            'posicao': [10, 20, 5],
            'eixos_home': 'xyz',
            'velocidade_pct': 100,
            'fluxo_pct': 100,
            'ventoinha_pct': 0,
            'z_offset': 0,
          },
      'POST /api/impressoras/i1/camera/link': (_) => json({'detail': 'Sem câmera'}, 404),
    });

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('Controle manda exatamente o contrato', () {
    testWidgets('Retrair manda distância negativa; Extrudar positiva', (tester) async {
      final amb = _ambiente();
      await abrirSecao(tester, amb, 'Controle');
      await _tocar(tester, find.text('Retrair'));
      await _tocar(tester, find.text('Extrudar'));
      expect(comandos(amb), [
        {'acao': 'extrudar', 'distancia': -10},
        {'acao': 'extrudar', 'distancia': 10},
      ]);
    });

    testWidgets('Home XY e Home Z mandam os eixos certos', (tester) async {
      final amb = _ambiente();
      await abrirSecao(tester, amb, 'Controle');
      await _tocar(tester, find.text('Home XY'));
      await _tocar(tester, find.text('Home Z'));
      expect(comandos(amb), [
        {'acao': 'home', 'eixos': 'XY'},
        {'acao': 'home', 'eixos': 'Z'},
      ]);
    });

    testWidgets('setas Y+, Y−, X− e Z+ mandam eixo e sinal certos', (tester) async {
      final amb = _ambiente();
      await abrirSecao(tester, amb, 'Controle');
      for (final t in ['Y+', 'Y−', 'X−', 'Z+']) {
        await _tocar(tester, find.byTooltip(t));
      }
      expect(comandos(amb), [
        {'acao': 'mover', 'eixo': 'Y', 'distancia': 10},
        {'acao': 'mover', 'eixo': 'Y', 'distancia': -10},
        {'acao': 'mover', 'eixo': 'X', 'distancia': -10},
        {'acao': 'mover', 'eixo': 'Z', 'distancia': 10},
      ]);
    });

    testWidgets('ajuste fino de Z manda o sinal do botão', (tester) async {
      final amb = _ambiente();
      await abrirSecao(tester, amb, 'Controle');
      await _tocar(tester, find.text('+0,01'));
      await _tocar(tester, find.text('−0,05'));
      expect(comandos(amb), [
        {'acao': 'ajuste_z', 'valor': 0.01},
        {'acao': 'ajuste_z', 'valor': -0.05},
      ]);
    });

    testWidgets('sliders de velocidade e fluxo mandam a própria ação', (tester) async {
      final amb = _ambiente();
      await abrirSecao(tester, amb, 'Controle');
      final sliders = find.byType(Slider);
      await tester.ensureVisible(sliders.at(2));
      await tester.pumpAndSettle();
      await tester.drag(sliders.at(1), const Offset(-2000, 0));
      await tester.pumpAndSettle();
      await tester.drag(sliders.at(2), const Offset(2000, 0));
      await tester.pumpAndSettle();
      expect(comandos(amb), [
        {'acao': 'velocidade', 'valor': 10},
        {'acao': 'fluxo', 'valor': 150},
      ]);
    });

    testWidgets('Desligar motores manda motores_off', (tester) async {
      final amb = _ambiente();
      await abrirSecao(tester, amb, 'Controle');
      await _tocar(tester, find.text('Desligar motores'));
      expect(comandos(amb), [
        {'acao': 'motores_off'}
      ]);
    });

    testWidgets('Reiniciar firmware pede confirmação antes', (tester) async {
      final amb = _ambiente();
      await abrirSecao(tester, amb, 'Controle');
      await _tocar(tester, find.text('Reiniciar firmware'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(comandos(amb), isEmpty);
      await _tocar(tester, find.text('Reiniciar'));
      expect(comandos(amb), [
        {'acao': 'reiniciar_firmware'}
      ]);
    });

    testWidgets('sem internet o comando falha na hora e nada fica na fila', (tester) async {
      final amb = _ambiente();
      await abrirSecao(tester, amb, 'Controle');
      amb.online = false;
      await _tocar(tester, find.text('Home tudo'));
      expect(amb.fila.pendentes, 0);
      amb.online = true;
      await tester.pumpAndSettle();
      expect(comandos(amb), isEmpty);
    });
  });

  group('bugs da revisão', () {
    testWidgets('imprimindo: Home, mover, desligar motores e extrudar ficam bloqueados', (tester) async {
      final amb = _ambiente(estado: 'printing');
      // O Painel anima a barra de progresso imprimindo: pump com tempo em vez de pumpAndSettle.
      await amb.preparar();
      await tamanhoTela(tester, 420, 2400);
      await tester.pumpWidget(amb.tela(const ImpressoraAba()));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Controle'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Home tudo'), findsOneWidget);
      final bloqueados = {
        'Home tudo': 'G28 no meio da peça arrasta o bico nela',
        'Desligar motores': 'M84 no meio da peça perde a posição',
        'Extrudar': 'M83 no meio de peça em extrusão absoluta (Cura) a estraga',
      };
      final liberados = [for (final b in bloqueados.keys) if (habilitado(tester, b)) b];
      await tester.tap(find.byTooltip('X+'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));
      // Duas verificações: record com listas compara por identidade e nunca seria igual.
      expect(liberados, isEmpty, reason: bloqueados.values.join('; '));
      expect(comandos(amb), isEmpty, reason: 'seta X+ imprimindo');
    });

    testWidgets('imprimindo: atalho "Desligar" das temperaturas pede confirmação', (tester) async {
      final amb = Ambiente({
        'GET /api/impressoras/i1/ao-vivo': (_) => {'estado': 'printing', 'arquivo': 'vaso.gcode', 'progresso': 0.4},
      });
      await abrir(tester, amb);
      await tester.tap(find.text('Desligar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'um toque desliga bico e mesa e perde a peça');
      expect(comandos(amb), isEmpty);
    });

    testWidgets('imprimir do catálogo: segundo toque enquanto envia não manda de novo', (tester) async {
      final resposta = Completer<Object?>();
      final amb = catalogo(imprimir: (_) => resposta.future);
      await abrirModelo(tester, amb);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Imprimir na Ender'), warnIfMissed: false);
        await tester.pumpAndSettle();
        if (find.text('Imprimir').evaluate().isNotEmpty) {
          await tester.tap(find.text('Imprimir'));
          await tester.pump();
        }
      }
      resposta.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(amb.recebidos.where((r) => r.url.path == '/api/arquivos/a1/imprimir'), hasLength(1));
    });
    testWidgets('parada de emergência continua tocável com outro comando no ar', (tester) async {
      // Painel/ImpressoraTela: `pode = !_semConexao && !_enviando` também desliga a emergência. Um CANCEL_PRINT
      // demorado (ou um tempo esgotado, que marca "sem conexão") deixa o botão vermelho morto.
      final resposta = Completer<Object?>();
      final amb = Ambiente({
        'GET /api/impressoras/i1/ao-vivo': (_) => {'estado': 'printing', 'arquivo': 'vaso.gcode', 'progresso': 0.4},
        'POST /api/impressoras/i1/comando': (_) => resposta.future,
      });
      await abrir(tester, amb);
      await tester.tap(find.text('Pausar'));
      await tester.pump();
      expect(habilitado(tester, 'Parada de emergência'), isTrue);
      resposta.complete({'ok': true});
      await tester.pumpAndSettle();
    });
  });
}

import 'dart:async';
import 'dart:convert' show jsonDecode, utf8;

import 'package:cubo3/telas/impressoes/impressoes_aba.dart';
import 'package:cubo3/telas/impressoes/impressora_tela.dart';
import 'package:cubo3/widgets/camera_mjpeg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'apoio.dart';

const impressora = {'id': 'i1', 'nome': 'Ender', 'moonraker_url': 'http://192.168.1.110:7125'};

/// Cliente que entrega o corpo de [fonte] e registra se foi fechado.
class ClienteVideo extends http.BaseClient {
  ClienteVideo(this.fonte);
  final StreamController<List<int>> fonte;
  bool fechado = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(fonte.stream, 200);

  @override
  void close() => fechado = true;
}

Ambiente ambiente({String estado = 'printing', Object? Function(http.Request)? comando}) => Ambiente({
      'GET /api/impressoras/i1/ao-vivo': (_) => {'estado': estado, 'arquivo': 'vaso.gcode', 'progresso': 0.4},
      'POST /api/impressoras/i1/comando': ?comando,
    });

Future<void> abrir(WidgetTester tester, Ambiente amb, {String papel = 'dono'}) async {
  await amb.preparar(papel: papel);
  await tamanhoTela(tester, 500, 2000);
  await tester.pumpWidget(amb.tela(const ImpressoraTela(impressora: impressora)));
  await tester.pumpAndSettle();
}

List<Map> comandos(Ambiente amb) => [
      for (final r in amb.recebidos)
        if (r.url.path == '/api/impressoras/i1/comando') jsonDecode(r.body) as Map
    ];

void main() {
  test('extrator MJPEG separa 2 quadros com lixo entre eles, mesmo partidos em pedaços', () async {
    final q1 = [0xFF, 0xD8, 1, 2, 0xFF, 0x00, 3, 0xFF, 0xD9];
    final q2 = [0xFF, 0xD8, 9, 0xFF, 0xD9];
    final bruto = [...utf8.encode('--boundarydonotcross\r\nContent-Type: image/jpeg\r\n\r\n'), ...q1,
      ...utf8.encode('\r\n--boundarydonotcross\r\n'), 0xFF, ...q2, 0xFF];
    final pedacos = [for (var i = 0; i < bruto.length; i += 3) bruto.sublist(i, i + 3 > bruto.length ? bruto.length : i + 3)];
    final quadros = await quadrosMjpeg(Stream.fromIterable(pedacos)).toList();
    expect(quadros, [q1, q2]);
  });

  test('cancelar o vídeo (sair da tela) fecha a conexão', () async {
    var origemCancelada = false;
    final fonte = StreamController<List<int>>(onCancel: () => origemCancelada = true);
    final cliente = ClienteVideo(fonte);
    final quadros = <List<int>>[];
    final assinatura = videoMjpeg(Uri.parse('https://teste/api/camera/t'), cliente).listen(quadros.add);
    fonte.add([0xFF, 0xD8, 7, 0xFF, 0xD9]);
    await pumpEventQueue();
    expect(quadros, hasLength(1));
    await assinatura.cancel();
    await pumpEventQueue();
    expect(origemCancelada, isTrue);
    expect(cliente.fechado, isTrue);
  });

  testWidgets('membro vê estado mas não vê controles', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb, papel: 'membro');
    expect(find.text('Imprimindo'), findsOneWidget);
    expect(find.text('Pausar'), findsNothing);
    expect(find.text('PETG'), findsNothing);
    expect(find.text('Parada de emergência'), findsNothing);
  });

  testWidgets('dono vê Pausar e Cancelar imprimindo; Continuar quando pausada', (tester) async {
    final amb = ambiente(estado: 'paused');
    await abrir(tester, amb);
    expect(find.text('Continuar'), findsOneWidget);
    expect(find.text('Pausar'), findsNothing);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(comandos(amb), [
      {'acao': 'continuar'}
    ]);
  });

  testWidgets('cancelar sem confirmar não chama a API', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(comandos(amb), isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar impressão'));
    await tester.pumpAndSettle();
    expect(comandos(amb), [
      {'acao': 'cancelar'}
    ]);
  });

  testWidgets('parada de emergência confirma explicando o reinício do Klipper', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb);
    await tester.tap(find.text('Parada de emergência'));
    await tester.pumpAndSettle();
    expect(find.textContaining('FIRMWARE_RESTART'), findsOneWidget);
    await tester.tap(find.text('Parar agora'));
    await tester.pumpAndSettle();
    expect(comandos(amb), [
      {'acao': 'emergencia'}
    ]);
  });

  testWidgets('comando com 502 mostra "Impressora não respondeu"', (tester) async {
    final amb = ambiente(comando: (_) => json({'detail': 'A impressora não respondeu'}, 502));
    await abrir(tester, amb);
    await tester.tap(find.text('Pausar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('impressora não respondeu'), findsOneWidget);
  });

  testWidgets('atalho PETG manda bico 235 e mesa 80', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb);
    await tester.tap(find.text('PETG'));
    await tester.pumpAndSettle();
    expect(comandos(amb), [
      {'acao': 'temperatura', 'alvo': 'bico', 'valor': 235},
      {'acao': 'temperatura', 'alvo': 'mesa', 'valor': 80},
    ]);
  });

  testWidgets('tocar no cartão ao vivo da aba Impressões abre a tela da impressora', (tester) async {
    final amb = ambiente()..rotas['GET /api/impressoras'] = (_) => [impressora];
    await amb.preparar();
    await tamanhoTela(tester, 500, 2000);
    await tester.pumpWidget(amb.tela(const ImpressoesAba()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ender'));
    await tester.pumpAndSettle();
    expect(find.text('Parada de emergência'), findsOneWidget);
  });

  testWidgets('sem conexão: comandos desabilitados com aviso e nada vai para a fila', (tester) async {
    final amb = ambiente();
    amb.online = false;
    await abrir(tester, amb);
    expect(find.textContaining('Sem conexão'), findsOneWidget);
    await tester.tap(find.text('PETG'));
    await tester.pumpAndSettle();
    expect(amb.fila.pendentes, 0);
    amb.online = true;
    expect(comandos(amb), isEmpty);
  });
}

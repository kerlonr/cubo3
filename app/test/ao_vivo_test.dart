import 'dart:async';
import 'dart:convert';

import 'package:cubo3/ao_vivo/canal_ao_vivo.dart';
import 'package:cubo3/api/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

EstadoImpressora estado(Map<String, Object?> d) => EstadoImpressora(d);

void main() {
  test('texto da notificação fixa', () {
    expect(
      textoProgresso(estado({'estado': 'printing', 'arquivo': 'vaso.gcode', 'progresso': 0.45, 'restante_s': 4320})),
      'Imprimindo vaso.gcode — 45% — faltam 1h12',
    );
    expect(textoProgresso(estado({'estado': 'standby'})), 'Cubo³ monitorando');
    expect(textoProgresso(null), 'Cubo³ monitorando');
    expect(textoTemperaturas(estado({'bico': 209.6, 'mesa': 60.2})), 'Bico 210° · Mesa 60°');
    expect(barraTexto(0.45), '▰▰▰▰▱▱▱▱▱▱');
  });

  test('fim de impressão: concluída pede confirmação; cancelada avisa que parou', () {
    final ok = alertaFim({'tipo': 'impressao_terminou', 'impressao_id': 'i1', 'arquivo': 'vaso.gcode', 'situacao': 'completed'});
    expect(ok.titulo, 'Impressão terminou: vaso.gcode');
    expect(ok.corpo, 'Toque para confirmar');
    final parou = alertaFim({'tipo': 'impressao_terminou', 'impressao_id': 'i1', 'arquivo': 'vaso.gcode', 'situacao': 'cancelled'});
    expect(parou.titulo, 'Impressão parou');
    expect(parou.corpo, contains('vaso.gcode'));
  });

  test('CanalAoVivo atualiza estados e reconecta depois de uma queda', () async {
    final conexoes = <StreamController<dynamic>>[];
    final urls = <Uri>[];
    var refreshes = 0;
    final api = ApiCliente(
        MockClient((r) async {
          refreshes++;
          return http.Response(jsonEncode({'acesso': 'A$refreshes', 'refresh': 'R'}), 200);
        }),
        Uri.parse('https://cubo3.kerlonr.com.br'),
        ArmazemMemoria());
    await api.usarTokens({'acesso': 'A0', 'refresh': 'R'});
    api.empresaId = 'emp';
    final canal = CanalAoVivo(api, esperaInicial: const Duration(milliseconds: 10), conectar: (uri) {
      urls.add(uri);
      final c = StreamController<dynamic>();
      conexoes.add(c);
      return (stream: c.stream, enviar: (_) {}, fechar: () async {});
    });
    canal.iniciar();
    await Future<void>.delayed(Duration.zero);
    expect(urls.single.toString(), 'wss://cubo3.kerlonr.com.br/api/ao-vivo?token=A0&empresa=emp');

    conexoes.last.add(jsonEncode({'tipo': 'estado', 'impressora_id': 'p1', 'estado': 'printing', 'progresso': 0.5}));
    await Future<void>.delayed(Duration.zero);
    expect(canal.estados['p1']!.progresso, 0.5);

    await conexoes.last.close(); // queda
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(conexoes, hasLength(2));
    expect(urls.last.queryParameters['token'], 'A1', reason: 'renova o token antes de reconectar');

    final eventos = <Map>[];
    canal.eventos.listen(eventos.add);
    conexoes.last.add(jsonEncode({'tipo': 'impressao_terminou', 'impressao_id': 'i1', 'situacao': 'completed'}));
    await Future<void>.delayed(Duration.zero);
    expect(eventos.single['impressao_id'], 'i1');
    canal.parar();
  });
}

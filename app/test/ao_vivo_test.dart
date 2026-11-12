import 'dart:async';
import 'dart:convert';

import 'package:cubo3/ao_vivo/canal_ao_vivo.dart';
import 'package:cubo3/api/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

EstadoImpressora estado(Map<String, Object?> d) => EstadoImpressora(d);

void main() {
  test('notificação imprimindo: título com a peça, % e hora do fim; puxando para baixo vêm camada e temperaturas', () {
    final c = conteudoNotificacao(
        estado({
          'estado': 'printing',
          'arquivo': 'pecas/choinka_PLA_3h11m.gcode',
          'progresso': 0.45,
          'restante_s': 4320,
          'camada': 34,
          'camadas': 120,
          'bico': 209.6,
          'bico_alvo': 210,
          'mesa': 60.2,
          'mesa_alvo': 60,
          'velocidade_pct': 100,
          'ventoinha_pct': 80,
        }),
        DateTime(2026, 11, 11, 13, 0));
    expect(c.titulo, 'Imprimindo · choinka PLA 3h11m');
    expect(c.corpo, '45% · termina às 14:12');
    expect(c.linhas, [
      '45% · camada 34 de 120',
      'Termina às 14:12 (faltam 1h12)',
      'Bico 210/210 °C · Mesa 60/60 °C',
      'Velocidade 100% · Ventoinha 80%',
    ]);
    expect(c.terminaEm, DateTime(2026, 11, 11, 14, 12));
    expect(c.progresso, 0.45);
  });

  test('notificação pausada não conta o tempo; parada mostra só as temperaturas', () {
    final p = conteudoNotificacao(estado({'estado': 'paused', 'arquivo': 'vaso.gcode', 'progresso': 0.5}), DateTime(2026));
    expect(p.titulo, 'Pausada · vaso');
    expect(p.terminaEm, isNull);
    expect(p.linhas, contains('Pausada: toque para abrir a impressora'));
    final parada = conteudoNotificacao(estado({'estado': 'standby', 'bico': 24.4, 'mesa': 23}), DateTime(2026));
    expect((parada.titulo, parada.corpo, parada.ativa), ('Cubo³', 'Nenhuma impressão agora · Bico 24° · Mesa 23°', false));
    expect(conteudoNotificacao(null, DateTime(2026)).corpo, 'Nenhuma impressão agora');
  });

  test('fim de impressão: concluída pede os gramas; cancelada avisa que parou', () {
    final ok = alertaFim({'tipo': 'impressao_terminou', 'impressao_id': 'i1', 'arquivo': 'vaso.gcode', 'situacao': 'completed'});
    expect(ok.titulo, 'Terminou: vaso');
    expect(ok.corpo, 'Toque para confirmar os gramas');
    final parou = alertaFim({'tipo': 'impressao_terminou', 'impressao_id': 'i1', 'arquivo': 'vaso.gcode', 'situacao': 'cancelled'});
    expect(parou.titulo, 'Parou: vaso');
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

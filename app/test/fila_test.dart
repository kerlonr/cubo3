import 'dart:convert';

import 'package:cubo3/api/api.dart';
import 'package:cubo3/api/cache.dart';
import 'package:cubo3/api/fila.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object corpo, [int status = 200]) => http.Response(jsonEncode(corpo), status);

/// Servidor falso: `online` liga/desliga a rede; registra o que chegou.
class Servidor {
  bool online = false;
  int status = 200;
  final recebidos = <http.Request>[];

  ApiCliente api() => ApiCliente(
      MockClient((r) async {
        if (!online) throw http.ClientException('sem rede');
        recebidos.add(r);
        return status == 200 ? json({'ok': true, 'avisos': []}) : json({'detail': 'Recusado $status'}, status);
      }),
      Uri.parse('https://teste'),
      ArmazemMemoria());
}

Operacao venda() => Operacao.nova('PUT', '/api/pedidos/p1', {'status': 'entregue', 'itens': []});

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('sem rede a venda fica guardada e sobrevive ao app reaberto; volta a rede e chega uma vez só', () async {
    final s = Servidor();
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    final r = await fila.enviarOuGuardar(venda());
    expect(r.guardada, isTrue);
    expect(fila.pendentes, 1);

    final reaberta = FilaOffline(s.api(), prefs, guardaOffline: true);
    expect(reaberta.pendentes, 1);

    s.online = true;
    await reaberta.esvaziar();
    await reaberta.esvaziar();
    expect(s.recebidos.where((r) => r.url.path == '/api/pedidos/p1'), hasLength(1));
    expect(reaberta.pendentes, 0);
    expect(FilaOffline(s.api(), prefs, guardaOffline: true).pendentes, 0);
  });

  test('ordem preservada: carretel antes do movimento que o usa', () async {
    final s = Servidor();
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/carreteis/c1', {'peso_inicial_g': 1000}));
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/movimentos/m1', {'item_id': 'c1'}));
    s.online = true;
    await fila.esvaziar();
    expect(s.recebidos.map((r) => r.url.path), ['/api/carreteis/c1', '/api/movimentos/m1']);
  });

  test('com algo na fila, operação nova entra atrás (não fura a ordem)', () async {
    final s = Servidor();
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/carreteis/c1', {}));
    s.online = true;
    final r = await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/movimentos/m1', {}));
    expect(r.guardada, isFalse);
    expect(s.recebidos.map((r) => r.url.path), ['/api/carreteis/c1', '/api/movimentos/m1']);
  });

  test('409 sai da fila e aparece em erros; 503 continua na fila', () async {
    final s = Servidor();
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    await fila.enviarOuGuardar(venda());
    s
      ..online = true
      ..status = 503;
    await fila.esvaziar();
    expect(fila.pendentes, 1);
    s.status = 409;
    await fila.esvaziar();
    expect(fila.pendentes, 0);
    expect(fila.erros.single.mensagem, 'Recusado 409');
    expect(FilaOffline(s.api(), prefs, guardaOffline: true).erros, hasLength(1), reason: 'erros persistem');
  });

  test('ao enviar o que estava guardado, avisa as telas (dadosMudaram); sem envio não avisa', () async {
    final s = Servidor();
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    await fila.enviarOuGuardar(venda());
    final antes = dadosMudaram.value;
    await fila.esvaziar();
    expect(dadosMudaram.value, antes, reason: 'sem rede nada foi gravado');
    s.online = true;
    await fila.esvaziar();
    expect(dadosMudaram.value, antes + 1);
  });

  test('401 (sessão expirada) não descarta a operação', () async {
    final s = Servidor();
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    await fila.enviarOuGuardar(venda());
    s
      ..online = true
      ..status = 401;
    await fila.esvaziar();
    expect(fila.pendentes, 1);
    expect(fila.erros, isEmpty);
  });

  test('edição leva X-Versao-Base exato; criação não leva; X-Alterado-Em nunca', () async {
    final s = Servidor()..online = true;
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/c1', {'nome': 'A'}));
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/c1', {'nome': 'B'}, '2026-11-03T12:30:00.123456+00:00'));
    expect(s.recebidos[0].headers.containsKey('X-Versao-Base'), isFalse);
    expect(s.recebidos[1].headers['X-Versao-Base'], '2026-11-03T12:30:00.123456+00:00');
    expect(s.recebidos.where((r) => r.headers.containsKey('X-Alterado-Em')), isEmpty);
  });

  test('criar e editar sem internet: tudo chega em ordem; só a edição de registro do servidor leva versão base', () async {
    final s = Servidor();
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/c1', {'nome': 'A'}));
    // Nasceu no aparelho: não há versão lida do servidor.
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/c1', {'nome': 'B'}));
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/c2', {'nome': 'C'}, 'v2'));
    s.online = true;
    await FilaOffline(s.api(), prefs, guardaOffline: true).esvaziar();
    expect(s.recebidos.map((r) => r.body), [for (final n in 'ABC'.split('')) jsonEncode({'nome': n})]);
    expect(s.recebidos.map((r) => r.headers['X-Versao-Base']), [null, null, 'v2']);
    expect(s.recebidos.where((r) => r.headers.containsKey('X-Alterado-Em')), isEmpty);
  });

  test('erro definitivo com fila vazia sobe para a tela; no navegador sem rede também', () async {
    final s = Servidor()
      ..online = true
      ..status = 422;
    final fila = FilaOffline(s.api(), prefs, guardaOffline: true);
    await expectLater(fila.enviarOuGuardar(venda()), throwsA(isA<ErroApi>()));
    expect(fila.pendentes, 0);
    final web = FilaOffline(Servidor().api(), prefs, guardaOffline: false);
    await expectLater(web.enviarOuGuardar(venda()), throwsA(isA<ErroApi>()));
    expect(web.pendentes, 0);
  });

  test('operação guardada vai para a empresa em que foi feita, mesmo se trocar de empresa', () async {
    final s = Servidor();
    final api = s.api()..empresaId = 'A';
    final fila = FilaOffline(api, prefs, guardaOffline: true);
    await fila.enviarOuGuardar(venda());
    api.empresaId = 'B';
    s.online = true;
    final reaberta = FilaOffline(api, prefs, guardaOffline: true);
    await reaberta.esvaziar();
    expect(s.recebidos.single.headers['X-Empresa'], 'A');
  });

  test('cache: falha de rede devolve o último dado com deCache', () async {
    final cache = CacheLeitura(prefs, persistir: true);
    final r1 = await cache.obter('canais', () async => [1, 2]);
    expect(r1.deCache, isFalse);
    final r2 = await CacheLeitura(prefs, persistir: true)
        .obter('canais', () async => throw ErroApi(null, 'Sem conexão'));
    expect(r2.deCache, isTrue);
    expect(r2.dados, [1, 2]);
    expect(r2.quando, isNotNull);
    await expectLater(cache.obter('outra', () async => throw ErroApi(null, 'Sem conexão')), throwsA(isA<ErroApi>()));
  });
}

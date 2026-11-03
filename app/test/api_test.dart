import 'dart:async';
import 'dart:convert';

import 'package:cubo3/api/api.dart';
import 'package:cubo3/api/sessao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object corpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(corpo)), status, headers: {'content-type': 'application/json'});

const empA = {'id': 'a', 'nome': 'Empresa A', 'papel': 'dono'};
const empB = {'id': 'b', 'nome': 'Empresa B', 'papel': 'membro'};

Map<String, Object> eu({List empresas = const [empA], bool trocar = false}) =>
    {'id': 'u', 'nome': 'Kerlon', 'email': 'k@x.com', 'trocar_senha': trocar, 'empresas': empresas};

ApiCliente cliente(MockClientHandler f, [ArmazemTokens? armazem]) =>
    ApiCliente(MockClient(f), Uri.parse('https://teste'), armazem ?? ArmazemMemoria());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('login grava o refresh e manda Authorization; X-Empresa depois de escolher', () async {
    final armazem = ArmazemMemoria();
    final pedidos = <http.Request>[];
    final api = cliente((r) async {
      pedidos.add(r);
      if (r.url.path == '/api/auth/login') return json({'acesso': 'A1', 'refresh': 'R1', 'trocar_senha': false});
      if (r.url.path == '/api/eu') return json(eu());
      return json({'ok': true});
    }, armazem);
    final s = Sessao(api, await SharedPreferences.getInstance());
    await s.entrar('k@x.com', 'segredo123');
    expect(await armazem.lerRefresh(), 'R1');
    expect(pedidos[1].headers['Authorization'], 'Bearer A1');
    expect(s.estado, EstadoSessao.pronta, reason: 'uma empresa só vai direto');
    await api.get('/api/canais');
    expect(pedidos.last.headers['X-Empresa'], 'a');
  });

  test('401 renova com o refresh e repete a chamada', () async {
    var tentativas = 0;
    final api = cliente((r) async {
      if (r.url.path == '/api/auth/refresh') {
        expect(jsonDecode(r.body), {'refresh': 'R1'});
        return json({'acesso': 'A2', 'refresh': 'R2'});
      }
      tentativas++;
      return r.headers['Authorization'] == 'Bearer A2' ? json([1, 2]) : json({'detail': 'expirou'}, 401);
    });
    await api.usarTokens({'acesso': 'A1', 'refresh': 'R1'});
    expect(await api.get('/api/canais'), [1, 2]);
    expect(tentativas, 2);
    expect(await api.armazem.lerRefresh(), 'R2');
  });

  test('duas chamadas simultâneas com 401 fazem um refresh só', () async {
    var refreshes = 0;
    final api = cliente((r) async {
      if (r.url.path == '/api/auth/refresh') {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return json({'acesso': 'A2', 'refresh': 'R2'});
      }
      return r.headers['Authorization'] == 'Bearer A2' ? json({'ok': 1}) : json({'detail': 'x'}, 401);
    });
    await api.usarTokens({'acesso': 'A1', 'refresh': 'R1'});
    await Future.wait([api.get('/api/a'), api.get('/api/b'), api.get('/api/c')]);
    expect(refreshes, 1);
  });

  test('refresh recusado leva ao login', () async {
    final api = cliente((r) async => json({'detail': 'Sessão inválida ou expirada'}, 401));
    final s = Sessao(api, await SharedPreferences.getInstance());
    await api.usarTokens({'acesso': 'A1', 'refresh': 'R1'});
    var expirou = 0;
    s.addListener(() => expirou++);
    await expectLater(api.get('/api/canais'), throwsA(isA<ErroApi>()));
    expect(s.estado, EstadoSessao.deslogado);
    expect(await api.armazem.lerRefresh(), isNull);
    expect(expirou, greaterThan(0));
  });

  test('corpo HTML com 413 vira mensagem amigável', () async {
    final api = cliente((r) async => http.Response('<html>Request Entity Too Large</html>', 413));
    await expectLater(
        api.get('/api/x'), throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', 'Arquivo maior que 95 MB')));
  });

  test('5xx em HTML e falta de rede viram mensagens claras', () async {
    final api502 = cliente((r) async => http.Response('<html>Bad gateway</html>', 502));
    await expectLater(api502.get('/api/x'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', 'Servidor indisponível')));
    final semRede = cliente((r) async => throw http.ClientException('Failed host lookup'));
    await expectLater(semRede.get('/api/x'),
        throwsA(isA<ErroApi>().having((e) => e.semConexao, 'semConexao', true).having((e) => e.mensagem, 'm', 'Sem conexão')));
  });

  test('detail do servidor vira a mensagem (inclusive lista do 422)', () async {
    final api = cliente((r) async => json({'detail': 'E-mail ou senha incorretos'}, 401));
    await expectLater(api.post('/api/auth/login', {'email': 'x', 'senha': 'y'}),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'm', 'E-mail ou senha incorretos')));
    final api422 = cliente((r) async => json({
          'detail': [
            {'msg': 'Value error, A senha precisa ter pelo menos 8 caracteres'}
          ]
        }, 422));
    await expectLater(api422.post('/api/x'),
        throwsA(isA<ErroApi>().having((e) => e.mensagem, 'm', 'A senha precisa ter pelo menos 8 caracteres')));
  });

  test('trocar_senha no login vai para a troca de senha', () async {
    final api = cliente((r) async {
      if (r.url.path == '/api/auth/login') return json({'acesso': 'A1', 'refresh': 'R1', 'trocar_senha': true});
      if (r.url.path == '/api/auth/senha') return json({'acesso': 'A2', 'refresh': 'R2'});
      return json(eu());
    });
    final s = Sessao(api, await SharedPreferences.getInstance());
    await s.entrar('k@x.com', 'inicial123');
    expect(s.estado, EstadoSessao.trocarSenha);
    await s.trocarSenha('inicial123', 'nova-senha-1');
    expect(s.estado, EstadoSessao.pronta);
    expect(api.tokenAcesso, 'A2');
  });

  test('várias empresas: escolher, lembrar e restaurar', () async {
    Future<http.Response> servidor(http.Request r) async {
      if (r.url.path == '/api/auth/login') return json({'acesso': 'A1', 'refresh': 'R1', 'trocar_senha': false});
      if (r.url.path == '/api/auth/refresh') return json({'acesso': 'A2', 'refresh': 'R2'});
      return json(eu(empresas: [empA, empB]));
    }

    final api = cliente(servidor);
    final prefs = await SharedPreferences.getInstance();
    final s = Sessao(api, prefs);
    await s.entrar('k@x.com', 'segredo123');
    expect(s.estado, EstadoSessao.escolherEmpresa);
    await s.escolherEmpresa('b');
    expect(s.estado, EstadoSessao.pronta);
    expect(s.papel, 'membro');

    // App reaberto: usa o refresh guardado e a empresa lembrada.
    final api2 = cliente(servidor, api.armazem);
    final s2 = Sessao(api2, prefs);
    await s2.restaurar();
    expect(s2.estado, EstadoSessao.pronta);
    expect(api2.empresaId, 'b');
  });

  test('restaurar sem internet usa o último /api/eu guardado', () async {
    final prefs = await SharedPreferences.getInstance();
    final online = cliente((r) async {
      if (r.url.path == '/api/auth/login') return json({'acesso': 'A1', 'refresh': 'R1', 'trocar_senha': false});
      return json(eu());
    });
    await Sessao(online, prefs).entrar('k@x.com', 'segredo123');
    final offline = cliente((r) async => throw http.ClientException('sem rede'), online.armazem);
    final s = Sessao(offline, prefs);
    await s.restaurar();
    expect(s.estado, EstadoSessao.pronta);
    expect(offline.empresaId, 'a');
  });

  test('sair apaga o refresh', () async {
    final api = cliente((r) async => json({'acesso': 'A1', 'refresh': 'R1', 'trocar_senha': false}));
    final s = Sessao(api, await SharedPreferences.getInstance());
    await api.usarTokens({'acesso': 'A1', 'refresh': 'R1'});
    await s.sair();
    expect(await api.armazem.lerRefresh(), isNull);
    expect(s.estado, EstadoSessao.deslogado);
  });
}

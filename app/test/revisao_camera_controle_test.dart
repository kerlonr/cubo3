// Revisão 79c77a8..4a7f389: testes que provam bugs da fila offline.
import 'dart:convert';

import 'package:cubo3/api/api.dart';
import 'package:cubo3/api/fila.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('servidor com 500 passageiro (banco reiniciando) não joga a fila inteira nos erros', () async {
    // O servidor devolve 500 nos 6 primeiros pedidos (ex.: Postgres reiniciando por ~1 s) e depois volta.
    var online = false, pedidos = 0;
    final api = ApiCliente(
        MockClient((r) async {
          if (!online) throw http.ClientException('sem rede');
          pedidos++;
          return pedidos <= 6
              ? http.Response(jsonEncode({'detail': 'Internal Server Error'}), 500)
              : http.Response(jsonEncode({'ok': true}), 200);
        }),
        Uri.parse('https://teste'),
        ArmazemMemoria());
    final fila = FilaOffline(api, prefs, guardaOffline: true);
    for (final n in ['a', 'b', 'c']) {
      await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/$n', {'nome': n}));
    }
    online = true;
    await fila.esvaziar();
    // Hoje: as 3 tentativas de cada operação saem uma atrás da outra, sem espera; 'a' e 'b' vão para os erros
    // em milissegundos e só 'c' chega. As vendas/edições 'a' e 'b' ficam perdidas (a lista de erros não reenvia).
    expect(fila.erros, isEmpty, reason: 'um 500 de 1 s não deveria descartar operação nenhuma');
  });

  test('duas edições do mesmo registro feitas sem internet chegam as duas', () async {
    // Servidor com a regra do X-Versao-Base: recusa (409) se o registro mudou depois da versão lida.
    var online = false;
    var versao = 'v1';
    final api = ApiCliente(
        MockClient((r) async {
          if (!online) throw http.ClientException('sem rede');
          final base = r.headers['X-Versao-Base'];
          if (base != null && base != versao) {
            return http.Response(jsonEncode({'detail': 'Cliente foi alterado por outra pessoa.'}), 409);
          }
          versao = 'v${int.parse(versao.substring(1)) + 1}';
          return http.Response(jsonEncode({'ok': true, 'atualizado_em': versao}), 200);
        }),
        Uri.parse('https://teste'),
        ArmazemMemoria());
    final fila = FilaOffline(api, prefs, guardaOffline: true);
    // Sem internet a tela lê do cache: as duas edições levam a mesma versão lida ('v1').
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/c1', {'nome': 'Ana Souza'}, 'v1'));
    await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/c1', {'telefone': '5599'}, 'v1'));
    online = true;
    await fila.esvaziar();
    // Hoje: a segunda volta 409 "alterado por outra pessoa" — foi o próprio aparelho — e vai para os erros.
    expect(fila.erros, isEmpty, reason: 'a 2ª edição do mesmo aparelho não é conflito com outra pessoa');
  });
}

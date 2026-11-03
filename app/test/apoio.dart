import 'dart:convert';

import 'dart:async';

import 'package:cubo3/ao_vivo/canal_ao_vivo.dart';
import 'package:cubo3/api/api.dart';
import 'package:cubo3/api/cache.dart';
import 'package:cubo3/api/fila.dart';
import 'package:cubo3/api/sessao.dart';
import 'package:cubo3/main.dart';
import 'package:cubo3/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GETs que devolvem objeto (o resto das listagens devolve lista).
const objetos = {'/api/estoque', '/api/painel', '/api/empresa/config'};

http.Response json(Object? corpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(corpo)), status, headers: {'content-type': 'application/json'});

const empresaA = {'id': 'a', 'nome': 'Cubo³', 'papel': 'dono'};

Map<String, Object> euJson({String papel = 'dono'}) => {
      'id': 'u',
      'nome': 'Kerlon',
      'email': 'k@x.com',
      'trocar_senha': false,
      'empresas': [
        {...empresaA, 'papel': papel}
      ]
    };

/// Ambiente de teste: servidor falso (`rotas` por "MÉTODO /caminho"), pedidos recebidos e serviços do app.
class Ambiente {
  Ambiente(this.rotas);

  final Map<String, Object? Function(http.Request)> rotas;

  /// Rotas por prefixo ("PUT /api/pedidos/"), para ids gerados no aparelho.
  final rotasPrefixo = <String, Object? Function(http.Request)>{};
  final recebidos = <http.Request>[];
  bool online = true;
  late ApiCliente api;
  late Sessao sessao;
  late FilaOffline fila;
  late CacheLeitura cache;
  late CanalAoVivo canal;

  /// Conexão ao vivo falsa: mande eventos com `aoVivo.add(jsonEncode({...}))`.
  final aoVivo = StreamController<dynamic>.broadcast();

  http.Request? ultimo(String metodoCaminho) {
    for (final r in recebidos.reversed) {
      if ('${r.method} ${r.url.path}' == metodoCaminho) return r;
    }
    return null;
  }

  Map corpo(String metodoCaminho) => jsonDecode(ultimo(metodoCaminho)!.body) as Map;

  Future<void> preparar({bool logado = true, String papel = 'dono', bool guardaOffline = true}) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pt_BR');
    final prefs = await SharedPreferences.getInstance();
    api = ApiCliente(
        MockClient((r) async {
          if (!online) throw http.ClientException('sem rede');
          recebidos.add(r);
          final chave = '${r.method} ${r.url.path}';
          if (rotas.containsKey(chave)) {
            var v = rotas[chave]!(r);
            if (v is Future) v = await v; // rota que responde depois (comando ainda no ar)
            return v is http.Response ? v : json(v);
          }
          for (final e in rotasPrefixo.entries) {
            if (chave.startsWith(e.key)) {
              final v = e.value(r);
              return v is http.Response ? v : json(v);
            }
          }
          if (r.url.path == '/api/eu') return json(euJson(papel: papel));
          if (r.method == 'GET') {
            final objeto = r.url.pathSegments.length > 2 || objetos.contains(r.url.path);
            return json(objeto ? {} : []);
          }
          return json(r.method == 'PUT' || r.method == 'POST' ? jsonDecode(r.body.isEmpty ? '{}' : r.body) : {'ok': true});
        }),
        Uri.parse('https://teste'),
        ArmazemMemoria());
    sessao = Sessao(api, prefs);
    fila = FilaOffline(api, prefs, guardaOffline: guardaOffline);
    cache = CacheLeitura(prefs, persistir: false);
    canal = CanalAoVivo(api, conectar: (_) => (stream: aoVivo.stream, enviar: (_) {}, fechar: () async {}));
    if (logado) {
      await api.usarTokens({'acesso': 'A', 'refresh': 'R'});
      await sessao.escolherEmpresa('a');
      sessao.eu = euJson(papel: papel);
    } else {
      sessao.estado = EstadoSessao.deslogado;
    }
  }

  Widget app() => AppCubo3(api: api, sessao: sessao, fila: fila, cache: cache, canal: canal);

  /// Monta uma tela solta com os mesmos serviços do app ([brilho] = com o tema e o idioma do app).
  Widget tela(Widget filho, {Brightness? brilho}) => MultiProvider(
        providers: provedores(api, sessao, fila, cache, canal),
        child: brilho == null
            ? MaterialApp(home: filho)
            : MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: temaCubo3(brilho),
                locale: const Locale('pt', 'BR'),
                supportedLocales: const [Locale('pt', 'BR')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: filho,
              ),
      );
}

Future<void> tamanhoTela(WidgetTester tester, double largura, [double altura = 900]) async {
  tester.view.physicalSize = Size(largura, altura);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

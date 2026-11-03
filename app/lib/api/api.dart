import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Erro de chamada à API com mensagem pronta para a tela.
class ErroApi implements Exception {
  ErroApi(this.status, this.mensagem);

  /// null = não chegou ao servidor (sem rede, DNS, tempo esgotado).
  final int? status;
  final String mensagem;

  bool get semConexao => status == null;

  /// Sem rede ou servidor fora: vale guardar na fila e tentar depois.
  bool get temporario => status == null || status! >= 500;

  factory ErroApi.daResposta(int status, List<int> corpo) {
    try {
      final detail = (jsonDecode(utf8.decode(corpo)) as Map)['detail'];
      if (detail is String) return ErroApi(status, detail);
      if (detail is List && detail.isNotEmpty) {
        final msg = '${(detail.first as Map)['msg']}'.replaceFirst('Value error, ', '');
        return ErroApi(status, msg);
      }
    } catch (_) {
      // Corpo não-JSON (página HTML da Cloudflare): cai na mensagem pelo status.
    }
    return ErroApi(status, switch (status) {
      413 => 'Arquivo maior que 95 MB',
      401 => 'Sessão expirada. Entre de novo.',
      403 => 'Sem permissão',
      404 => 'Não encontrado',
      >= 500 => 'Servidor indisponível',
      _ => 'Erro $status',
    });
  }

  @override
  String toString() => mensagem;
}

abstract class ArmazemTokens {
  Future<String?> lerRefresh();
  Future<void> gravarRefresh(String? refresh);
}

class ArmazemSeguro implements ArmazemTokens {
  static const _chave = 'refresh';
  final _s = const FlutterSecureStorage();

  @override
  Future<String?> lerRefresh() => _s.read(key: _chave);

  @override
  Future<void> gravarRefresh(String? refresh) =>
      refresh == null ? _s.delete(key: _chave) : _s.write(key: _chave, value: refresh);
}

class ArmazemMemoria implements ArmazemTokens {
  String? _refresh;

  @override
  Future<String?> lerRefresh() async => _refresh;

  @override
  Future<void> gravarRefresh(String? refresh) async => _refresh = refresh;
}

class ApiCliente {
  ApiCliente(this._http, this.base, this.armazem);

  final http.Client _http;
  Uri base;
  final ArmazemTokens armazem;
  String? empresaId;
  String? _acesso;
  Future<void>? _renovando;

  /// Chamado quando o refresh é recusado: a sessão acabou e é preciso entrar de novo.
  void Function()? aoSessaoExpirar;

  String? get tokenAcesso => _acesso;

  Map<String, String> get cabecalhosAuth => {
        if (_acesso != null) 'Authorization': 'Bearer $_acesso',
        if (empresaId != null) 'X-Empresa': empresaId!,
      };

  Uri url(String caminho, [Map<String, String>? query]) {
    final u = base.resolve(caminho);
    return query == null || query.isEmpty ? u : u.replace(queryParameters: query);
  }

  Future<void> usarTokens(Map tokens) async {
    _acesso = tokens['acesso'] as String?;
    await armazem.gravarRefresh(tokens['refresh'] as String?);
  }

  Future<void> esquecerTokens() async {
    _acesso = null;
    await armazem.gravarRefresh(null);
  }

  /// Renova o acesso com o refresh guardado. Chamadas simultâneas esperam o mesmo refresh.
  Future<void> renovar() => _renovando ??= _renovar().whenComplete(() => _renovando = null);

  Future<void> _renovar() async {
    final refresh = await armazem.lerRefresh();
    if (refresh == null) {
      _expirou();
      throw ErroApi(401, 'Sessão expirada. Entre de novo.');
    }
    try {
      await usarTokens(await _bruto('POST', '/api/auth/refresh', corpo: {'refresh': refresh}, comAuth: false));
    } on ErroApi catch (e) {
      if (e.status == 401 || e.status == 403) _expirou();
      rethrow;
    }
  }

  void _expirou() {
    _acesso = null;
    armazem.gravarRefresh(null);
    aoSessaoExpirar?.call();
  }

  Future<dynamic> get(String caminho, {Map<String, String>? query}) => _chamar('GET', caminho, query: query);

  Future<dynamic> put(String caminho, Map corpo, {DateTime? alteradoEm}) => _chamar('PUT', caminho,
      corpo: corpo, extra: {if (alteradoEm != null) 'X-Alterado-Em': alteradoEm.toUtc().toIso8601String()});

  Future<dynamic> post(String caminho, [Map? corpo]) => _chamar('POST', caminho, corpo: corpo ?? const {});

  Future<dynamic> delete(String caminho) => _chamar('DELETE', caminho);

  /// Chamada genérica (usada pela fila offline).
  Future<dynamic> enviar(String metodo, String caminho, {Map? corpo, Map<String, String>? extra}) =>
      _chamar(metodo, caminho, corpo: corpo, extra: extra);

  Future<dynamic> _chamar(String metodo, String caminho,
      {Map<String, String>? query, Object? corpo, Map<String, String>? extra}) async {
    final semAuth = caminho == '/api/auth/login' || caminho == '/api/auth/refresh';
    final usado = _acesso;
    try {
      return await _bruto(metodo, caminho, query: query, corpo: corpo, extra: extra, comAuth: !semAuth);
    } on ErroApi catch (e) {
      if (e.status != 401 || semAuth) rethrow;
      // Outro pedido pode já ter renovado enquanto este estava no ar.
      if (_acesso == usado) await renovar();
      return _bruto(metodo, caminho, query: query, corpo: corpo, extra: extra);
    }
  }

  Future<dynamic> _bruto(String metodo, String caminho,
      {Map<String, String>? query, Object? corpo, Map<String, String>? extra, bool comAuth = true}) async {
    final r = http.Request(metodo, url(caminho, query));
    if (comAuth) r.headers.addAll(cabecalhosAuth);
    if (extra != null) r.headers.addAll(extra);
    if (corpo != null) {
      r.headers['Content-Type'] = 'application/json';
      r.bodyBytes = utf8.encode(jsonEncode(corpo));
    }
    return _resposta(() => _http.send(r).timeout(const Duration(seconds: 30)));
  }

  /// Envia um arquivo (multipart, campo `arquivo`).
  /// shortcut: o stream não pode ser reenviado; em 401 renova e pede para tentar de novo.
  Future<dynamic> enviarArquivo(String caminho,
      {required String nome, required Stream<List<int>> bytes, required int tamanho}) async {
    final r = http.MultipartRequest('POST', url(caminho))
      ..headers.addAll(cabecalhosAuth)
      ..files.add(http.MultipartFile('arquivo', bytes, tamanho, filename: nome));
    try {
      return await _resposta(() => _http.send(r));
    } on ErroApi catch (e) {
      if (e.status != 401) rethrow;
      await renovar();
      throw ErroApi(null, 'Sessão renovada. Envie o arquivo de novo.');
    }
  }

  Future<dynamic> _resposta(Future<http.StreamedResponse> Function() enviar) async {
    final http.Response resp;
    try {
      resp = await http.Response.fromStream(await enviar());
    } on ErroApi {
      rethrow;
    } catch (_) {
      throw ErroApi(null, 'Sem conexão');
    }
    if (resp.statusCode >= 400) throw ErroApi.daResposta(resp.statusCode, resp.bodyBytes);
    if (resp.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw ErroApi(resp.statusCode, 'Resposta inesperada do servidor');
    }
  }
}

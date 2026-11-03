import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

enum EstadoSessao { carregando, deslogado, trocarSenha, escolherEmpresa, pronta }

class Sessao extends ChangeNotifier {
  Sessao(this.api, this._prefs) {
    api.aoSessaoExpirar = () => _mudar(EstadoSessao.deslogado);
  }

  final ApiCliente api;
  final SharedPreferences _prefs;
  static const _chaveEmpresa = 'empresa_v1';
  static const _chaveEu = 'eu_v1';

  EstadoSessao estado = EstadoSessao.carregando;
  Map<String, dynamic>? eu;

  List<Map<String, dynamic>> get empresas =>
      [for (final e in (eu?['empresas'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];

  Map<String, dynamic>? get empresaAtual {
    for (final e in empresas) {
      if (e['id'] == api.empresaId) return e;
    }
    return null;
  }

  String? get papel => empresaAtual?['papel'] as String?;
  bool get dono => papel == 'dono';

  Future<void> entrar(String email, String senha) async {
    final t = await api.post('/api/auth/login', {'email': email.trim(), 'senha': senha}) as Map;
    await api.usarTokens(t);
    if (t['trocar_senha'] == true) return _mudar(EstadoSessao.trocarSenha);
    await _carregarEu();
  }

  Future<void> trocarSenha(String atual, String nova) async {
    await api.usarTokens(await api.post('/api/auth/senha', {'atual': atual, 'nova': nova}) as Map);
    await _carregarEu();
  }

  Future<void> escolherEmpresa(String id) async {
    api.empresaId = id;
    await _prefs.setString(_chaveEmpresa, id);
    _mudar(EstadoSessao.pronta);
  }

  /// Volta para a tela de escolha (quem tem mais de uma empresa).
  void trocarEmpresa() => _mudar(EstadoSessao.escolherEmpresa);

  Future<void> sair() async {
    await api.esquecerTokens();
    api.empresaId = null;
    eu = null;
    await _prefs.remove(_chaveEu);
    _mudar(EstadoSessao.deslogado);
  }

  /// Abre o app com o refresh guardado. Sem internet, segue com o último /api/eu (fila e cache continuam).
  Future<void> restaurar() async {
    if (await api.armazem.lerRefresh() == null) return _mudar(EstadoSessao.deslogado);
    try {
      await api.renovar();
      await _carregarEu();
    } on ErroApi catch (e) {
      final guardado = _prefs.getString(_chaveEu);
      if (e.temporario && guardado != null) {
        _aplicarEu(jsonDecode(guardado) as Map<String, dynamic>);
      } else {
        _mudar(EstadoSessao.deslogado);
      }
    }
  }

  Future<void> _carregarEu() async {
    final dados = Map<String, dynamic>.from(await api.get('/api/eu') as Map);
    await _prefs.setString(_chaveEu, jsonEncode(dados));
    _aplicarEu(dados);
  }

  void _aplicarEu(Map<String, dynamic> dados) {
    eu = dados;
    if (dados['trocar_senha'] == true) return _mudar(EstadoSessao.trocarSenha);
    final ids = [for (final e in empresas) e['id'] as String];
    final lembrada = _prefs.getString(_chaveEmpresa);
    if (lembrada != null && ids.contains(lembrada)) {
      api.empresaId = lembrada;
      return _mudar(EstadoSessao.pronta);
    }
    if (ids.length == 1) {
      api.empresaId = ids.single;
      return _mudar(EstadoSessao.pronta);
    }
    _mudar(EstadoSessao.escolherEmpresa);
  }

  void _mudar(EstadoSessao novo) {
    estado = novo;
    notifyListeners();
  }
}

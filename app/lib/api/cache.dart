import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class RespostaCache {
  const RespostaCache(this.dados, this.deCache, this.quando);
  final dynamic dados;
  final bool deCache;
  final DateTime quando;
}

/// Última resposta das telas principais, para mostrar sem conexão ("dados de HH:MM").
// shortcut: cache em shared_preferences; trocar por arquivo se passar de ~1 MB por chave.
class CacheLeitura {
  CacheLeitura(this._prefs, {bool? persistir}) : persistir = persistir ?? !kIsWeb;

  final SharedPreferences _prefs;
  final bool persistir; // no navegador só memória
  final _memoria = <String, RespostaCache>{};

  Future<RespostaCache> obter(String chave, Future<dynamic> Function() buscar) async {
    try {
      final r = RespostaCache(await buscar(), false, DateTime.now());
      _memoria[chave] = r;
      if (persistir) {
        await _prefs.setString('cache_v1:$chave', jsonEncode({'quando': r.quando.toIso8601String(), 'dados': r.dados}));
      }
      return r;
    } on ErroApi catch (e) {
      final velho = ultimo(chave);
      if (!e.temporario || velho == null) rethrow;
      return RespostaCache(velho.dados, true, velho.quando);
    }
  }

  /// Último dado guardado, sem ir à rede (ex.: calculadora offline).
  RespostaCache? ultimo(String chave) {
    final m = _memoria[chave];
    if (m != null) return m;
    final s = persistir ? _prefs.getString('cache_v1:$chave') : null;
    if (s == null) return null;
    final j = jsonDecode(s) as Map;
    return RespostaCache(j['dados'], true, DateTime.parse(j['quando'] as String));
  }
}

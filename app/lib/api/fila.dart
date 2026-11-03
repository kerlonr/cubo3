import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'modelos.dart';

class Operacao {
  Operacao(this.id, this.metodo, this.caminho, this.corpo, this.criadaEm, {this.empresa, this.versaoBase});

  /// [versaoBase] = `atualizado_em` lido do servidor antes de editar (só em edição; criação não tem).
  Operacao.nova(this.metodo, this.caminho, [this.corpo, this.versaoBase])
      : id = novoId(),
        criadaEm = DateTime.now().toUtc();

  factory Operacao.fromJson(Map j) => Operacao(j['id'] as String, j['metodo'] as String, j['caminho'] as String,
      j['corpo'] as Map?, DateTime.parse(j['criadaEm'] as String),
      empresa: j['empresa'] as String?, versaoBase: j['versaoBase'] as String?);

  final String id, metodo, caminho;
  final Map? corpo;
  final DateTime criadaEm;
  final String? versaoBase;

  /// Empresa em que foi feita: a fila manda para ela mesmo que o usuário troque de empresa antes.
  String? empresa;

  Map<String, dynamic> toJson() => {
        'id': id,
        'metodo': metodo,
        'caminho': caminho,
        'corpo': corpo,
        'criadaEm': criadaEm.toUtc().toIso8601String(),
        'empresa': empresa,
        'versaoBase': versaoBase,
      };
}

class ErroFila {
  ErroFila(this.operacao, this.mensagem);

  factory ErroFila.fromJson(Map j) => ErroFila(Operacao.fromJson(j['operacao'] as Map), j['mensagem'] as String);

  final Operacao operacao;
  final String mensagem;

  Map<String, dynamic> toJson() => {'operacao': operacao.toJson(), 'mensagem': mensagem};
}

class ResultadoEnvio {
  const ResultadoEnvio(this.guardada, [this.resposta]);

  /// true = sem conexão; ficou no aparelho e vai quando a rede voltar.
  final bool guardada;
  final dynamic resposta;
}

/// Fila local de escritas (só Android; no navegador o app é só online).
/// Toda criação usa id gerado no aparelho, então reenviar não duplica nada no servidor.
class FilaOffline extends ChangeNotifier {
  FilaOffline(this.api, this._prefs, {bool? guardaOffline}) : guardaOffline = guardaOffline ?? !kIsWeb {
    _ops.addAll([for (final j in _ler(_chave)) Operacao.fromJson(j)]);
    erros.addAll([for (final j in _ler(_chaveErros)) ErroFila.fromJson(j)]);
  }

  static const _chave = 'fila_v1';
  static const _chaveErros = 'fila_erros_v1';

  final ApiCliente api;
  final SharedPreferences _prefs;
  final bool guardaOffline;
  final _ops = <Operacao>[];
  final List<ErroFila> erros = [];
  Future<void>? _esvaziando;
  Timer? _timer;

  int get pendentes => _ops.length;

  List<Map> _ler(String chave) => [for (final e in jsonDecode(_prefs.getString(chave) ?? '[]') as List) e as Map];

  Future<void> _gravar() async {
    await _prefs.setString(_chave, jsonEncode([for (final o in _ops) o.toJson()]));
    await _prefs.setString(_chaveErros, jsonEncode([for (final e in erros) e.toJson()]));
    notifyListeners();
  }

  Future<dynamic> _enviar(Operacao op) => api.enviar(op.metodo, op.caminho, corpo: op.corpo, extra: {
        'X-Empresa': ?op.empresa,
        // O servidor recusa com 409 se o registro mudou depois desta versão (edição de outra pessoa).
        'X-Versao-Base': ?op.versaoBase,
      });

  /// Tenta enviar já. Sem conexão (ou servidor fora) guarda; erro definitivo sobe para a tela.
  Future<ResultadoEnvio> enviarOuGuardar(Operacao op) async {
    op.empresa ??= api.empresaId;
    if (_ops.isNotEmpty) {
      // Já há pendências: entra atrás delas para não furar a ordem (carretel antes do movimento).
      _ops.add(op);
      await _gravar();
      await esvaziar();
      return ResultadoEnvio(_ops.contains(op));
    }
    try {
      return ResultadoEnvio(false, await _enviar(op));
    } on ErroApi catch (e) {
      if (!e.temporario || !guardaOffline) rethrow;
      _ops.add(op);
      await _gravar();
      return const ResultadoEnvio(true);
    }
  }

  /// Envia em ordem; para no primeiro erro de rede/5xx ou sessão expirada.
  Future<void> esvaziar() => _esvaziando ??= _esvaziar().whenComplete(() => _esvaziando = null);

  Future<void> _esvaziar() async {
    while (_ops.isNotEmpty) {
      final op = _ops.first;
      try {
        await _enviar(op);
      } on ErroApi catch (e) {
        if (e.temporario || e.status == 401) return;
        erros.add(ErroFila(op, e.mensagem)); // 404/409/422...: reenviar não adianta
      }
      _ops.removeAt(0);
      await _gravar();
    }
  }

  Future<void> limparErros() async {
    erros.clear();
    await _gravar();
  }

  /// Tenta a cada 30 s enquanto houver pendência.
  void iniciarTentativas() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (_ops.isNotEmpty) esvaziar();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

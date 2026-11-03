import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'modelos.dart';

/// Avisa as telas abertas que algo foi gravado no servidor (abas no IndexedStack recarregam sozinhas).
final dadosMudaram = ValueNotifier<int>(0);

class Operacao {
  Operacao(this.id, this.metodo, this.caminho, this.corpo, this.criadaEm,
      {this.empresa, this.versaoBase, this.tentativas = 0, this.proximaTentativa});

  /// [versaoBase] = `atualizado_em` lido do servidor antes de editar (só em edição; criação não tem).
  Operacao.nova(this.metodo, this.caminho, [this.corpo, this.versaoBase])
      : id = novoId(),
        criadaEm = DateTime.now().toUtc();

  factory Operacao.fromJson(Map j) => Operacao(j['id'] as String, j['metodo'] as String, j['caminho'] as String,
      j['corpo'] as Map?, DateTime.parse(j['criadaEm'] as String),
      empresa: j['empresa'] as String?,
      versaoBase: j['versaoBase'] as String?,
      tentativas: j['tentativas'] as int? ?? 0,
      proximaTentativa: DateTime.tryParse(j['proximaTentativa'] as String? ?? ''));

  final String id, metodo, caminho;
  final Map? corpo;
  final DateTime criadaEm;

  /// Muda quando uma edição anterior do mesmo registro, feita neste aparelho, chega antes (ver _esvaziar).
  String? versaoBase;

  /// Tentativas com erro 500 (bug no servidor para esta operação, não servidor fora).
  int tentativas = 0;

  /// Depois de um 500, a fila só reenvia a partir daqui (espera crescente, ver FilaOffline.esperas500).
  DateTime? proximaTentativa;

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
        'tentativas': tentativas,
        'proximaTentativa': proximaTentativa?.toUtc().toIso8601String(),
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
  const ResultadoEnvio(this.guardada, [this.resposta, this.recusada]);

  /// true = sem conexão; ficou no aparelho e vai quando a rede voltar.
  final bool guardada;
  final dynamic resposta;

  /// Mensagem do servidor quando recusou (404/409/422...). Só vem aqui se havia pendências na frente;
  /// com a fila vazia o erro sobe como ErroApi.
  final String? recusada;
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

  /// Espera depois da 1ª, 2ª, 3ª e 4ª tentativa com 500; na 5ª a operação vai para os erros e a fila segue.
  /// Espaçadas: um 500 passageiro (banco reiniciando) não descarta nada.
  static const esperas500 = [Duration(seconds: 30), Duration(minutes: 2), Duration(minutes: 10), Duration(minutes: 10)];
  static const maxTentativas500 = 5;

  /// Relógio da espera depois de 500 (os testes avançam o tempo).
  DateTime Function() relogio = DateTime.now;

  int get pendentes => _ops.length;

  List<Operacao> get operacoes => List.unmodifiable(_ops);

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
      final erro = erros.where((e) => e.operacao == op).firstOrNull;
      if (erro == null) return ResultadoEnvio(_ops.contains(op));
      erros.remove(erro); // a tela mostra a mensagem; não repete na lista de erros
      await _gravar();
      return ResultadoEnvio(false, null, erro.mensagem);
    }
    try {
      return ResultadoEnvio(false, await _enviar(op));
    } on ErroApi catch (e) {
      if (!e.temporario || !guardaOffline) rethrow;
      if (e.status == 500) _falhou500(op);
      _ops.add(op);
      await _gravar();
      return const ResultadoEnvio(true);
    }
  }

  /// Conta o 500 e marca quando tentar de novo. false = já esgotou as tentativas.
  bool _falhou500(Operacao op) {
    if (++op.tentativas >= maxTentativas500) return false;
    op.proximaTentativa = relogio().add(esperas500[op.tentativas - 1]);
    return true;
  }

  /// Envia em ordem; para no primeiro erro de rede/502-504 ou sessão expirada. A operação esperando depois
  /// de um 500 fica onde está e as seguintes vão: um 500 fixo não prende a venda de agora.
  /// [forcar] (botão "Enviar agora") não espera o prazo depois de um 500.
  Future<void> esvaziar({bool forcar = false}) =>
      _esvaziando ??= _esvaziar(forcar).whenComplete(() => _esvaziando = null);

  Future<void> _esvaziar(bool forcar) async {
    var enviou = false;
    try {
      var i = 0;
      while (i < _ops.length) {
        final op = _ops[i];
        final prazo = op.proximaTentativa;
        if (!forcar && prazo != null && relogio().isBefore(prazo)) {
          i++;
          continue;
        }
        try {
          final resposta = await _enviar(op);
          enviou = true;
          // Outras edições do mesmo registro feitas sem rede leram a mesma versão: agora partem desta,
          // senão o servidor veria a 2ª como conflito com "outra pessoa" (foi este aparelho).
          final nova = resposta is Map ? resposta['atualizado_em'] : null;
          if (op.versaoBase != null && nova is String) {
            for (final o in _ops) {
              if (o != op && o.caminho == op.caminho && o.versaoBase == op.versaoBase) o.versaoBase = nova;
            }
          }
        } on ErroApi catch (e) {
          // 500 é bug do servidor com esta operação (ou ele reiniciando): tenta de novo mais tarde, espaçado;
          // depois de 5, vai para os erros. 502/503/504 e sem rede são servidor fora: esperam sem limite.
          if (e.status == 500 && _falhou500(op)) {
            await _gravar();
            i++;
            continue;
          }
          if (e.status != 500 && (e.temporario || e.status == 401)) return;
          erros.add(ErroFila(op, e.mensagem)); // 404/409/422...: reenviar não adianta
        }
        _ops.remove(op); // não removeAt(i): a operação pode ter sido descartada enquanto ia
        await _gravar();
      }
    } finally {
      if (enviou) dadosMudaram.value++;
    }
  }

  /// Tira uma pendência da fila sem enviar (o usuário confirmou na tela).
  Future<void> descartar(Operacao op) async {
    _ops.remove(op);
    await _gravar();
  }

  /// Devolve uma operação recusada para o fim da fila, com as tentativas zeradas, e tenta enviar.
  Future<void> tentarDeNovo(ErroFila erro) async {
    erros.remove(erro);
    _ops.add(erro.operacao
      ..tentativas = 0
      ..proximaTentativa = null);
    await _gravar();
    await esvaziar(forcar: true);
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

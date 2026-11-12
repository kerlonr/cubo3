import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api.dart';
import '../api/modelos.dart';
import '../util/formatos.dart';

/// Conexão aberta: o que chega, como mandar texto e como fechar.
typedef ConexaoAoVivo = ({Stream<dynamic> stream, void Function(String) enviar, Future<void> Function() fechar});
typedef Conectar = ConexaoAoVivo Function(Uri url);

ConexaoAoVivo conectarWebSocket(Uri url) {
  final c = WebSocketChannel.connect(url);
  return (stream: c.stream, enviar: c.sink.add, fechar: () async => c.sink.close());
}

class EstadoImpressora {
  EstadoImpressora(this.dados);
  final Map dados;

  String? get estado => dados['estado'] as String?;
  String? get arquivo => dados['arquivo'] as String?;
  double? get progresso => numOu(dados['progresso']);
  double? get restanteS => numOu(dados['restante_s']);
  bool get imprimindo => estado == 'printing' || estado == 'paused';
}

/// "choinka_PLA_3h11m.gcode" → "choinka PLA 3h11m".
String nomePeca(String? arquivo) => (arquivo ?? '')
    .split('/')
    .last
    .replaceAll(RegExp(r'\.gcode$', caseSensitive: false), '')
    .replaceAll('_', ' ')
    .trim();

/// "Bico 210° · Mesa 60°" (como o Mobileraker).
String textoTemperaturas(EstadoImpressora? e) => [
      if (e?.dados['bico'] != null) 'Bico ${num0(e!.dados['bico']).round()}°',
      if (e?.dados['mesa'] != null) 'Mesa ${num0(e!.dados['mesa']).round()}°',
    ].join(' · ');

/// O que a notificação fixa mostra: título e linha curtas; [linhas] aparecem ao puxar para baixo.
class ConteudoNotificacao {
  const ConteudoNotificacao(
      {required this.titulo, required this.corpo, this.linhas = const [], this.progresso, this.terminaEm, this.ativa = false});
  final String titulo, corpo;
  final List<String> linhas;
  final double? progresso;

  /// Hora prevista do fim (só imprimindo): vira a contagem regressiva ao vivo da notificação.
  final DateTime? terminaEm;
  final bool ativa;
}

ConteudoNotificacao conteudoNotificacao(EstadoImpressora? e, DateTime agora) {
  final temps = textoTemperaturas(e);
  if (e == null || !e.imprimindo) {
    return ConteudoNotificacao(
        titulo: 'Cubo³', corpo: ['Nenhuma impressão agora', if (temps.isNotEmpty) temps].join(' · '));
  }
  final d = e.dados;
  final pausada = e.estado == 'paused';
  final pct = '${((e.progresso ?? 0) * 100).round()}%';
  final fim = pausada || e.restanteS == null ? null : agora.add(Duration(seconds: e.restanteS!.round()));
  final hora = fim == null ? null : DateFormat('HH:mm').format(fim);
  String alvo(String r, String atual, String meta) =>
      d[atual] == null ? '' : '$r ${num0(d[atual]).round()}${num0(d[meta]) > 0 ? '/${num0(d[meta]).round()}' : ''} °C';
  final linhas = [
    [pct, if (d['camada'] != null) 'camada ${d['camada']}${d['camadas'] != null ? ' de ${d['camadas']}' : ''}'].join(' · '),
    if (hora != null) 'Termina às $hora (faltam ${duracao(e.restanteS!)})',
    if (pausada) 'Pausada: toque para abrir a impressora',
    [alvo('Bico', 'bico', 'bico_alvo'), alvo('Mesa', 'mesa', 'mesa_alvo')].where((x) => x.isNotEmpty).join(' · '),
    [
      if (d['velocidade_pct'] != null) 'Velocidade ${num0(d['velocidade_pct']).round()}%',
      if (d['ventoinha_pct'] != null) 'Ventoinha ${num0(d['ventoinha_pct']).round()}%',
    ].join(' · '),
  ].where((x) => x.isNotEmpty).toList();
  return ConteudoNotificacao(
    titulo: '${pausada ? 'Pausada' : 'Imprimindo'} · ${nomePeca(e.arquivo)}',
    corpo: [pct, if (hora != null) 'termina às $hora' else if (temps.isNotEmpty) temps].join(' · '),
    linhas: linhas,
    progresso: e.progresso,
    terminaEm: fim,
    ativa: true,
  );
}

/// Alerta de fim de impressão.
({String titulo, String corpo}) alertaFim(Map evento) {
  final nome = nomePeca('${evento['arquivo'] ?? ''}');
  if (evento['situacao'] == 'completed') return (titulo: 'Terminou: $nome', corpo: 'Toque para confirmar os gramas');
  return (titulo: 'Parou: $nome', corpo: 'A impressão não terminou. Toque para registrar');
}

/// WebSocket `/api/ao-vivo` da empresa: estado das impressoras e fim de impressão.
/// Reconecta sozinho (2 s → 60 s), renovando o token antes; manda "ping" a cada 30 s.
class CanalAoVivo extends ChangeNotifier {
  CanalAoVivo(this.api, {Conectar? conectar, this.esperaInicial = const Duration(seconds: 2)})
      : _conectar = conectar ?? conectarWebSocket;

  final ApiCliente api;
  final Conectar _conectar;
  final Duration esperaInicial;
  final Map<String, EstadoImpressora> estados = {};
  final _eventos = StreamController<Map>.broadcast();
  Stream<Map> get eventos => _eventos.stream;

  ConexaoAoVivo? _conexao;
  StreamSubscription<dynamic>? _assinatura;
  Timer? _ping, _volta;
  bool _ativo = false;
  int _falhas = 0;
  String? _empresa;

  bool get ativo => _ativo;

  Uri get url {
    final b = api.base;
    return b.replace(
      scheme: b.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/ao-vivo',
      queryParameters: {'token': api.tokenAcesso ?? '', 'empresa': api.empresaId ?? ''},
    );
  }

  /// Liga (ou religa, se a empresa mudou).
  void iniciar() {
    if (_ativo && _empresa == api.empresaId) return;
    parar();
    _ativo = true;
    _empresa = api.empresaId;
    _abrir();
  }

  void parar() {
    _ativo = false;
    _ping?.cancel();
    _volta?.cancel();
    _assinatura?.cancel();
    _conexao?.fechar();
    _conexao = null;
    estados.clear();
  }

  Future<void> _abrir() async {
    if (!_ativo) return;
    if (_falhas > 0) {
      try {
        await api.renovar(); // o acesso dura 30 min; a queda pode ter sido token vencido
      } catch (_) {
        // Sem rede: tenta conectar assim mesmo e cai na próxima espera.
      }
      if (!_ativo) return;
    }
    try {
      _conexao = _conectar(url);
    } catch (_) {
      return _agendar();
    }
    _assinatura = _conexao!.stream.listen(_receber, onError: (_) => _agendar(), onDone: _agendar, cancelOnError: true);
    _ping = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        _conexao?.enviar('ping');
      } catch (_) {}
    });
  }

  void _receber(dynamic bruto) {
    _falhas = 0;
    final Map ev;
    try {
      ev = jsonDecode('$bruto') as Map;
    } catch (_) {
      return;
    }
    if (ev['tipo'] == 'estado' && ev['impressora_id'] != null) {
      estados['${ev['impressora_id']}'] = EstadoImpressora(ev);
      notifyListeners();
    }
    _eventos.add(ev);
  }

  void _agendar() {
    _ping?.cancel();
    _assinatura?.cancel();
    _conexao = null;
    if (!_ativo) return;
    final espera = esperaInicial * (1 << _falhas.clamp(0, 5));
    _falhas++;
    _volta?.cancel();
    _volta = Timer(espera > const Duration(seconds: 60) ? const Duration(seconds: 60) : espera, _abrir);
  }

  @override
  void dispose() {
    parar();
    _eventos.close();
    super.dispose();
  }
}

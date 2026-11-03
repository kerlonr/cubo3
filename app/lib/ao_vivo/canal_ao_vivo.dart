import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

/// "Imprimindo vaso.gcode — 45% — faltam 1h12" ou, ociosa, "Cubo³ monitorando".
String textoProgresso(EstadoImpressora? e) {
  if (e == null || !e.imprimindo) return 'Cubo³ monitorando';
  return [
    '${e.estado == 'paused' ? 'Pausada' : 'Imprimindo'} ${e.arquivo ?? ''}'.trim(),
    '${((e.progresso ?? 0) * 100).round()}%',
    if (e.restanteS != null) 'faltam ${duracao(e.restanteS!)}',
  ].join(' — ');
}

/// "Bico 210° · Mesa 60°" (como o Mobileraker).
String textoTemperaturas(EstadoImpressora? e) => [
      if (e?.dados['bico'] != null) 'Bico ${num0(e!.dados['bico']).round()}°',
      if (e?.dados['mesa'] != null) 'Mesa ${num0(e!.dados['mesa']).round()}°',
    ].join(' · ');

/// Barra de progresso em texto para a notificação fixa (10 blocos).
String barraTexto(double fracao) {
  final cheios = (fracao.clamp(0, 1) * 10).floor(); // bloco só enche quando a fração é atingida
  return '${'▰' * cheios}${'▱' * (10 - cheios)}';
}

/// Alerta de fim de impressão.
({String titulo, String corpo}) alertaFim(Map evento) {
  final arquivo = '${evento['arquivo'] ?? ''}';
  if (evento['situacao'] == 'completed') return (titulo: 'Impressão terminou: $arquivo', corpo: 'Toque para confirmar');
  return (titulo: 'Impressão parou', corpo: '$arquivo — toque para registrar');
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

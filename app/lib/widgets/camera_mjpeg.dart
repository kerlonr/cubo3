import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/controle.dart';
import 'camera_mjpeg_io.dart' if (dart.library.js_interop) 'camera_mjpeg_web.dart';

/// Quadros JPEG de um MJPEG: cada um vai do marcador FFD8 ao FFD9; o resto (cabeçalhos das partes) é descartado.
/// Transformer (e não async*): cancelar chega à origem na hora, mesmo com a câmera parada.
Stream<Uint8List> quadrosMjpeg(Stream<List<int>> bytes) {
  var b = <int>[];
  var inicio = -1; // FFD8 do quadro em curso
  var i = 0; // próximo byte a examinar
  return bytes.transform(StreamTransformer.fromHandlers(handleData: (pedaco, saida) {
    b.addAll(pedaco);
    for (; i + 1 < b.length; i++) {
      if (b[i] != 0xFF) continue;
      if (inicio < 0) {
        if (b[i + 1] == 0xD8) {
          inicio = i;
          i++; // pula o D8
        }
      } else if (b[i + 1] == 0xD9) {
        saida.add(Uint8List.fromList(b.sublist(inicio, i + 2)));
        b = b.sublist(i + 2);
        inicio = -1;
        i = -1;
      }
    }
    final corte = inicio < 0 ? i : inicio;
    b = b.sublist(corte);
    i -= corte;
    if (inicio >= 0) inicio = 0;
    if (b.length > 16 << 20) {
      // Quadro sem fim (stream corrompido): descarta e recomeça em vez de crescer sem limite.
      b = [];
      i = 0;
      inicio = -1;
    }
  }));
}

/// Vídeo da câmera em quadros. Cancelar a assinatura fecha a conexão na hora (economia de 4G).
Stream<Uint8List> videoMjpeg(Uri url, http.Client cliente) {
  StreamSubscription<Uint8List>? quadros;
  late final StreamController<Uint8List> saida;
  saida = StreamController(
    onListen: () async {
      try {
        final r = await cliente.send(http.Request('GET', url));
        if (r.statusCode != 200) throw ErroApi(r.statusCode, 'Câmera indisponível');
        if (!saida.hasListener) return; // a tela fechou enquanto conectava
        quadros = quadrosMjpeg(r.stream).listen(saida.add, onError: saida.addError, onDone: saida.close);
      } catch (e) {
        if (saida.hasListener) saida.addError(e);
        saida.close();
      }
    },
    onCancel: () {
      quadros?.cancel();
      cliente.close();
    },
  );
  return saida.stream;
}

/// Câmera ao vivo da impressora. Pede um link novo a cada abertura; toque abre em tela cheia.
class CameraAoVivo extends StatefulWidget {
  const CameraAoVivo({super.key, required this.impressoraId, this.telaCheia = false});
  final String impressoraId;
  final bool telaCheia;

  @override
  State<CameraAoVivo> createState() => _CameraAoVivoState();
}

class _CameraAoVivoState extends State<CameraAoVivo> {
  Uri? _url;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  Future<void> _abrir() async {
    setState(() {
      _url = null;
      _erro = null;
    });
    try {
      final url = await linkCamera(context.read<ApiCliente>(), widget.impressoraId);
      if (mounted) setState(() => _url = url);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.status == 404 ? 'Sem câmera' : 'Câmera indisponível — toque para tentar de novo');
    }
  }

  void _falhou() {
    if (mounted) setState(() => _erro = 'Câmera indisponível — toque para tentar de novo');
  }

  Future<void> _tocar() async {
    if (_erro != null) return _abrir();
    if (widget.telaCheia) return Navigator.pop(context);
    // Fecha o vídeo daqui enquanto a tela cheia abre o dela: uma conexão por vez.
    setState(() => _url = null);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(child: CameraAoVivo(impressoraId: widget.impressoraId, telaCheia: true)),
        ),
      ),
    );
    if (mounted) _abrir();
  }

  @override
  Widget build(BuildContext context) {
    final conteudo = Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Stack(fit: StackFit.expand, children: [
        if (_erro != null)
          Center(child: Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))
        else if (_url == null)
          const Center(child: CircularProgressIndicator())
        else
          VideoMjpeg(key: ValueKey(_url), url: _url!, aoFalhar: _falhou),
        // Por cima do vídeo: no navegador o <img> engoliria o toque.
        GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tocar),
      ]),
    );
    if (widget.telaCheia) return conteudo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(aspectRatio: 16 / 9, child: conteudo),
    );
  }
}

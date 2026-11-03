import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'camera_mjpeg.dart';

/// Android: lê o MJPEG e desenha quadro a quadro. Sair da tela cancela a assinatura e fecha a conexão.
class VideoMjpeg extends StatefulWidget {
  const VideoMjpeg({super.key, required this.url, required this.aoFalhar});
  final Uri url;
  final VoidCallback aoFalhar;

  @override
  State<VideoMjpeg> createState() => _VideoMjpegState();
}

class _VideoMjpegState extends State<VideoMjpeg> {
  StreamSubscription<Uint8List>? _assinatura;
  Uint8List? _quadro;

  @override
  void initState() {
    super.initState();
    _assinatura = videoMjpeg(widget.url, http.Client()).listen(
      (q) => setState(() => _quadro = q),
      onError: (_) => widget.aoFalhar(),
      onDone: widget.aoFalhar, // a câmera não para sozinha: fim do stream é queda
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _assinatura?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_quadro == null) return const Center(child: CircularProgressIndicator());
    return Image.memory(_quadro!, gaplessPlayback: true, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox());
  }
}

import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Navegador: o próprio <img> toca o MJPEG (o link assinado dispensa o cabeçalho de login).
class VideoMjpeg extends StatefulWidget {
  const VideoMjpeg({super.key, required this.url, required this.aoFalhar});
  final Uri url;
  final VoidCallback aoFalhar;

  @override
  State<VideoMjpeg> createState() => _VideoMjpegState();
}

class _VideoMjpegState extends State<VideoMjpeg> {
  web.HTMLImageElement? _img;
  late final JSFunction _erro = ((web.Event _) => widget.aoFalhar()).toJS;

  @override
  void dispose() {
    // Remover o elemento não basta: o navegador segue baixando o stream até a origem mudar.
    _img?.removeEventListener('error', _erro);
    _img?.src = 'data:,';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'img',
        onElementCreated: (e) {
          final img = (e as web.HTMLImageElement)
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain'
            ..style.pointerEvents = 'none';
          img.addEventListener('error', _erro);
          img.src = widget.url.toString();
          _img = img;
        },
      );
}

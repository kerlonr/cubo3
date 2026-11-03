import 'package:flutter/foundation.dart';

/// Servidor de produção. No navegador o app é servido pelo próprio servidor, então usa a mesma origem.
const servidorPadrao = 'https://cubo3.kerlonr.com.br';

Uri baseInicial([String? salvo]) {
  if (salvo != null && salvo.isNotEmpty) return Uri.parse(salvo);
  return kIsWeb ? Uri.parse(Uri.base.origin) : Uri.parse(servidorPadrao);
}

/// Limite do túnel Cloudflare gratuito (100 MB) com folga.
const limiteUploadBytes = 95 * 1024 * 1024;

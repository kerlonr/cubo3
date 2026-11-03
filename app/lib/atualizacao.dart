import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api/api.dart';
import 'api/modelos.dart';

/// Resposta de `GET /api/versao` com build maior que o instalado.
bool precisaAtualizar({required int buildApp, Map? resposta}) => resposta != null && num0(resposta['build']) > buildApp;

/// Pergunta ao servidor. Sem versão publicada (404) ou sem rede: nada a fazer.
Future<bool> consultarAtualizacao(ApiCliente api, {required int buildApp}) async {
  try {
    return precisaAtualizar(buildApp: buildApp, resposta: mapa(await api.get('/api/versao')));
  } on ErroApi {
    return false;
  }
}

/// Faixa "Nova versão do Cubo³ — Atualizar" (só Android; o navegador já roda a versão do servidor).
class FaixaAtualizacao extends StatefulWidget {
  const FaixaAtualizacao({super.key});

  @override
  State<FaixaAtualizacao> createState() => _FaixaAtualizacaoState();
}

class _FaixaAtualizacaoState extends State<FaixaAtualizacao> {
  bool _nova = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _verificar();
  }

  Future<void> _verificar() async {
    final api = context.read<ApiCliente>();
    try {
      final info = await PackageInfo.fromPlatform();
      final nova = await consultarAtualizacao(api, buildApp: int.tryParse(info.buildNumber) ?? 0);
      if (mounted) setState(() => _nova = nova);
    } catch (_) {
      // Plataforma sem versão (testes): segue sem faixa.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_nova) return const SizedBox.shrink();
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.primary,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.system_update, color: Colors.white),
          title: const Text('Nova versão do Cubo³', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          trailing: TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => launchUrl(context.read<ApiCliente>().url('/baixar'), mode: LaunchMode.externalApplication),
            child: const Text('Atualizar'),
          ),
        ),
      ),
    );
  }
}

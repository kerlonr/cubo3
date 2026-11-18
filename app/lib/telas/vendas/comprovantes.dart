import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../config.dart';
import '../../tema.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';

/// Mesma lista do servidor (`TIPOS_ANEXO` em `server/app/vendas/rotas.py`).
const extensoesComprovante = ['png', 'jpg', 'jpeg', 'webp', 'pdf'];

/// Mensagem de recusa, ou null se pode enviar.
String? validarComprovante(String nome, int tamanho) {
  if (tamanho > limiteUploadBytes) return 'Arquivo maior que 95 MB';
  final ponto = nome.lastIndexOf('.');
  if (ponto < 0 || !extensoesComprovante.contains(nome.substring(ponto + 1).toLowerCase())) {
    return 'Comprovante precisa ser foto ou PDF';
  }
  return null;
}

/// Envia um comprovante (só online, como os arquivos do modelo). Devolve o id do anexo (null = não anexou).
Future<String?> enviarComprovante(
    BuildContext context, String pedidoId, String nome, int tamanho, Stream<List<int>> bytes) async {
  final recusa = validarComprovante(nome, tamanho);
  if (recusa != null) {
    avisar(context, '$nome: $recusa', erro: true);
    return null;
  }
  final api = context.read<ApiCliente>();
  avisar(context, 'Enviando $nome…');
  try {
    final r = await api.enviarArquivo('/api/pedidos/$pedidoId/anexos', nome: nome, bytes: bytes, tamanho: tamanho);
    if (context.mounted) avisar(context, 'Comprovante anexado');
    return '${mapa(r)['id']}';
  } catch (e) {
    if (context.mounted) avisarErro(context, e);
    return null;
  }
}

/// Seletor de arquivos (galeria/arquivos no celular). Devolve o id do último anexado (null = nenhum).
Future<String?> escolherComprovante(BuildContext context, String pedidoId) async {
  final arquivos = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensoesComprovante);
  String? ultimo;
  for (final f in arquivos) {
    final tamanho = await f.length() ?? 0;
    if (!context.mounted) break;
    ultimo = await enviarComprovante(context, pedidoId, f.name, tamanho, f.readAsByteStream()) ?? ultimo;
  }
  return ultimo;
}

/// O GET do comprovante pede o token (não há link de 10 minutos como nos arquivos do modelo):
/// baixa aqui e entrega ao compartilhar do sistema (no navegador, vira download).
Future<void> _baixar(BuildContext context, Map a) async {
  final api = context.read<ApiCliente>();
  final nome = '${a['nome_original']}';
  try {
    final r = await http.get(api.url('${a['url']}'), headers: api.cabecalhosAuth);
    if (r.statusCode >= 400) throw ErroApi.daResposta(r.statusCode, r.bodyBytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(r.bodyBytes, mimeType: 'application/pdf', name: nome)],
      fileNameOverrides: [nome],
    ));
  } catch (e) {
    if (context.mounted) avisarErro(context, e);
  }
}

/// Comprovantes de pagamento do pedido: miniaturas, abrir, apagar e anexar (clipe; arrastar no navegador).
class Comprovantes extends StatelessWidget {
  const Comprovantes(
      {super.key, required this.pedidoId, required this.anexos, required this.aoMudar, this.somenteLeitura = false});
  final String pedidoId;
  final List<Json> anexos;
  final VoidCallback aoMudar;

  /// Venda bloqueada: dá para ver e baixar, não para anexar nem apagar.
  final bool somenteLeitura;

  Future<void> _apagar(BuildContext context, Map a) async {
    if (!await confirmar(context, 'Apagar comprovante?', '${a['nome_original']} sai do pedido.',
        sim: 'Apagar', cor: vermelho)) {
      return;
    }
    if (context.mounted && await salvar(context, 'DELETE', '/api/anexos/${a['id']}', {}, feito: 'Comprovante apagado')) {
      aoMudar();
    }
  }

  void _abrir(BuildContext context, Map a) {
    if (a['tipo'] != 'foto') {
      _baixar(context, a);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${a['nome_original']}')),
          body: InteractiveViewer(
              maxScale: 6, child: SizedBox.expand(child: ImagemApi('${a['url']}', ajuste: BoxFit.contain))),
        ),
      ),
    );
  }

  Widget _miniatura(BuildContext context, Json a) {
    final t = Theme.of(context);
    final nome = '${a['nome_original']}';
    return SizedBox(
      key: ValueKey('anexo-${a['id']}'),
      width: 84,
      height: 84,
      child: Stack(children: [
        Positioned.fill(
          child: Material(
            color: t.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Tooltip(
              message: nome,
              child: InkWell(
                onTap: () => _abrir(context, a),
                child: a['tipo'] == 'foto'
                    ? ImagemApi('${a['url']}')
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.picture_as_pdf_outlined, size: 32, color: t.colorScheme.primary),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        ),
                      ]),
              ),
            ),
          ),
        ),
        if (!somenteLeitura)
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: 'Apagar comprovante',
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(backgroundColor: t.colorScheme.surface.withValues(alpha: 0.85)),
              onPressed: () => _apagar(context, a),
              icon: const Icon(Icons.close),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conteudo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Secao('Comprovantes',
          acao: somenteLeitura
              ? null
              : IconButton(
                  tooltip: 'Anexar comprovante (foto ou PDF)',
                  icon: const Icon(Icons.attach_file),
                  onPressed: () async {
                    if (await escolherComprovante(context, pedidoId) != null) aoMudar();
                  },
                )),
      if (anexos.isEmpty)
        Text(
            somenteLeitura
                ? 'Nenhum comprovante.'
                : kIsWeb
                    ? 'Nenhum. Toque no clipe ou arraste a foto/PDF aqui.'
                    : 'Nenhum. Toque no clipe para anexar.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))
      else
        Wrap(spacing: 8, runSpacing: 8, children: [for (final a in anexos) _miniatura(context, a)]),
    ]);
    if (!kIsWeb || somenteLeitura) return conteudo;
    return DropTarget(
      onDragDone: (d) async {
        var algum = false;
        for (final f in d.files) {
          final tamanho = await f.length();
          if (!context.mounted) return;
          algum = await enviarComprovante(context, pedidoId, f.name, tamanho, f.openRead()) != null || algum;
        }
        if (algum) aoMudar();
      },
      child: conteudo,
    );
  }
}

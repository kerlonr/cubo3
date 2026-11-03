import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../config.dart';
import '../../util/formatos.dart';
import '../../widgets/estado_tela.dart';

/// Mesma lista do servidor (`server/app/catalogo/arquivos.py`).
const extensoesAceitas = {'stl', '3mf', 'gcode', 'obj', 'step', 'stp', 'png', 'jpg', 'jpeg', 'webp'};

/// Mensagem de recusa, ou null se pode enviar.
String? validarArquivo(String nome, int tamanho) {
  if (tamanho > limiteUploadBytes) return 'Arquivo maior que 95 MB';
  final ponto = nome.lastIndexOf('.');
  if (ponto < 0 || !extensoesAceitas.contains(nome.substring(ponto + 1).toLowerCase())) {
    return 'Tipo de arquivo não aceito';
  }
  return null;
}

/// Confere antes de enviar (o túnel recusaria só depois de subir tudo) e acompanha o progresso.
Future<dynamic> enviarArquivoModelo(ApiCliente api, String modeloId,
    {required String nome,
    required int tamanho,
    required Stream<List<int>> bytes,
    void Function(double fracao)? aoProgresso}) async {
  final recusa = validarArquivo(nome, tamanho);
  if (recusa != null) throw ErroApi(recusa.startsWith('Arquivo') ? 413 : 415, recusa);
  var enviados = 0;
  final contando = bytes.map((b) {
    enviados += b.length;
    aoProgresso?.call(tamanho == 0 ? 1 : enviados / tamanho);
    return b;
  });
  return api.enviarArquivo('/api/modelos/$modeloId/arquivos', nome: nome, bytes: contando, tamanho: tamanho);
}

/// Baixa pelo link de 10 minutos (o navegador/gerenciador de downloads não manda o token).
Future<void> baixarArquivo(BuildContext context, Json arquivo) async {
  final api = context.read<ApiCliente>();
  try {
    final r = mapa(await api.post('/api/arquivos/${arquivo['id']}/link'));
    await launchUrl(api.url(r['url'] as String), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) avisarErro(context, e);
  }
}

IconData iconeArquivo(String? tipo) => switch (tipo) {
      'foto' => Icons.image_outlined,
      'gcode' => Icons.code,
      _ => Icons.view_in_ar_outlined,
    };

String tamanhoArquivo(num bytes) =>
    bytes >= 1024 * 1024 ? '${numero(bytes / 1024 / 1024)} MB' : '${numero(bytes / 1024)} KB';

/// Área de envio: botão (celular e navegador) + arrastar-e-soltar (navegador), com barra de progresso.
class EnvioArquivos extends StatefulWidget {
  const EnvioArquivos({super.key, required this.modeloId, required this.aoEnviar});
  final String modeloId;
  final VoidCallback aoEnviar;

  @override
  State<EnvioArquivos> createState() => _EnvioArquivosState();
}

class _EnvioArquivosState extends State<EnvioArquivos> {
  double? _progresso;
  String? _enviando;
  bool _sobre = false;

  Future<void> _enviar(String nome, int tamanho, Stream<List<int>> Function() abrir) async {
    final api = context.read<ApiCliente>();
    final recusa = validarArquivo(nome, tamanho);
    if (recusa != null) return avisar(context, '$nome: $recusa');
    setState(() {
      _enviando = nome;
      _progresso = 0;
    });
    try {
      await enviarArquivoModelo(api, widget.modeloId,
          nome: nome, tamanho: tamanho, bytes: abrir(), aoProgresso: (p) => setState(() => _progresso = p));
      if (mounted) avisar(context, '$nome enviado');
      widget.aoEnviar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _enviando = null;
          _progresso = null;
        });
      }
    }
  }

  Future<void> _escolher() async {
    final arquivos = await FilePicker.pickFiles();
    for (final f in arquivos) {
      await _enviar(f.name, await f.length() ?? 0, f.readAsByteStream);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final conteudo = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _sobre ? t.colorScheme.primary : t.colorScheme.outlineVariant),
        color: _sobre ? t.colorScheme.primaryContainer : null,
      ),
      child: _enviando != null
          ? Column(children: [
              Text('Enviando $_enviando…'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progresso),
            ])
          : Column(children: [
              OutlinedButton.icon(
                  onPressed: _escolher, icon: const Icon(Icons.upload_file), label: const Text('Enviar arquivo')),
              const SizedBox(height: 4),
              Text(kIsWeb ? 'ou arraste aqui · STL, 3MF, G-code, fotos · até 95 MB' : 'STL, 3MF, G-code, fotos · até 95 MB',
                  style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
            ]),
    );
    if (!kIsWeb) return conteudo;
    return DropTarget(
      onDragEntered: (_) => setState(() => _sobre = true),
      onDragExited: (_) => setState(() => _sobre = false),
      onDragDone: (d) async {
        setState(() => _sobre = false);
        for (final f in d.files) {
          await _enviar(f.name, await f.length(), f.openRead);
        }
      },
      child: conteudo,
    );
  }
}

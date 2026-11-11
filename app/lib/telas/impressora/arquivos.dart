import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/controle.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../util/formatos.dart';
import '../orcar/orcar_tela.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import 'envio.dart';

/// "3h05 · 33 g · 03/11/2026" de um arquivo da impressora.
String resumoArquivo(Json a) => [
      if (a['tempo_estimado_s'] != null) duracao(num0(a['tempo_estimado_s'])),
      if (a['gramas'] != null) gramas(num0(a['gramas'])),
      if (lerData(a['modificado']) != null) dataCurta(lerData(a['modificado'])!),
    ].join(' · ');

/// G-codes que já estão na impressora (mais recentes primeiro), com busca; tocar abre os detalhes.
class ArquivosImpressora extends StatefulWidget {
  const ArquivosImpressora({super.key, required this.impressora});
  final Json impressora;

  @override
  State<ArquivosImpressora> createState() => _ArquivosImpressoraState();
}

class _ArquivosImpressoraState extends State<ArquivosImpressora> {
  String _busca = '';

  String get _id => '${widget.impressora['id']}';

  Widget _miniatura(Json a, double tamanho) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: tamanho,
          height: tamanho,
          child: ImagemApi(a['miniatura'] == null ? null : miniaturaDaImpressora(_id, '${a['miniatura']}'),
              ajuste: BoxFit.contain),
        ),
      );

  void _detalhes(Json a) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => DetalheArquivo(impressoraId: _id, arquivo: a, miniatura: _miniatura(a, 160)),
      );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar arquivo', isDense: true),
              onChanged: (v) => setState(() => _busca = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: EstadoTela<List>(
              carregar: () => buscar(context, '/api/impressoras/$_id/arquivos'),
              vazio: (l) => l.isEmpty,
              estadoVazio: const EstadoVazio(
                icone: Icons.folder_open_outlined,
                titulo: 'Nenhum arquivo na impressora',
                explicacao: 'Os G-codes enviados pelo fatiador (ou pelo catálogo) aparecem aqui para imprimir de novo.',
              ),
              construir: (context, l) {
                final arquivos = [for (final a in lista(l)) if ('${a['nome']}'.toLowerCase().contains(_busca)) a];
                return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
                  for (final a in arquivos)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: _miniatura(a, 48),
                        title: Text('${a['nome']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(resumoArquivo(a)),
                        onTap: () => _detalhes(a),
                      ),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Detalhes do arquivo e (só o dono) "Imprimir", com confirmação.
class DetalheArquivo extends StatefulWidget {
  const DetalheArquivo({super.key, required this.impressoraId, required this.arquivo, required this.miniatura});
  final String impressoraId;
  final Json arquivo;
  final Widget miniatura;

  @override
  State<DetalheArquivo> createState() => _DetalheArquivoState();
}

class _DetalheArquivoState extends State<DetalheArquivo> with EnvioComando {
  @override
  String get impressoraId => widget.impressoraId;

  Future<void> _imprimir() async {
    final nome = '${widget.arquivo['nome']}';
    if (!await confirmar(context, 'Imprimir agora?', nome, sim: 'Imprimir agora') || !mounted) return;
    if (await enviar((api) => imprimirDaImpressora(api, impressoraId, nome), 'Impressão iniciada') && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dono = context.watch<Sessao>().dono;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: widget.miniatura),
          const SizedBox(height: 12),
          Text('${widget.arquivo['nome']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(resumoArquivo(widget.arquivo)),
          const SizedBox(height: 16),
          if (dono)
            FilledButton.icon(
              onPressed: se(_imprimir),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: emVoo
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print),
              label: const Text('Imprimir'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => OrcarTela(inicial: {
                          'itens': [
                            itemDeArquivo('${widget.arquivo['nome']}', widget.arquivo['gramas'] as num?,
                                widget.arquivo['tempo_estimado_s'] as num?)
                          ]
                        }))),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Orçar'),
          ),
        ]),
      ),
    );
  }
}

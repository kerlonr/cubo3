import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../widgets/estado_tela.dart';
import 'envio.dart';

/// Macros do Klipper (as que começam com "_" o servidor já esconde); o dono roda com um toque + confirmação.
class MacrosImpressora extends StatefulWidget {
  const MacrosImpressora({super.key, required this.impressora});
  final Json impressora;

  @override
  State<MacrosImpressora> createState() => _MacrosImpressoraState();
}

class _MacrosImpressoraState extends State<MacrosImpressora> with EnvioComando {
  @override
  String get impressoraId => '${widget.impressora['id']}';

  Future<void> _rodar(String nome) async {
    if (await confirmar(context, 'Rodar $nome?', 'A macro roda na impressora agora.', sim: 'Rodar') && mounted) {
      comando('macro', '$nome enviada', extra: {'nome': nome});
    }
  }

  @override
  Widget build(BuildContext context) {
    final dono = context.watch<Sessao>().dono;
    return EstadoTela<List>(
      carregar: () => buscar(context, '/api/impressoras/$impressoraId/macros'),
      vazio: (l) => l.isEmpty,
      estadoVazio: const EstadoVazio(
        icone: Icons.bolt_outlined,
        titulo: 'Nenhuma macro',
        explicacao: 'As macros do Klipper (gcode_macro no printer.cfg) aparecem aqui.',
      ),
      construir: (context, l) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            for (final m in lista(l))
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: Text('${m['nome']}', overflow: TextOverflow.ellipsis),
                  trailing: dono
                      ? FilledButton.tonal(onPressed: se(() => _rodar('${m['nome']}')), child: const Text('Rodar'))
                      : null,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

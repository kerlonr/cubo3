import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../impressoes/impressora_tela.dart';

/// Seção Painel: faixa "N a confirmar" e câmera, estado, pausar/continuar/cancelar, temperaturas e mover.
class PainelSecao extends StatelessWidget {
  const PainelSecao(
      {super.key, required this.impressora, required this.aConfirmar, required this.verHistorico, this.comCamera = true});

  final Json impressora;
  final int aConfirmar;
  final VoidCallback verHistorico;
  final bool comCamera;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            if (aConfirmar > 0) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pending_actions, color: amarelo),
                  title: Text(aConfirmar == 1 ? '1 impressão a confirmar' : '$aConfirmar impressões a confirmar'),
                  subtitle: const Text('Confirme os gramas reais para o estoque e o custo ficarem certos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: verHistorico,
                ),
              ),
              const SizedBox(height: 8),
            ],
            PainelImpressora(key: ValueKey(impressora['id']), impressora: impressora, comCamera: comCamera),
          ]),
        ),
      );
}

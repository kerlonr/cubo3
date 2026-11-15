import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../impressoes/confirmar_tela.dart';
import '../impressoes/impressora_tela.dart';

const nomesStatus = {
  'a_confirmar': 'A confirmar',
  'confirmada': 'Confirmada',
  'arquivada': 'Arquivada',
  'descartada': 'Descartada',
};

/// Impressões registradas: "A confirmar" (padrão) e "Todas"; tocar numa pendente abre a confirmação.
class HistoricoImpressoes extends StatefulWidget {
  const HistoricoImpressoes({super.key, required this.impressoes, required this.abrir, this.impressora, this.topo});

  /// Na ordem do servidor (mais antigas primeiro).
  final List<Json> impressoes;

  /// Abre uma tela e recarrega a aba na volta.
  final Future<void> Function(Widget tela) abrir;

  /// Com Klipper: botão para trazer trabalhos antigos do histórico dele.
  final Json? impressora;

  /// Antes da lista (ex.: convite para cadastrar a impressora).
  final Widget? topo;

  @override
  State<HistoricoImpressoes> createState() => _HistoricoImpressoesState();
}

class _HistoricoImpressoesState extends State<HistoricoImpressoes> {
  bool _todas = false;

  @override
  Widget build(BuildContext context) {
    final todas = widget.impressoes.reversed.toList();
    final pendentes = todas.where((i) => i['status'] == 'a_confirmar').length;
    final mostradas = _todas ? todas : [for (final i in todas) if (i['status'] == 'a_confirmar') i];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          ?widget.topo,
          Row(children: [
            Expanded(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text('A confirmar ($pendentes)')),
                  const ButtonSegment(value: true, label: Text('Todas')),
                ],
                selected: {_todas},
                onSelectionChanged: (s) => setState(() => _todas = s.first),
              ),
            ),
            if (widget.impressora != null) BotaoHistoricoKlipper(impressora: widget.impressora!),
          ]),
          const SizedBox(height: 8),
          if (mostradas.isEmpty)
            EstadoVazio(
              icone: Icons.task_alt,
              titulo: _todas ? 'Nenhuma impressão ainda' : 'Nada para confirmar',
              explicacao: 'As do Klipper chegam sozinhas. Imprimiu fora dele? Lance à mão.',
              acao: 'Lançar impressão',
              aoTocar: () => widget.abrir(const ConfirmarTela()),
            ),
          for (final i in mostradas) _item(i),
        ]),
      ),
    );
  }

  Widget _item(Json i) {
    final pendente = i['status'] == 'a_confirmar' || i['status'] == 'arquivada';
    final fim = lerData(i['fim']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 48, height: 48, child: ImagemApi(i['miniatura_url'] as String?, ajuste: BoxFit.contain)),
        ),
        title: Text('${i['arquivo'] ?? 'Impressão manual'}', overflow: TextOverflow.ellipsis),
        subtitle: Text([if (fim != null) dataHora(fim), duracao(num0(i['duracao_s']))].join(' · '),
            style: const TextStyle(fontFeatures: tabular)),
        trailing: Selo(nomesStatus[i['status']] ?? '${i['status']}',
            cor: i['status'] == 'a_confirmar' ? amarelo : (i['status'] == 'descartada' ? Colors.grey : null)),
        onTap: pendente ? () => widget.abrir(ConfirmarTela(impressao: i)) : null,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/adaptativo.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../mais/impressoras_tela.dart';
import 'confirmar_tela.dart';
import 'impressora_tela.dart';

const nomesStatus = {
  'a_confirmar': 'A confirmar',
  'confirmada': 'Confirmada',
  'arquivada': 'Arquivada',
  'descartada': 'Descartada',
};

/// Aba Impressora: câmera, estado e controles da impressora; ao lado (ou embaixo) "A confirmar" (padrão) e "Todas".
class ImpressoesAba extends StatefulWidget {
  const ImpressoesAba({super.key, this.aoContar, this.ativa = true});

  /// false enquanto outra aba está na frente (a câmera só liga com a aba visível).
  final bool ativa;

  /// Avisa a casca quantas estão a confirmar (contador no ícone da aba).
  final ValueChanged<int>? aoContar;

  @override
  State<ImpressoesAba> createState() => ImpressoesAbaState();
}

class ImpressoesAbaState extends State<ImpressoesAba> {
  bool _todas = false;
  int _versao = 0;
  String? _impressora;

  void recarregar() => setState(() => _versao++);

  Future<void> _abrir(Widget tela) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impressora'), actions: [
        IconButton(tooltip: 'Impressoras', icon: const Icon(Icons.settings_outlined), onPressed: () => _abrir(const ImpressorasTela())),
        IconButton(tooltip: 'Lançar impressão', icon: const Icon(Icons.add), onPressed: () => _abrir(const ConfirmarTela())),
      ]),
      body: EstadoTela<Map>(
        key: ValueKey(_versao),
        carregar: () async {
          final r = await buscarVarios(context, {'impressoes': '/api/impressoes', 'impressoras': '/api/impressoras'});
          final n = lista((r.dados as Map)['impressoes']).where((i) => i['status'] == 'a_confirmar').length;
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.aoContar?.call(n));
          return r;
        },
        construir: (context, d) => _corpo(d),
      ),
    );
  }

  Widget _corpo(Map d) {
    final impressoras = [for (final i in lista(d['impressoras'])) if ((i['moonraker_url'] ?? '') != '') i];
    final todas = lista(d['impressoes']).reversed.toList();
    final mostradas = _todas ? todas : [for (final i in todas) if (i['status'] == 'a_confirmar') i];
    final atual = impressoras.where((i) => i['id'] == _impressora).firstOrNull ?? impressoras.firstOrNull;
    return ListaDetalhe(
      detalhe: [
        if (impressoras.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in impressoras)
                ChoiceChip(
                  label: Text('${i['nome']}', overflow: TextOverflow.ellipsis),
                  selected: i == atual,
                  onSelected: (_) => setState(() => _impressora = i['id'] as String),
                ),
            ]),
          ),
        if (atual != null) ...[
          Align(alignment: Alignment.centerRight, child: BotaoHistoricoKlipper(impressora: atual)),
          PainelImpressora(key: ValueKey(atual['id']), impressora: atual, comCamera: widget.ativa),
        ],
      ],
      lista: [
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text('A confirmar (${todas.where((i) => i['status'] == 'a_confirmar').length})')),
            const ButtonSegment(value: true, label: Text('Todas')),
          ],
          selected: {_todas},
          onSelectionChanged: (s) => setState(() => _todas = s.first),
        ),
        const SizedBox(height: 8),
        if (mostradas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Nada para confirmar. Quando uma impressão terminar no Klipper, ela aparece aqui.',
                textAlign: TextAlign.center),
          ),
        for (final i in mostradas) _item(i),
      ],
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
        onTap: pendente ? () => _abrir(ConfirmarTela(impressao: i)) : null,
      ),
    );
  }
}

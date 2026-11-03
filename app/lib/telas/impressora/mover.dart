import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import 'envio.dart';

final _passos = {0.1: '0,1', 1.0: '1', 10.0: '10', 100.0: '100'};

/// O servidor recusa (409) o mesmo: imprimindo, nada de mexer nos eixos; pausada, home e motores perdem a peça.
bool imprimindo(Map estado) => estado['estado'] == 'printing';
bool pausada(Map estado) => estado['estado'] == 'paused';

/// Aviso do bloqueio acima (null quando nada está bloqueado).
Widget? avisoBloqueio(Map estado) => imprimindo(estado) || pausada(estado)
    ? Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
            imprimindo(estado)
                ? 'Pause a impressão para mover os eixos'
                : 'Com a impressão pausada, Home e Desligar motores ficam bloqueados: perdem a posição da peça',
            style: const TextStyle(fontSize: 13, color: amarelo)),
      )
    : null;

/// Posição, Home e setas de mover (só o dono vê). Vai no Painel, junto da câmera.
class MoverImpressora extends StatefulWidget {
  const MoverImpressora({super.key, required this.impressoraId, required this.estado});
  final String impressoraId;
  final Map estado;

  @override
  State<MoverImpressora> createState() => _MoverImpressoraState();
}

class _MoverImpressoraState extends State<MoverImpressora> with EnvioComando {
  double _passo = 10;

  @override
  String get impressoraId => widget.impressoraId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = widget.estado;
    final pos = e['posicao'] is List ? e['posicao'] as List : const [];
    final home = '${e['eixos_home'] ?? ''}'.toLowerCase();
    VoidCallback? mexe(VoidCallback f) => imprimindo(e) ? null : se(f);
    VoidCallback? zera(VoidCallback f) => imprimindo(e) || pausada(e) ? null : se(f);

    Widget eixo(String nome, int i) {
      final feito = home.contains(nome.toLowerCase());
      final cor = feito ? t.colorScheme.primary : t.colorScheme.outline;
      return Expanded(
        child: Column(children: [
          Text(nome, style: TextStyle(fontWeight: FontWeight.w700, color: cor)),
          Text(i < pos.length ? num0(pos[i]).toStringAsFixed(2).replaceAll('.', ',') : '—',
              style: TextStyle(fontSize: 18, fontFeatures: tabular, color: feito ? null : cor)),
          Text(feito ? 'em home' : 'sem home', style: TextStyle(fontSize: 11, color: cor)),
        ]),
      );
    }

    Widget seta(String eixo, int sinal, IconData icone) => IconButton.filledTonal(
          tooltip: '$eixo${sinal > 0 ? '+' : '−'}',
          iconSize: 28,
          onPressed: mexe(() => comando('mover', 'Movendo $eixo', extra: {'eixo': eixo, 'distancia': sinal * _passo})),
          icon: Icon(icone),
        );

    final homeEPasso = [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: zera(() => comando('home', 'Home de todos os eixos', extra: {'eixos': 'XYZ'})),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Home tudo')),
        OutlinedButton(
            onPressed: zera(() => comando('home', 'Home XY', extra: {'eixos': 'XY'})), child: const Text('Home XY')),
        OutlinedButton(onPressed: zera(() => comando('home', 'Home Z', extra: {'eixos': 'Z'})), child: const Text('Home Z')),
      ]),
      const SizedBox(height: 12),
      CampoComAjuda(
        rotulo: 'Passo (mm)',
        child: SeletorChips<double>(opcoes: _passos, valor: _passo, aoMudar: (p) => setState(() => _passo = p)),
      ),
    ];
    final setas = Wrap(alignment: WrapAlignment.center, spacing: 32, runSpacing: 16, children: [
      Column(mainAxisSize: MainAxisSize.min, children: [
        seta('Y', 1, Icons.keyboard_arrow_up),
        Row(mainAxisSize: MainAxisSize.min, children: [
          seta('X', -1, Icons.keyboard_arrow_left),
          const SizedBox(width: 56, child: Center(child: Text('XY', style: TextStyle(fontWeight: FontWeight.w600)))),
          seta('X', 1, Icons.keyboard_arrow_right),
        ]),
        seta('Y', -1, Icons.keyboard_arrow_down),
      ]),
      Column(mainAxisSize: MainAxisSize.min, children: [
        seta('Z', 1, Icons.keyboard_arrow_up),
        const SizedBox(height: 40, child: Center(child: Text('Z', style: TextStyle(fontWeight: FontWeight.w600)))),
        seta('Z', -1, Icons.keyboard_arrow_down),
      ]),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Secao('Mover'),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [eixo('X', 0), eixo('Y', 1), eixo('Z', 2)]),
        ),
      ),
      ?avisoBloqueio(e),
      if (home != 'xyz')
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Eixo em cinza ainda não fez Home. Faça Home antes de mover.',
              style: TextStyle(fontSize: 13, color: amarelo)),
        ),
      const SizedBox(height: 12),
      // Com espaço, Home e passo ao lado das setas: tudo cabe na tela junto da câmera.
      LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 480
            ? Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: homeEPasso)),
                const SizedBox(width: 16),
                setas,
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ...homeEPasso,
                const SizedBox(height: 8),
                setas,
              ]),
      ),
    ]);
  }
}

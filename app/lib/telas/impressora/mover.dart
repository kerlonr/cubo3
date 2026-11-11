import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import 'envio.dart';

// Passos escolhidos pelo Kerlon (estilo Mainsail): XY em mm grandes, Z fino.
final _passosXY = {1.0: '1', 5.0: '5', 10.0: '10', 25.0: '25', 50.0: '50'};
final _passosZ = {0.1: '0,1', 1.0: '1', 10.0: '10', 25.0: '25'};

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
  double _passoXY = 10, _passoZ = 1;

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

    const lado = 52.0;
    Widget botao(String dica, IconData icone, VoidCallback? acao, {bool destaque = false}) => SizedBox(
          width: lado,
          height: lado,
          child: destaque
              ? IconButton.filled(tooltip: dica, onPressed: acao, icon: Icon(icone))
              : IconButton.filledTonal(tooltip: dica, onPressed: acao, icon: Icon(icone, size: 28)),
        );
    Widget seta(String eixo, int sinal, IconData icone) => botao('$eixo${sinal > 0 ? '+' : '−'}', icone,
        mexe(() => comando('mover', 'Movendo $eixo',
            extra: {'eixo': eixo, 'distancia': sinal * (eixo == 'Z' ? _passoZ : _passoXY)})));
    const vazio = SizedBox(width: lado, height: lado);
    const g = SizedBox(width: 6, height: 6);

    // Cruz XY com Home XY no meio e coluna Z com Home Z no meio, lado a lado (como no Mainsail).
    final xy = Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [vazio, g, seta('Y', 1, Icons.keyboard_arrow_up), g, vazio]),
      g,
      Row(mainAxisSize: MainAxisSize.min, children: [
        seta('X', -1, Icons.keyboard_arrow_left),
        g,
        botao('Home XY', Icons.home_outlined, zera(() => comando('home', 'Home XY', extra: {'eixos': 'XY'}))),
        g,
        seta('X', 1, Icons.keyboard_arrow_right),
      ]),
      g,
      Row(mainAxisSize: MainAxisSize.min, children: [vazio, g, seta('Y', -1, Icons.keyboard_arrow_down), g, vazio]),
    ]);
    final z = Column(mainAxisSize: MainAxisSize.min, children: [
      seta('Z', 1, Icons.keyboard_arrow_up),
      g,
      botao('Home Z', Icons.home_outlined, zera(() => comando('home', 'Home Z', extra: {'eixos': 'Z'}))),
      g,
      seta('Z', -1, Icons.keyboard_arrow_down),
    ]);
    Widget rotulo(String r) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(r, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Secao('Mover',
          acao: FilledButton.tonalIcon(
            onPressed: zera(() => comando('home', 'Home de todos os eixos', extra: {'eixos': 'XYZ'})),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Home tudo'),
          )),
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
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown, child: xy),
            rotulo('Passo XY (mm)'),
            SeletorChips<double>(opcoes: _passosXY, valor: _passoXY, aoMudar: (p) => setState(() => _passoXY = p)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(children: [
            z,
            rotulo('Passo Z (mm)'),
            SeletorChips<double>(opcoes: _passosZ, valor: _passoZ, aoMudar: (p) => setState(() => _passoZ = p)),
          ]),
        ),
      ]),
    ]);
  }
}

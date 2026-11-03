import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ao_vivo/canal_ao_vivo.dart';
import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import 'envio.dart';

final _passos = {0.1: '0,1', 1.0: '1', 10.0: '10', 100.0: '100'};
const _extrusoes = {5: '5 mm', 10: '10 mm', 25: '25 mm'};

/// Bico mínimo para extrudar (abaixo disso o Klipper recusa e o filamento pode travar).
const bicoMinimoExtrudar = 170;

/// Controle da máquina (só o dono vê): home, eixos, motores, extrusora, ventoinha, velocidade, fluxo, Z e firmware.
class ControleImpressora extends StatefulWidget {
  const ControleImpressora({super.key, required this.impressora});
  final Json impressora;

  @override
  State<ControleImpressora> createState() => _ControleImpressoraState();
}

class _ControleImpressoraState extends State<ControleImpressora> with EnvioComando {
  Json? _inicial;
  double _passo = 10;
  int _extrusao = 10;
  final _arrasto = <String, double>{};

  @override
  String get impressoraId => '${widget.impressora['id']}';

  @override
  void initState() {
    super.initState();
    context.read<ApiCliente>().get('/api/impressoras/$impressoraId/ao-vivo').then((e) {
      if (mounted) setState(() => _inicial = mapa(e));
    }, onError: (_) {}); // sem estado: os controles abrem assim mesmo
  }

  void _mover(String eixo, int sinal) =>
      comando('mover', 'Movendo $eixo', extra: {'eixo': eixo, 'distancia': sinal * _passo});

  Future<void> _reiniciar() async {
    if (await confirmar(context, 'Reiniciar firmware?',
        'Use depois de uma parada de emergência ou erro. O Klipper reinicia e a impressora fica alguns segundos fora.',
        sim: 'Reiniciar')) {
      comando('reiniciar_firmware', 'Reiniciando o firmware');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = context.watch<CanalAoVivo>().estados[impressoraId]?.dados ?? _inicial ?? const {};
    final pos = e['posicao'] is List ? e['posicao'] as List : const [];
    final home = '${e['eixos_home'] ?? ''}'.toLowerCase();
    final bico = num0(e['bico']);
    final zOffset = num0(e['z_offset']);
    // O servidor recusa (409) o mesmo: imprimindo, nada de mexer nos eixos; pausada, home e motores perdem a peça.
    final imprimindo = e['estado'] == 'printing';
    final pausada = e['estado'] == 'paused';
    VoidCallback? mexe(VoidCallback f) => imprimindo ? null : se(f);
    VoidCallback? zera(VoidCallback f) => imprimindo || pausada ? null : se(f);

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
          onPressed: mexe(() => _mover(eixo, sinal)),
          icon: Icon(icone),
        );

    Widget slider(String acao, String rotulo, double minimo, double maximo, double padrao) {
      final v = (_arrasto[acao] ?? numOu(e['${acao}_pct']) ?? padrao).clamp(minimo, maximo).toDouble();
      return CampoComAjuda(
        rotulo: '$rotulo: ${v.round()}%',
        child: Slider(
          value: v,
          min: minimo,
          max: maximo,
          divisions: ((maximo - minimo) / 5).round(),
          label: '${v.round()}%',
          onChanged: emVoo ? null : (x) => setState(() => _arrasto[acao] = x),
          // Envia só ao soltar: arrastar não dispara dezenas de comandos.
          onChangeEnd: (x) async {
            await comando(acao, '$rotulo ${x.round()}%', valor: x.round());
            if (mounted) setState(() => _arrasto.remove(acao));
          },
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
          const Secao('Posição'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [eixo('X', 0), eixo('Y', 1), eixo('Z', 2)]),
            ),
          ),
          if (imprimindo || pausada)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  imprimindo
                      ? 'Pause a impressão para mover os eixos'
                      : 'Com a impressão pausada, Home e Desligar motores ficam bloqueados: perdem a posição da peça',
                  style: TextStyle(fontSize: 13, color: amarelo)),
            ),
          if (home != 'xyz')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Eixo em cinza ainda não fez Home. Faça Home antes de mover.',
                  style: TextStyle(fontSize: 13, color: amarelo)),
            ),
          const Secao('Home'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: zera(() => comando('home', 'Home de todos os eixos', extra: {'eixos': 'XYZ'})),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Home tudo')),
            OutlinedButton(
                onPressed: zera(() => comando('home', 'Home XY', extra: {'eixos': 'XY'})), child: const Text('Home XY')),
            OutlinedButton(
                onPressed: zera(() => comando('home', 'Home Z', extra: {'eixos': 'Z'})), child: const Text('Home Z')),
          ]),
          const Secao('Mover'),
          CampoComAjuda(
            rotulo: 'Passo (mm)',
            child: SeletorChips<double>(opcoes: _passos, valor: _passo, aoMudar: (p) => setState(() => _passo = p)),
          ),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 32, runSpacing: 16, children: [
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
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: zera(() => comando('motores_off', 'Motores desligados')),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Desligar motores')),
          ),
          const Secao('Extrusora'),
          SeletorChips<int>(opcoes: _extrusoes, valor: _extrusao, aoMudar: (v) => setState(() => _extrusao = v)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: bico >= bicoMinimoExtrudar
                  ? mexe(() => comando('extrudar', 'Extrudando $_extrusao mm', extra: {'distancia': _extrusao}))
                  : null,
              icon: const Icon(Icons.arrow_downward),
              label: const Text('Extrudar'),
            ),
            OutlinedButton.icon(
              onPressed: bico >= bicoMinimoExtrudar
                  ? mexe(() => comando('extrudar', 'Retraindo $_extrusao mm', extra: {'distancia': -_extrusao}))
                  : null,
              icon: const Icon(Icons.arrow_upward),
              label: const Text('Retrair'),
            ),
          ]),
          if (bico < bicoMinimoExtrudar)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Aqueça o bico a $bicoMinimoExtrudar °C ou mais para extrudar (agora ${bico.round()} °C).',
                  style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
            ),
          const Secao('Ventoinha, velocidade e fluxo'),
          slider('ventoinha', 'Ventoinha', 0, 100, 0),
          slider('velocidade', 'Velocidade', 10, 300, 100),
          slider('fluxo', 'Fluxo', 50, 150, 100),
          const Secao('Ajuste fino de Z'),
          Text('Ajuste atual: ${zOffset.toStringAsFixed(3).replaceAll('.', ',')} mm '
              '(negativo aproxima o bico da mesa)',
              style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in [-0.05, -0.01, 0.01, 0.05])
              OutlinedButton(
                onPressed: se(() => comando('ajuste_z', 'Z ajustado', valor: v)),
                child: Text('${v > 0 ? '+' : '−'}${v.abs().toString().replaceAll('.', ',')}'),
              ),
          ]),
          const Secao('Firmware'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: se(_reiniciar), icon: const Icon(Icons.restart_alt), label: const Text('Reiniciar firmware')),
          ),
        ]),
      ),
    );
  }
}

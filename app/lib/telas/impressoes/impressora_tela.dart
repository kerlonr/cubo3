import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ao_vivo/canal_ao_vivo.dart';
import '../../api/api.dart';
import '../../api/controle.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/adaptativo.dart';
import '../../widgets/camera_mjpeg.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../impressora/mover.dart';
import '../mais/impressoras_tela.dart';
import 'cartao_ao_vivo.dart';

/// Câmera, estado e (só para o dono) os controles da impressora, numa tela própria.
class ImpressoraTela extends StatelessWidget {
  const ImpressoraTela({super.key, required this.impressora});
  final Json impressora;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${impressora['nome']}'), actions: [BotaoHistoricoKlipper(impressora: impressora)]),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(padding: const EdgeInsets.all(16), children: [PainelImpressora(impressora: impressora)]),
          ),
        ),
      );
}

class BotaoHistoricoKlipper extends StatelessWidget {
  const BotaoHistoricoKlipper({super.key, required this.impressora});
  final Json impressora;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Histórico do Klipper',
        icon: const Icon(Icons.history),
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => HistoricoImpressoraTela(impressora: impressora))),
      );
}

/// Câmera, estado e controles (sem rolagem própria: vai dentro de uma lista). Para o dono: temperaturas e mover
/// junto da câmera; em tela larga (≥ 840 dp) a câmera fica à esquerda e eles à direita, para ver o vídeo movendo.
/// [comCamera] false enquanto a aba está escondida: o vídeo não fica gastando dados.
class PainelImpressora extends StatefulWidget {
  const PainelImpressora({super.key, required this.impressora, this.comCamera = true});
  final Json impressora;
  final bool comCamera;

  @override
  State<PainelImpressora> createState() => _PainelImpressoraState();
}

class _PainelImpressoraState extends State<PainelImpressora> {
  Json? _estado;
  bool _semConexao = false;
  bool _enviando = false;
  final _bico = TextEditingController();
  final _mesa = TextEditingController();

  String get _id => '${widget.impressora['id']}';

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _bico.dispose();
    _mesa.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    try {
      final e = mapa(await context.read<ApiCliente>().get('/api/impressoras/$_id/ao-vivo'));
      if (mounted) {
        setState(() {
          _estado = e;
          _semConexao = false;
        });
      }
    } on ErroApi catch (e) {
      if (mounted) setState(() => _semConexao = e.semConexao);
    }
  }

  /// Envia já; sem rede avisa e não guarda nada.
  Future<void> _enviar(Future<void> Function(ApiCliente api) acao, String feito) async {
    setState(() => _enviando = true);
    try {
      await acao(context.read<ApiCliente>());
      if (mounted) avisar(context, feito);
      _buscar();
    } on ErroApi catch (e) {
      if (!mounted) return;
      if (e.semConexao) setState(() => _semConexao = true);
      avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _comando(String acao, String feito) => _enviar((api) => comandar(api, _id, acao), feito);

  Future<void> _cancelar() async {
    if (await confirmar(context, 'Cancelar a impressão?', 'A peça em andamento será perdida.',
        sim: 'Cancelar impressão', nao: 'Voltar', cor: vermelho)) {
      _comando('cancelar', 'Cancelando a impressão');
    }
  }

  Future<void> _emergencia() async {
    if (await confirmar(
        context,
        'Parada de emergência?',
        'Desliga motores e aquecedores na hora e interrompe a impressão. Depois o Klipper precisa ser '
            'reiniciado (FIRMWARE_RESTART no Mainsail) antes de usar a impressora de novo.',
        sim: 'Parar agora',
        nao: 'Voltar',
        cor: vermelho)) {
      _comando('emergencia', 'Parada de emergência enviada');
    }
  }

  void _temperaturas(num? bico, num? mesa) =>
      _enviar((api) => mudarTemperaturas(api, _id, bico: bico, mesa: mesa), 'Temperatura enviada');

  /// "Desligar" (0/0) com peça em andamento ou pausada esfria e perde a peça: confirma antes.
  Future<void> _atalho(num bico, num mesa, String? estado) async {
    if (bico == 0 &&
        (estado == 'printing' || estado == 'paused') &&
        !await confirmar(context, 'Desligar bico e mesa?', 'A peça em andamento esfria e se perde.',
            sim: 'Desligar', nao: 'Voltar', cor: vermelho)) {
      return;
    }
    if (mounted) _temperaturas(bico, mesa);
  }

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<CanalAoVivo>().estados[_id]?.dados ?? _estado;
    final dono = context.watch<Sessao>().dono;
    final situacao = estado?['estado'] as String?;
    final esquerda = [
      if (widget.comCamera) ...[CameraAoVivo(impressoraId: _id), const SizedBox(height: 8)],
      PainelAoVivo(nome: '${widget.impressora['nome']}', estado: estado),
      if (dono) ..._impressao(situacao),
    ];
    final direita = [
      if (dono) ...[..._secaoTemperaturas(situacao), MoverImpressora(impressoraId: _id, estado: estado ?? const {})],
    ];
    final emergencia = [
      if (dono) ...[
        const SizedBox(height: 32),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: vermelho, foregroundColor: Colors.white),
          // Sempre tocável: nem outro comando no ar nem "sem conexão" (que um tempo esgotado também marca) a desligam.
          onPressed: _emergencia,
          icon: const Icon(Icons.dangerous_outlined),
          label: const Text('Parada de emergência'),
        ),
      ],
    ];
    if (ClasseLargura.de(context) != ClasseLargura.expandido || direita.isEmpty) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [...esquerda, ...direita, ...emergencia]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...esquerda, ...emergencia])),
      const SizedBox(width: 24),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: direita)),
    ]);
  }

  VoidCallback? _se(VoidCallback f) => !_semConexao && !_enviando ? f : null;

  List<Widget> _impressao(String? estado) => [
        if (_semConexao)
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off),
              title: const Text('Sem conexão — comandos desativados'),
              subtitle: const Text('Nada é guardado para depois.'),
              trailing: TextButton(onPressed: _buscar, child: const Text('Tentar de novo')),
            ),
          ),
        if (estado == 'printing' || estado == 'paused') ...[
          const Secao('Impressão'),
          Row(children: [
            Expanded(
              child: estado == 'printing'
                  ? OutlinedButton.icon(
                      onPressed: _se(() => _comando('pausar', 'Pausando')),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pausar'))
                  : FilledButton.icon(
                      onPressed: _se(() => _comando('continuar', 'Continuando')),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Continuar')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                  onPressed: _se(_cancelar), icon: const Icon(Icons.stop), label: const Text('Cancelar')),
            ),
          ]),
        ],
      ];

  List<Widget> _secaoTemperaturas(String? estado) => [
        const Secao('Temperaturas'),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _bico,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Bico', suffixText: '°C')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
                controller: _mesa,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Mesa', suffixText: '°C')),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _se(() {
              final bico = lerNumero(_bico.text), mesa = lerNumero(_mesa.text);
              if (bico != null || mesa != null) _temperaturas(bico, mesa);
            }),
            child: const Text('Aplicar'),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final a in atalhosTemperatura.entries)
            ActionChip(
              label: Text(a.key),
              tooltip: '${a.value.bico}° / ${a.value.mesa}°',
              onPressed: _se(() => _atalho(a.value.bico, a.value.mesa, estado)),
            ),
        ]),
      ];
}

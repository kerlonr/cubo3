import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ao_vivo/canal_ao_vivo.dart';
import '../../api/api.dart';
import '../../api/controle.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/camera_mjpeg.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../mais/impressoras_tela.dart';
import 'cartao_ao_vivo.dart';

/// Câmera, estado e (só para o dono) os controles da impressora.
class ImpressoraTela extends StatefulWidget {
  const ImpressoraTela({super.key, required this.impressora});
  final Json impressora;

  @override
  State<ImpressoraTela> createState() => _ImpressoraTelaState();
}

class _ImpressoraTelaState extends State<ImpressoraTela> {
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

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<CanalAoVivo>().estados[_id]?.dados ?? _estado;
    final dono = context.watch<Sessao>().dono;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.impressora['nome']}'), actions: [
        IconButton(
          tooltip: 'Histórico do Klipper',
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => HistoricoImpressoraTela(impressora: widget.impressora))),
        ),
      ]),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            CameraAoVivo(impressoraId: _id),
            const SizedBox(height: 8),
            PainelAoVivo(nome: '${widget.impressora['nome']}', estado: estado),
            if (dono) ..._controles(estado?['estado'] as String?),
          ]),
        ),
      ),
    );
  }

  List<Widget> _controles(String? estado) {
    final pode = !_semConexao && !_enviando;
    VoidCallback? se(VoidCallback f) => pode ? f : null;
    return [
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
                    onPressed: se(() => _comando('pausar', 'Pausando')), icon: const Icon(Icons.pause), label: const Text('Pausar'))
                : FilledButton.icon(
                    onPressed: se(() => _comando('continuar', 'Continuando')),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Continuar')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
                onPressed: se(_cancelar), icon: const Icon(Icons.stop), label: const Text('Cancelar')),
          ),
        ]),
      ],
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
          onPressed: se(() {
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
            onPressed: se(() => _temperaturas(a.value.bico, a.value.mesa)),
          ),
      ]),
      const SizedBox(height: 32),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: vermelho, foregroundColor: Colors.white),
        onPressed: se(_emergencia),
        icon: const Icon(Icons.dangerous_outlined),
        label: const Text('Parada de emergência'),
      ),
    ];
  }
}

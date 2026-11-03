import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ao_vivo/canal_ao_vivo.dart';
import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';

String nomeEstado(String? e) => switch (e) {
      'printing' => 'Imprimindo',
      'paused' => 'Pausada',
      'complete' => 'Terminou',
      'cancelled' => 'Cancelada',
      'error' => 'Erro',
      'standby' => 'Parada',
      'desconectada' => 'Sem conexão com a impressora',
      'desligada' => 'Klipper desligado',
      'sem_integracao' => 'Sem Klipper configurado',
      _ => e ?? '—',
    };

/// Estado da impressora (estado, arquivo, %, restante, bico/mesa).
class CartaoAoVivo extends StatefulWidget {
  const CartaoAoVivo({super.key, required this.impressora});
  final Json impressora;

  @override
  State<CartaoAoVivo> createState() => _CartaoAoVivoState();
}

class _CartaoAoVivoState extends State<CartaoAoVivo> {
  Json? _estado;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    try {
      final e = mapa(await context.read<ApiCliente>().get('/api/impressoras/${widget.impressora['id']}/ao-vivo'));
      if (mounted) setState(() => _estado = e);
    } on ErroApi {
      // Sem rede: o cartão fica com o último estado.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Eventos do WebSocket têm prioridade; o GET inicial cobre até o primeiro evento chegar.
    final aoVivo = context.watch<CanalAoVivo>().estados['${widget.impressora['id']}'];
    return PainelAoVivo(nome: '${widget.impressora['nome']}', estado: aoVivo?.dados ?? _estado);
  }
}

class PainelAoVivo extends StatelessWidget {
  const PainelAoVivo({super.key, required this.nome, required this.estado});
  final String nome;
  final Map? estado;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = estado ?? const {};
    final imprimindo = e['estado'] == 'printing' || e['estado'] == 'paused';
    final progresso = numOu(e['progresso']);
    String temp(String rotulo, Object? atual, Object? alvo) {
      if (atual == null) return '';
      final a = '${num0(atual).round()}°';
      return num0(alvo) > 0 ? '$rotulo $a/${num0(alvo).round()}°' : '$rotulo $a';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.print, size: 18, color: imprimindo ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(nome, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(nomeEstado(e['estado'] as String?), style: TextStyle(color: e['estado'] == 'error' ? vermelho : null)),
          ]),
          if (imprimindo) ...[
            const SizedBox(height: 8),
            Text('${e['arquivo'] ?? ''}', overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progresso, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 6),
            Row(children: [
              Text('${((progresso ?? 0) * 100).round()}%', style: const TextStyle(fontFeatures: tabular)),
              const Spacer(),
              if (e['restante_s'] != null)
                Text('faltam ${duracao(num0(e['restante_s']))}', style: const TextStyle(fontFeatures: tabular)),
            ]),
          ],
          if ('${e['mensagem'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('${e['mensagem']}')),
          if (e['bico'] != null || e['mesa'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [temp('Bico', e['bico'], e['bico_alvo']), temp('Mesa', e['mesa'], e['mesa_alvo'])]
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
                style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular),
              ),
            ),
        ]),
      ),
    );
  }
}

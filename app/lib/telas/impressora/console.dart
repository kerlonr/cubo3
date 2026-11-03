import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ao_vivo/canal_ao_vivo.dart';
import '../../api/api.dart';
import '../../api/controle.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../util/formatos.dart';
import '../../widgets/estado_tela.dart';
import 'envio.dart';

const _maxLinhas = 300;

/// Respostas do Klipper ao vivo (histórico do servidor + WebSocket) e, para o dono, campo de G-code
/// com os últimos comandos para repetir em um toque.
class ConsoleImpressora extends StatefulWidget {
  const ConsoleImpressora({super.key, required this.impressora});
  final Json impressora;

  @override
  State<ConsoleImpressora> createState() => _ConsoleImpressoraState();
}

class _ConsoleImpressoraState extends State<ConsoleImpressora> with EnvioComando {
  final _linhas = <Json>[];
  final _campo = TextEditingController();
  // shortcut: últimos comandos só em memória; guardar no aparelho se o Kerlon sentir falta ao reabrir o app.
  final _ultimos = <String>[];
  StreamSubscription<Map>? _eventos;

  @override
  String get impressoraId => '${widget.impressora['id']}';

  @override
  void initState() {
    super.initState();
    _eventos = context.read<CanalAoVivo>().eventos.listen((e) {
      if (e['tipo'] == 'console' && '${e['impressora_id']}' == impressoraId && mounted) {
        setState(() {
          _linhas.add(mapa(e));
          if (_linhas.length > _maxLinhas) _linhas.removeAt(0);
        });
      }
    });
    context.read<ApiCliente>().get('/api/impressoras/$impressoraId/console').then((r) {
      // As do servidor vêm antes das que chegaram pelo WebSocket enquanto o GET estava no ar.
      if (mounted) setState(() => _linhas.insertAll(0, lista(mapa(r)['linhas'])));
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _eventos?.cancel();
    _campo.dispose();
    super.dispose();
  }

  Future<void> _enviar([String? texto]) async {
    final script = (texto ?? _campo.text).trim();
    if (script.isEmpty) return;
    if (await enviar((api) => enviarGcode(api, impressoraId, script), 'Enviado: $script') && mounted) {
      setState(() {
        _ultimos
          ..remove(script)
          ..insert(0, script);
        if (_ultimos.length > 6) _ultimos.removeLast();
        if (texto == null) _campo.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dono = context.watch<Sessao>().dono;
    final t = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Expanded(
            child: _linhas.isEmpty
                ? ListView(children: const [
                    EstadoVazio(
                      icone: Icons.terminal,
                      titulo: 'Console vazio',
                      explicacao: 'As respostas do Klipper aparecem aqui ao vivo (temperaturas, avisos, erros).',
                    ),
                  ])
                : ListView.builder(
                    reverse: true, // a mais nova embaixo, perto do campo
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: _linhas.length,
                    itemBuilder: (_, i) {
                      final l = _linhas[_linhas.length - 1 - i];
                      final h = lerData(l['hora']);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text.rich(TextSpan(children: [
                          if (h != null)
                            TextSpan(text: '${hora(h)}  ', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                          TextSpan(text: '${l['texto']}'),
                        ])),
                      );
                    },
                  ),
          ),
          if (dono) ...[
            if (_ultimos.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  for (final u in _ultimos)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(label: Text(u), onPressed: se(() => _enviar(u))),
                    ),
                ]),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      key: const Key('gcode'),
                      controller: _campo,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: 'G-code (ex.: G28, M105)', counterText: ''),
                      onSubmitted: emVoo ? null : (_) => _enviar(),
                    ),
                  ),
                  IconButton.filled(tooltip: 'Enviar', onPressed: se(_enviar), icon: const Icon(Icons.send)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

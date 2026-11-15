import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';

/// Ajustar a foto de capa: escolher qual foto, arrastar para enquadrar e dar zoom.
/// Não mexe no arquivo: guarda só o enquadramento (`capa_ajuste`), que o catálogo e o perfil usam.
class CapaTela extends StatefulWidget {
  const CapaTela({super.key, required this.modelo});
  final Json modelo;

  @override
  State<CapaTela> createState() => _CapaTelaState();
}

class _CapaTelaState extends State<CapaTela> {
  late final Json m = widget.modelo;
  late final List<Json> _fotos = [for (final a in lista(m['arquivos'])) if (a['tipo'] == 'foto') a];
  late String? _capa = (m['capa_id'] as String?) ?? (_fotos.isEmpty ? null : '${_fotos.first['id']}');
  late final Json _ajuste = mapa(m['capa_ajuste']);
  late double _x = num0(_ajuste['x']), _y = num0(_ajuste['y']), _zoom = num0(_ajuste['zoom'] ?? 1).clamp(1, 4).toDouble();
  double _zoomInicial = 1;

  Map get _enquadramento => {'x': _x, 'y': _y, 'zoom': _zoom};

  Future<void> _salvar() async {
    final ok = await salvar(context, 'PUT', '/api/modelos/${m['id']}',
        {'capa_id': _capa, 'capa_ajuste': _enquadramento},
        versaoBase: m['atualizado_em'] as String?, feito: 'Foto ajustada');
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _foto(double proporcao) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: proporcao,
          child: ImagemApi(_capa == null ? null : '/api/arquivos/$_capa', enquadramento: _enquadramento),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustar foto'), actions: [
        TextButton(
            onPressed: () => setState(() {
                  _x = 0;
                  _y = 0;
                  _zoom = 1;
                }),
            child: const Text('Centralizar')),
      ]),
      bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Arraste a foto para enquadrar e use dois dedos (ou a barra) para o zoom.',
                style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) => GestureDetector(
                key: const Key('enquadrar'),
                onScaleStart: (_) => _zoomInicial = _zoom,
                onScaleUpdate: (d) => setState(() {
                  // Arrastar para a direita mostra mais da esquerda (foco vai para -1).
                  final metade = c.maxWidth / 2;
                  _x = (_x - d.focalPointDelta.dx / metade / _zoom).clamp(-1.0, 1.0);
                  _y = (_y - d.focalPointDelta.dy / (metade * 10 / 16) / _zoom).clamp(-1.0, 1.0);
                  if (d.pointerCount > 1) _zoom = (_zoomInicial * d.scale).clamp(1.0, 4.0);
                }),
                child: _foto(16 / 10),
              ),
            ),
            Row(children: [
              const Icon(Icons.zoom_out),
              Expanded(
                child: Slider(
                  key: const Key('zoom'),
                  value: _zoom,
                  min: 1,
                  max: 4,
                  onChanged: (v) => setState(() => _zoom = v),
                ),
              ),
              const Icon(Icons.zoom_in),
            ]),
            const Secao('No catálogo'),
            Align(alignment: Alignment.centerLeft, child: SizedBox(width: 180, child: _foto(1))),
            if (_fotos.length > 1) ...[
              const Secao('Foto de capa'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in _fotos)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _capa = '${f['id']}';
                      _x = 0;
                      _y = 0;
                      _zoom = 1;
                    }),
                    child: Container(
                      width: 76,
                      height: 76,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            width: 2, color: _capa == '${f['id']}' ? t.colorScheme.primary : Colors.transparent),
                      ),
                      child: ClipRRect(borderRadius: BorderRadius.circular(9), child: ImagemApi('/api/arquivos/${f['id']}')),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

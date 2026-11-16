import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';

class InsumoForm extends StatefulWidget {
  const InsumoForm({super.key, this.dados});
  final Json? dados;

  @override
  State<InsumoForm> createState() => _InsumoFormState();
}

class _InsumoFormState extends State<InsumoForm> {
  final _form = GlobalKey<FormState>();
  late final Json d = widget.dados ?? {};
  late final _nome = TextEditingController(text: d['nome'] as String?);
  late final _custo = ctrlDinheiro(numOu(d['custo_unitario']));
  late final _unidade = TextEditingController(text: d['unidade'] as String? ?? 'un');
  late final _minimo = ctrlNumero(numOu(d['estoque_minimo']));
  late String _categoria = d['categoria'] as String? ?? 'insumo';

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final ok = await salvar(context, 'PUT', '/api/insumos/${d['id'] ?? novoId()}', versaoBase: d['atualizado_em'] as String?, {
      'nome': _nome.text.trim(),
      'custo_unitario': lerNumero(_custo.text) ?? 0,
      'categoria': _categoria,
      'unidade': _unidade.text.trim().isEmpty ? 'un' : _unidade.text.trim(),
      'estoque_minimo': lerNumero(_minimo.text) ?? 0,
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dados == null ? 'Novo insumo' : 'Editar insumo'), actions: [
        if (widget.dados != null)
          IconButton(
              tooltip: 'Excluir',
              onPressed: () => excluirCadastro(context, 'Excluir insumo?', '/api/insumos/${d['id']}'),
              icon: const Icon(Icons.delete_outline, color: vermelho)),
      ]),
      body: CorpoFormulario(chave: _form, children: [
        CampoTexto(_nome, 'Nome (ímã, parafuso, caixa...)', obrigatorio: true),
        CampoDinheiro(_custo, 'Custo por unidade'),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'insumo', label: Text('Insumo')),
            ButtonSegment(value: 'embalagem', label: Text('Embalagem')),
          ],
          selected: {_categoria},
          onSelectionChanged: (s) => setState(() => _categoria = s.first),
        ),
        MaisDetalhes(children: [
          CampoTexto(_unidade, 'Unidade'),
          CampoNumero(_minimo, 'Estoque mínimo (alerta)'),
        ]),
        const SizedBox(height: 16),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ]),
    );
  }
}

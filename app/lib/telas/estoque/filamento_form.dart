import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';

const _paleta = [
  ('Branco', '#FFFFFF'),
  ('Preto', '#000000'),
  ('Cinza', '#9E9E9E'),
  ('Vermelho', '#E53935'),
  ('Laranja', '#FB8C00'),
  ('Amarelo', '#FDD835'),
  ('Verde', '#43A047'),
  ('Azul', '#1E88E5'),
  ('Roxo', '#8E24AA'),
  ('Rosa', '#EC407A'),
  ('Marrom', '#6D4C41'),
  ('Transparente', '#E0F7FA'),
];

const _materiais = ['PLA', 'PETG', 'ABS', 'ASA', 'TPU'];

class FilamentoForm extends StatefulWidget {
  const FilamentoForm({super.key, this.dados});
  final Json? dados;

  @override
  State<FilamentoForm> createState() => _FilamentoFormState();
}

class _FilamentoFormState extends State<FilamentoForm> {
  final _form = GlobalKey<FormState>();
  late final Json d = widget.dados ?? {};
  late final _marca = TextEditingController(text: d['marca'] as String?);
  late final _material = TextEditingController(text: d['material'] as String? ?? 'PLA');
  late final _corNome = TextEditingController(text: d['cor_nome'] as String?);
  late final _corHex = TextEditingController(text: d['cor_hex'] as String?);
  late final _precoKg = ctrlDinheiro(numOu(d['preco_kg']));
  late final _diametro = ctrlNumero(numOu(d['diametro']) ?? 1.75);
  late final _densidade = ctrlNumero(numOu(d['densidade']) ?? 1.24);
  late final _vazio = ctrlNumero(numOu(d['peso_carretel_vazio_g']));
  late final _minimo = ctrlNumero(numOu(d['estoque_minimo_g']));

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final hex = _corHex.text.trim().toUpperCase();
    final ok = await salvar(context, 'PUT', '/api/filamentos/${d['id'] ?? novoId()}', {
      'marca': _marca.text.trim(),
      'material': _material.text.trim().toUpperCase(),
      'cor_nome': _corNome.text.trim().isEmpty ? null : _corNome.text.trim(),
      'cor_hex': RegExp(r'^#[0-9A-F]{6}$').hasMatch(hex) ? hex : null,
      'preco_kg': lerNumero(_precoKg.text),
      'diametro': lerNumero(_diametro.text) ?? 1.75,
      'densidade': lerNumero(_densidade.text) ?? 1.24,
      'peso_carretel_vazio_g': lerNumero(_vazio.text),
      'estoque_minimo_g': lerNumero(_minimo.text) ?? 0,
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dados == null ? 'Novo filamento' : 'Editar filamento')),
      body: CorpoFormulario(chave: _form, children: [
        CampoTexto(_marca, 'Marca', obrigatorio: true),
        Wrap(spacing: 8, children: [
          for (final m in _materiais)
            ChoiceChip(
              label: Text(m),
              selected: _material.text.toUpperCase() == m,
              onSelected: (_) => setState(() => _material.text = m),
            ),
        ]),
        CampoTexto(_material, 'Material', obrigatorio: true, aoMudar: (_) => setState(() {})),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (nome, hex) in _paleta)
            InkWell(
              onTap: () => setState(() {
                _corNome.text = nome;
                _corHex.text = hex;
              }),
              child: Tooltip(
                message: nome,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        width: 2,
                        color: _corHex.text.toUpperCase() == hex ? Theme.of(context).colorScheme.primary : Colors.transparent),
                  ),
                  child: BolinhaCor(corHex(hex), tamanho: 28),
                ),
              ),
            ),
        ]),
        Row(children: [
          Expanded(child: CampoTexto(_corNome, 'Nome da cor')),
          const SizedBox(width: 12),
          SizedBox(
              width: 130, child: CampoTexto(_corHex, 'Hex', dica: '#FFFFFF', aoMudar: (_) => setState(() {}))),
        ]),
        CampoDinheiro(_precoKg, 'Preço por kg', obrigatorio: true),
        MaisDetalhes(children: [
          CampoNumero(_diametro, 'Diâmetro', sufixo: 'mm'),
          CampoNumero(_densidade, 'Densidade', sufixo: 'g/cm³'),
          CampoNumero(_vazio, 'Peso do carretel vazio', sufixo: 'g'),
          CampoNumero(_minimo, 'Estoque mínimo (alerta)', sufixo: 'g'),
        ]),
        const SizedBox(height: 16),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ]),
    );
  }
}

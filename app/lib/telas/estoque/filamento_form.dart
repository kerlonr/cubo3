import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
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
  ('Bege', '#D7C4A3'),
  ('Dourado', '#C9A227'),
  ('Prata', '#BDBDBD'),
  ('Verde-claro', '#9CCC65'),
  ('Azul-claro', '#4FC3F7'),
  ('Vinho', '#7B1F3A'),
  ('Lilás', '#B39DDB'),
  ('Laranja neon', '#FF6D00'),
];

const _materiais = ['PLA', 'PETG', 'ABS', 'TPU', 'ASA'];

/// O servidor exige marca; sem ela o filamento fica como "Genérico".
const marcaPadrao = 'Genérico';

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
  late bool _outroMaterial = !_materiais.contains(_material.text.toUpperCase());
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
    final ok = await salvar(context, 'PUT', '/api/filamentos/${d['id'] ?? novoId()}', versaoBase: d['atualizado_em'] as String?, {
      'marca': _marca.text.trim().isEmpty ? marcaPadrao : _marca.text.trim(),
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
    final material = _outroMaterial ? 'Outro' : _material.text.toUpperCase();
    return Scaffold(
      appBar: AppBar(title: Text(widget.dados == null ? 'Novo filamento' : 'Editar filamento'), actions: [
        if (widget.dados != null)
          IconButton(
              tooltip: 'Excluir',
              onPressed: () => excluirCadastro(context, 'Excluir filamento?', '/api/filamentos/${d['id']}'),
              icon: const Icon(Icons.delete_outline, color: vermelho)),
      ]),
      bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
      body: CorpoFormulario(chave: _form, children: [
        CampoComAjuda(
          rotulo: 'Material',
          child: SeletorChips<String>(
            opcoes: {for (final m in [..._materiais, 'Outro']) m: m},
            valor: material,
            aoMudar: (m) => setState(() {
              _outroMaterial = m == 'Outro';
              _material.text = _outroMaterial ? '' : m;
            }),
          ),
        ),
        if (_outroMaterial) CampoTexto(_material, 'Qual material?', obrigatorio: true, dica: 'PLA Silk, Nylon...'),
        CampoComAjuda(
          rotulo: 'Cor',
          ajuda: _corNome.text.isEmpty ? 'Toque na cor do carretel' : _corNome.text,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (nome, hex) in _paleta)
              Tooltip(
                message: nome,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() {
                    _corNome.text = nome;
                    _corHex.text = hex;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          width: 2,
                          color:
                              _corHex.text.toUpperCase() == hex ? Theme.of(context).colorScheme.primary : Colors.transparent),
                    ),
                    child: BolinhaCor(corHex(hex), tamanho: 34),
                  ),
                ),
              ),
          ]),
        ),
        CampoDinheiro(_precoKg, 'Preço por kg',
            key: const Key('preco_kg'), obrigatorio: true),
        MaisDetalhes(children: [
          CampoTexto(_marca, 'Marca', dica: marcaPadrao),
          CampoTexto(_corNome, 'Nome da cor', dica: 'Se não está na paleta (ex.: Azul petróleo)'),
          CampoTexto(_corHex, 'Código da cor', dica: '#FFFFFF', aoMudar: (_) => setState(() {})),
          CampoNumero(_diametro, 'Diâmetro', sufixo: 'mm'),
          CampoNumero(_densidade, 'Densidade', sufixo: 'g/cm³'),
          CampoNumero(_vazio, 'Peso do carretel vazio',
              sufixo: 'g', ajuda: 'Para pesar o carretel na balança e saber quanto sobrou.'),
          CampoNumero(_minimo, 'Avisar quando ficar abaixo de', sufixo: 'g', ajuda: 'O Início mostra "Repor".'),
        ]),
      ]),
    );
  }
}

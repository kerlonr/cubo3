import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../dominio/custos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';

/// Linha da receita: item escolhido + quantidade.
class LinhaReceita {
  LinhaReceita(this.id, num? qtd) : qtd = ctrlNumero(qtd);
  String? id;
  final TextEditingController qtd;
}

/// Cadastros que o custo ao vivo precisa (cacheados para funcionar sem internet).
const caminhosCusto = {
  'filamentos': '/api/filamentos',
  'insumos': '/api/insumos',
  'impressoras': '/api/impressoras',
  'config': '/api/empresa/config',
};

class ModeloForm extends StatefulWidget {
  const ModeloForm({super.key, this.dados});
  final Json? dados;

  @override
  State<ModeloForm> createState() => _ModeloFormState();
}

class _ModeloFormState extends State<ModeloForm> {
  final _form = GlobalKey<FormState>();
  late final Json d = widget.dados ?? {};
  late final Json receita = mapa(d['receita']);
  late final _nome = TextEditingController(text: d['nome'] as String?);
  late final _preco = ctrlDinheiro(numOu(d['preco_venda']));
  late final _descricao = TextEditingController(text: d['descricao'] as String?);
  late final _categoria = TextEditingController(text: d['categoria'] as String?);
  late final _tags = TextEditingController(text: (d['tags'] as List? ?? const []).join(', '));
  late final _links = TextEditingController(
      text: [for (final l in lista(d['links'])) (l['titulo'] ?? '') == '' ? l['url'] : '${l['titulo']} | ${l['url']}']
          .join('\n'));
  late final _horas = ctrlNumero(numOu(receita['horas']));
  late final _maoObra = ctrlNumero(numOu(receita['mao_obra_min']));
  late final _envio = ctrlDinheiro(numOu(receita['custo_envio']));
  late final _filamentos = [
    for (final f in lista(receita['filamentos'])) LinhaReceita(f['filamento_id'] as String?, numOu(f['gramas']))
  ];
  late final _insumos = [for (final i in lista(receita['insumos'])) LinhaReceita(i['insumo_id'] as String?, numOu(i['qtd']))];
  late String? _impressora = d['impressora_id'] as String?;

  Json get _receita => {
        'filamentos': [
          for (final f in _filamentos)
            if (f.id != null) {'filamento_id': f.id, 'gramas': lerNumero(f.qtd.text) ?? 0}
        ],
        'horas': lerNumero(_horas.text) ?? 0,
        'mao_obra_min': lerNumero(_maoObra.text) ?? 0,
        'insumos': [
          for (final i in _insumos)
            if (i.id != null) {'insumo_id': i.id, 'qtd': lerNumero(i.qtd.text) ?? 0}
        ],
        'custo_envio': lerNumero(_envio.text) ?? 0,
      };

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final links = [
      for (final linha in _links.text.split('\n'))
        if (linha.trim().isNotEmpty)
          linha.contains('|')
              ? {'titulo': linha.split('|').first.trim(), 'url': linha.split('|').last.trim()}
              : {'titulo': '', 'url': linha.trim()}
    ];
    final ok = await salvar(context, 'PUT', '/api/modelos/${d['id'] ?? novoId()}', versaoBase: d['atualizado_em'] as String?, {
      'nome': _nome.text.trim(),
      'preco_venda': lerNumero(_preco.text),
      'descricao': _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
      'categoria': _categoria.text.trim().isEmpty ? null : _categoria.text.trim(),
      'tags': [for (final t in _tags.text.split(',')) if (t.trim().isNotEmpty) t.trim()],
      'links': links,
      'receita': _receita,
      'impressora_id': _impressora,
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  void _mudou([_]) => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dados?['id'] == null ? 'Novo modelo' : 'Editar modelo')),
      body: EstadoTela<Map>(
        carregar: () => buscarVarios(context, caminhosCusto),
        construir: (context, cad) {
          final filamentos = lista(cad['filamentos']);
          final insumos = lista(cad['insumos']);
          final impressoras = lista(cad['impressoras']);
          final custo = custoDaReceita(_receita,
              filamentos: filamentos,
              insumos: insumos,
              impressoras: impressoras,
              config: mapa(cad['config']),
              impressoraId: _impressora);
          final preco = lerNumero(_preco.text);
          return CorpoFormulario(chave: _form, children: [
            CampoTexto(_nome, 'Nome', key: const Key('nome'), obrigatorio: true),
            CampoDinheiro(_preco, 'Preço de venda', aoMudar: _mudou),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Text('Custo ${moeda(custo.total)}', style: const TextStyle(fontFeatures: tabular)),
                const SizedBox(width: 16),
                if (preco != null)
                  Text('Lucro ${moeda(preco - custo.total)}',
                      style: TextStyle(fontFeatures: tabular, color: corResultado(preco - custo.total))),
              ]),
            ),
            MaisDetalhes(children: [
              CampoTexto(_descricao, 'Descrição', linhas: 3),
              CampoTexto(_categoria, 'Categoria'),
              CampoTexto(_tags, 'Tags (separadas por vírgula)'),
              CampoTexto(_links, 'Links (um por linha; "título | endereço")', linhas: 3, teclado: TextInputType.multiline),
            ]),
            MaisDetalhes(titulo: 'Receita e custo', children: [
              for (var i = 0; i < _filamentos.length; i++)
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: filamentos.any((f) => f['id'] == _filamentos[i].id) ? _filamentos[i].id : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Filamento'),
                      items: [
                        for (final f in filamentos)
                          DropdownMenuItem(value: f['id'] as String, child: Text(nomeFilamento(f), overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _filamentos[i].id = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: 100,
                      child: CampoNumero(_filamentos[i].qtd, 'Gramas', key: Key('gramas$i'), sufixo: 'g', aoMudar: _mudou)),
                  IconButton(onPressed: () => setState(() => _filamentos.removeAt(i)), icon: const Icon(Icons.close)),
                ]),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() =>
                      _filamentos.add(LinhaReceita(filamentos.length == 1 ? filamentos.single['id'] as String : null, null))),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar filamento'),
                ),
              ),
              Row(children: [
                Expanded(child: CampoNumero(_horas, 'Tempo de impressão', key: const Key('horas'), sufixo: 'h', aoMudar: _mudou)),
                const SizedBox(width: 12),
                Expanded(child: CampoNumero(_maoObra, 'Mão de obra', key: const Key('mao_obra'), sufixo: 'min', aoMudar: _mudou)),
              ]),
              for (var i = 0; i < _insumos.length; i++)
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: insumos.any((x) => x['id'] == _insumos[i].id) ? _insumos[i].id : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Insumo / embalagem'),
                      items: [
                        for (final x in insumos)
                          DropdownMenuItem(value: x['id'] as String, child: Text(x['nome'] as String, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _insumos[i].id = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 80, child: CampoNumero(_insumos[i].qtd, 'Qtd', aoMudar: _mudou)),
                  IconButton(onPressed: () => setState(() => _insumos.removeAt(i)), icon: const Icon(Icons.close)),
                ]),
              if (insumos.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _insumos.add(LinhaReceita(null, 1))),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar insumo'),
                  ),
                ),
              CampoDinheiro(_envio, 'Custo médio de envio', aoMudar: _mudou),
              if (impressoras.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: impressoras.any((x) => x['id'] == _impressora) ? _impressora : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Impressora'),
                  items: [
                    for (final x in impressoras) DropdownMenuItem(value: x['id'] as String, child: Text(x['nome'] as String)),
                  ],
                  onChanged: (v) => setState(() => _impressora = v),
                ),
              const SizedBox(height: 8),
              QuebraCusto(custo),
            ]),
            const SizedBox(height: 16),
            FilledButton(onPressed: _salvar, child: const Text('Salvar')),
          ]);
        },
      ),
    );
  }
}

/// Material, mão de obra, máquina, insumos, embalagem e total.
class QuebraCusto extends StatelessWidget {
  const QuebraCusto(this.c, {super.key});
  final Custo c;

  @override
  Widget build(BuildContext context) {
    Widget linha(String r, double v, {bool forte = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(r, style: TextStyle(fontWeight: forte ? FontWeight.w600 : null))),
            Text(moeda(v), style: TextStyle(fontFeatures: tabular, fontWeight: forte ? FontWeight.w600 : null)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          linha('Material', c.material),
          linha('Mão de obra', c.maoObra),
          linha('Máquina (energia e desgaste)', c.maquina),
          linha('Insumos', c.insumos),
          linha('Embalagem e envio', c.embalagem),
          const Divider(),
          linha('Custo', c.total, forte: true),
        ]),
      ),
    );
  }
}

/// Usado pelo perfil com o custo que o servidor calculou.
Custo custoDoJson(Map j) => Custo(num0(j['material']), num0(j['mao_obra']), num0(j['maquina']), num0(j['insumos']),
    num0(j['embalagem']), num0(j['total']));

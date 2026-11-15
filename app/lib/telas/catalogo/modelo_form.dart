import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../dominio/custos.dart';
import '../../dominio/orcamento.dart' show lerHoras, opcoesDePreco;
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';
import '../orcar/importar.dart';
import 'insumos_receita.dart';

/// Cadastros que o custo ao vivo precisa (cacheados para funcionar sem internet).
const caminhosCusto = {
  'filamentos': '/api/filamentos',
  'insumos': '/api/insumos',
  'impressoras': '/api/impressoras',
  'config': '/api/empresa/config',
};

/// Peça impressa do modelo. Um modelo pode juntar várias (ex.: fidget de switch = case + keycap).
class PecaReceita {
  PecaReceita({this.filamentoId, String nome = '', num? gramas, String tempo = '', num? precoKg})
      : nome = TextEditingController(text: nome),
        gramas = ctrlNumero(gramas),
        tempo = TextEditingController(text: tempo),
        precoKg = ctrlDinheiro(precoKg);

  String? filamentoId;
  final TextEditingController nome, gramas, tempo;

  /// Só para filamento avulso (sem cadastro): sem ele o material contava R$ 0.
  final TextEditingController precoKg;

  bool get vazia => gramas.text.trim().isEmpty && tempo.text.trim().isEmpty;

  /// Linha de `receita.filamentos`; null quando não há o que guardar (avulso sem preço e sem tempo).
  Json? get json {
    final g = lerNumero(gramas.text) ?? 0, h = lerHoras(tempo.text);
    final extra = <String, Object>{if (nome.text.trim().isNotEmpty) 'nome': nome.text.trim(), 'horas': ?h};
    if (filamentoId != null) return {'filamento_id': filamentoId, 'gramas': g, ...extra};
    final p = lerNumero(precoKg.text) ?? 0;
    if (p > 0 || (h ?? 0) > 0) return {'filamento_id': null, 'preco_kg': p, 'gramas': g, ...extra};
    return null;
  }

  /// Gramas e tempo de um arquivo fatiado ({nome, gramas, tempo}); o nome só se a peça ainda não tem.
  void preencher(Map item) {
    if (nome.text.trim().isEmpty) nome.text = '${item['nome'] ?? ''}';
    if ('${item['gramas'] ?? ''}'.isNotEmpty) gramas.text = '${item['gramas']}';
    if ('${item['tempo'] ?? ''}'.isNotEmpty) tempo.text = '${item['tempo']}';
  }
}

/// Peças da receita salva. Receita antiga (tempo só no total) põe o tempo na primeira peça.
List<PecaReceita> pecasDaReceita(Map receita) {
  final fils = lista(receita['filamentos']);
  final total = num0(receita['horas']);
  final semTempoPorPeca = !fils.any((f) => f['horas'] != null);
  String tempo(num h) => h > 0 ? duracao(h * 3600) : '';
  final pecas = [
    for (final (i, f) in fils.indexed)
      PecaReceita(
        filamentoId: f['filamento_id'] as String?,
        nome: '${f['nome'] ?? ''}',
        gramas: numOu(f['gramas']),
        precoKg: numOu(f['preco_kg']),
        tempo: f['horas'] != null ? tempo(num0(f['horas'])) : (semTempoPorPeca && i == 0 ? tempo(total) : ''),
      ),
  ];
  if (pecas.isEmpty) pecas.add(PecaReceita(tempo: tempo(total)));
  return pecas;
}

/// Totais da receita para mostrar (catálogo e perfil): gramas, horas, peças e insumos.
({double gramas, double horas, int pecas, int insumos}) resumoReceita(Map receita) {
  final fils = lista(receita['filamentos']);
  return (
    gramas: fils.fold(0.0, (s, f) => s + num0(f['gramas'])),
    horas: num0(receita['horas']),
    pecas: fils.length,
    insumos: lista(receita['insumos']).length,
  );
}

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
  late final _maoObra = ctrlNumero(numOu(receita['mao_obra_min']));
  late final _envio = ctrlDinheiro(numOu(receita['custo_envio']));
  late final _pecas = pecasDaReceita(receita);
  late final _insumos = [for (final i in lista(receita['insumos'])) LinhaInsumo.deJson(i)];
  late String? _impressora = d['impressora_id'] as String?;

  double get _horas => _pecas.fold(0.0, (s, p) => s + (lerHoras(p.tempo.text) ?? 0));

  Json get _receita => {
        'filamentos': [for (final p in _pecas) ?p.json],
        'horas': _horas,
        'mao_obra_min': lerNumero(_maoObra.text) ?? 0,
        'insumos': [for (final i in _insumos) i.json],
        'custo_envio': lerNumero(_envio.text) ?? 0,
      };

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final r = _receita;
    final semFilamento = !lista(r['filamentos']).any((f) => num0(f['gramas']) > 0);
    final semTempo = num0(r['horas']) == 0;
    if ((semFilamento || semTempo) &&
        !await confirmar(
            context,
            'Receita incompleta',
            '${semFilamento ? 'Sem filamento' : 'Sem tempo de impressão'}, o custo fica menor que o real '
                'e o lucro aparece maior. Salvar assim mesmo?',
            sim: 'Salvar assim')) {
      return;
    }
    if (!mounted) return;
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
      'receita': r,
      'impressora_id': _impressora,
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  void _mudou([_]) => setState(() {});

  /// Gramas e tempo de um arquivo: na peça [i] ou, sem índice, na primeira peça vazia (ou numa nova).
  Future<void> _importar(Future<Json?> Function() ler, [int? i]) async {
    final item = await ler();
    if (item == null || !mounted) return;
    setState(() {
      var alvo = i == null ? _pecas.where((p) => p.vazia).firstOrNull : _pecas[i];
      if (alvo == null) {
        alvo = PecaReceita(filamentoId: _pecas.last.filamentoId);
        _pecas.add(alvo);
      }
      alvo.preencher(item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dados?['id'] == null ? 'Novo modelo' : 'Editar modelo')),
      bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
      body: EstadoTela<Map>(
        carregar: () => buscarVarios(context, caminhosCusto),
        construir: (context, cad) {
          final filamentos = lista(cad['filamentos']);
          final impressoras = lista(cad['impressoras']);
          final klipper = impressorasComKlipper(impressoras);
          // Peça nova (sem nada digitado) já vem com o primeiro filamento cadastrado.
          for (final p in _pecas) {
            if (p.filamentoId == null && p.precoKg.text.isEmpty && p.vazia && filamentos.isNotEmpty) {
              p.filamentoId = filamentos.first['id'] as String;
            }
          }
          final custo = custoDaReceita(_receita,
              filamentos: filamentos,
              insumos: lista(cad['insumos']),
              impressoras: impressoras,
              config: mapa(cad['config']),
              impressoraId: _impressora);
          final preco = lerNumero(_preco.text);
          final t = Theme.of(context);
          final fraco = TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant);
          final gramasTotal = _pecas.fold(0.0, (s, p) => s + (lerNumero(p.gramas.text) ?? 0));
          return CorpoFormulario(chave: _form, children: [
            CampoTexto(_nome, 'Nome', key: const Key('nome'), obrigatorio: true, dica: 'Fidget switch chaveiro...'),
            const Secao('Peças impressas'),
            Text('Uma para cada parte impressa (ex.: case e keycap), cada uma com sua cor.', style: fraco),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: () => _importar(() => itemDoAparelho(context)),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Do arquivo')),
              for (final k in klipper.take(1))
                OutlinedButton.icon(
                    onPressed: () => _importar(() => itemDaImpressora(context, k)),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Da impressora')),
            ]),
            for (var i = 0; i < _pecas.length; i++) ...[
              const SizedBox(height: 8),
              _peca(i, filamentos, klipper),
            ],
            Row(children: [
              TextButton.icon(
                onPressed: () => setState(() => _pecas.add(PecaReceita(
                    filamentoId: _pecas.isEmpty ? null : _pecas.last.filamentoId))),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar peça'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${gramas(gramasTotal)} · ${_horas > 0 ? duracao(_horas * 3600) : 'sem tempo'}',
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: fraco.copyWith(fontFeatures: tabular)),
              ),
            ]),
            const Secao('Insumos'),
            Text('O que vai junto e entra no preço: switch, argola, ímã, embalagem.', style: fraco),
            const SizedBox(height: 8),
            EditorInsumos(linhas: _insumos, cadastro: lista(cad['insumos']), aoMudar: _mudou),
            CampoNumero(_maoObra, 'Mão de obra (montagem e acabamento)',
                key: const Key('mao_obra'), sufixo: 'min', aoMudar: _mudou),
            const Secao('Preço'),
            CampoDinheiro(_preco, 'Preço de venda', aoMudar: _mudou, ajuda: 'O seu preço. Toque numa sugestão para usar.'),
            Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Custo ${moeda(custo.total)}', style: const TextStyle(fontFeatures: tabular)),
              if (preco != null)
                Text('Lucro ${moeda(preco - custo.total)}${preco > 0 ? ' (${numero((preco - custo.total) / preco * 100)}%)' : ''}',
                    style: TextStyle(fontFeatures: tabular, color: corResultado(preco - custo.total))),
            ]),
            if (custo.total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in opcoesDePreco(custo.total, ParamEmpresa.fromJson(mapa(cad['config'])).margens))
                    ChoiceChip(
                      label: Text('${numero(p.margem)}% · ${moeda(p.preco)}', style: const TextStyle(fontFeatures: tabular)),
                      selected: preco == p.preco,
                      onSelected: (_) => setState(() => _preco.text = DinheiroFormatter.formatar(p.preco)),
                    ),
                ]),
              ),
            MaisDetalhes(titulo: 'Envio, impressora e detalhe do custo', children: [
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
            MaisDetalhes(children: [
              CampoTexto(_descricao, 'Descrição', linhas: 3),
              CampoTexto(_categoria, 'Categoria', dica: 'Chaveiros, Fidget...'),
              CampoTexto(_tags, 'Tags', ajuda: 'Separadas por vírgula; viram filtros no catálogo.'),
              CampoTexto(_links, 'Links', ajuda: 'Um por linha; "título | endereço".', linhas: 3, teclado: TextInputType.multiline),
            ]),
          ]);
        },
      ),
    );
  }

  Widget _peca(int i, List filamentos, List<Json> klipper) {
    final p = _pecas[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                key: Key('peca_nome$i'),
                controller: p.nome,
                decoration: InputDecoration(
                    hintText: 'Peça ${i + 1} (ex.: case, keycap)',
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Opções da peça',
              onSelected: (o) => o == 'tirar'
                  ? setState(() => _pecas.removeAt(i))
                  : _importar(
                      () => o == 'arquivo'
                          ? itemDoAparelho(context)
                          : itemDaImpressora(context, klipper.firstWhere((k) => 'imp:${k['id']}' == o)),
                      i),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'arquivo', child: Text('Puxar do arquivo fatiado')),
                for (final k in klipper) PopupMenuItem(value: 'imp:${k['id']}', child: Text('Puxar da ${k['nome']}')),
                if (_pecas.length > 1) const PopupMenuItem(value: 'tirar', child: Text('Tirar peça')),
              ],
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(children: [
              SeletorFilamento(
                  filamentos: filamentos, valor: p.filamentoId, aoMudar: (v) => setState(() => p.filamentoId = v)),
              if (p.filamentoId == null)
                CampoDinheiro(p.precoKg, 'Preço do filamento por kg', key: Key('preco_kg$i'), aoMudar: _mudou),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: CampoNumero(p.gramas, 'Gramas', key: Key('gramas$i'), sufixo: 'g', aoMudar: _mudou)),
                const SizedBox(width: 8),
                Expanded(
                  child: CampoComAjuda(
                    rotulo: 'Tempo',
                    child: TextFormField(
                      key: Key('horas$i'),
                      controller: p.tempo,
                      onChanged: _mudou,
                      decoration: const InputDecoration(hintText: '3h11'),
                      validator: (v) => (v ?? '').trim().isEmpty || lerHoras(v!) != null ? null : 'Use 3h11 ou 2,5',
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
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

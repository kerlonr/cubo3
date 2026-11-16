import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../api/cache.dart';
import '../../api/modelos.dart';
import '../../dominio/custos.dart';
import '../../dominio/orcamento.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/animacoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/logo.dart';
import '../../widgets/seletores.dart';
import '../catalogo/insumos_receita.dart';
import '../catalogo/modelo_form.dart' show caminhosCusto, ModeloForm, QuebraCusto;
import '../vendas/pix.dart' show gerarCobranca;
import 'historico.dart';
import 'importar.dart';

export 'importar.dart' show itemDeArquivo;

const _prefFilamento = 'orcar_filamento';
const _prefMaoObra = 'orcar_mao_obra';

/// Uma peça do orçamento (o kit pode ter várias).
class ItemOrcado {
  ItemOrcado({String nome = '', String gramas = '', String tempo = '', this.qtd = 1, this.filamento})
      : nome = TextEditingController(text: nome),
        gramas = TextEditingController(text: gramas),
        tempo = TextEditingController(text: tempo);

  factory ItemOrcado.deJson(Map j) =>
      ItemOrcado(
          nome: '${j['nome'] ?? ''}',
          gramas: '${j['gramas'] ?? ''}',
          tempo: '${j['tempo'] ?? ''}',
          qtd: num0(j['qtd'] ?? 1).toInt(),
          filamento: j['filamento_id'] as String?);

  final TextEditingController nome, gramas, tempo;
  int qtd;

  /// Cor/filamento desta peça quando é diferente do geral (ex.: keycap colorida, case preto).
  String? filamento;

  bool get vazio => gramas.text.trim().isEmpty && tempo.text.trim().isEmpty;
  Json get json => {
        'nome': nome.text.trim(),
        'gramas': gramas.text.trim(),
        'tempo': tempo.text.trim(),
        'qtd': qtd,
        if (filamento != null) 'filamento_id': filamento,
      };

  void dispose() {
    nome.dispose();
    gramas.dispose();
    tempo.dispose();
  }
}

/// Orçar peça: digita gramas e tempo (ou puxa de um arquivo fatiado) e vê o preço na hora.
/// Funciona sem internet com os cadastros do cache (ou, sem cache nenhum, os padrões da planilha).
class OrcarTela extends StatefulWidget {
  const OrcarTela({super.key, this.inicial});

  /// Orçamento do histórico ou peça vinda de arquivo: {'itens': [...], 'filamento_id', 'preco_kg', 'mao_obra', 'extra'}.
  final Json? inicial;

  @override
  State<OrcarTela> createState() => _OrcarTelaState();
}

class _OrcarTelaState extends State<OrcarTela> {
  late final List<ItemOrcado> _itens;
  late final String _id;
  final _precoKg = TextEditingController();
  final _maoObra = TextEditingController(text: '10');
  final _extra = TextEditingController();
  final _cliente = TextEditingController();
  final _obs = TextEditingController();
  final _meuPreco = TextEditingController();
  final _insumos = <LinhaInsumo>[];
  final _imagem = GlobalKey();
  bool _comPix = false;
  String? _filamento;
  String? _impressora;
  bool _escolheuFilamento = false;
  double _margem = margemAlvo; // recomendada; o Kerlon pode tocar em outra para baratear

  void _mudou([_]) => setState(() {});

  @override
  void initState() {
    super.initState();
    final ini = widget.inicial;
    _id = '${ini?['id'] ?? const Uuid().v4()}';
    _itens = [for (final i in lista(ini?['itens'])) ItemOrcado.deJson(i)];
    if (_itens.isEmpty) _itens.add(ItemOrcado());
    if (ini != null) {
      _filamento = ini['filamento_id'] as String?;
      _escolheuFilamento = ini.containsKey('filamento_id');
      _precoKg.text = '${ini['preco_kg'] ?? ''}';
      if (ini['mao_obra'] != null) _maoObra.text = '${ini['mao_obra']}';
      _extra.text = '${ini['extra'] ?? ''}';
      _margem = num0(ini['margem'] ?? margemAlvo).toDouble();
      _cliente.text = '${ini['cliente'] ?? ''}';
      _obs.text = '${ini['obs'] ?? ''}';
      _meuPreco.text = '${ini['preco_manual'] ?? ''}';
      _insumos.addAll([for (final i in lista(ini['insumos'])) LinhaInsumo.deJson(i)]);
    }
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        if (!_escolheuFilamento) _filamento = p.getString(_prefFilamento) ?? _filamento;
        if (ini?['mao_obra'] == null) _maoObra.text = p.getString(_prefMaoObra) ?? _maoObra.text;
      });
    });
  }

  @override
  void dispose() {
    for (final i in _itens) {
      i.dispose();
    }
    _precoKg.dispose();
    _maoObra.dispose();
    _extra.dispose();
    _cliente.dispose();
    _obs.dispose();
    _meuPreco.dispose();
    super.dispose();
  }

  Future<RespostaCache> _carregar() async {
    try {
      return await buscarVarios(context, caminhosCusto);
    } catch (_) {
      return RespostaCache(const {}, true, DateTime.now()); // nunca abriu online: padrões da planilha
    }
  }

  void _adicionar(Json item) => setState(() {
        if (_itens.length == 1 && _itens.single.vazio) _itens.removeAt(0).dispose();
        _itens.add(ItemOrcado.deJson(item));
      });

  Future<void> _doArquivo() async {
    final item = await itemDoAparelho(context);
    if (item != null && mounted) _adicionar(item);
  }

  Future<void> _daImpressora(Json impressora) async {
    final item = await itemDaImpressora(context, impressora);
    if (item != null && mounted) _adicionar(item);
  }

  /// Peças com gramas ou tempo.
  List<ItemOrcado> get _comDados => [
        for (final i in _itens)
          if ((lerNumero(i.gramas.text) ?? 0) > 0 || (lerHoras(i.tempo.text) ?? 0) > 0) i
      ];

  /// O orçamento como UMA receita (cada peça × quantidade, mão de obra por peça, insumos e envio).
  /// O custo sai dela e o "Salvar no catálogo" guarda ela: os dois dão o mesmo valor, arredondado só no fim.
  Json _receitaKit() {
    final itens = _comDados;
    final pecas = [
      for (final (n, it) in itens.indexed)
        <String, Object?>{
          'filamento_id': it.filamento ?? _filamento,
          if ((it.filamento ?? _filamento) == null) 'preco_kg': lerNumero(_precoKg.text) ?? 0,
          'gramas': (lerNumero(it.gramas.text) ?? 0) * it.qtd,
          'horas': (lerHoras(it.tempo.text) ?? 0) * it.qtd,
          'nome': [it.nome.text.trim().isEmpty ? 'Peça ${n + 1}' : it.nome.text.trim(), if (it.qtd > 1) '(${it.qtd}x)']
              .join(' '),
        }
    ];
    return {
      'filamentos': pecas,
      'horas': pecas.fold<double>(0, (s, f) => s + (f['horas'] as num)),
      'mao_obra_min': (lerNumero(_maoObra.text) ?? 0) * itens.fold<int>(0, (s, i) => s + i.qtd),
      'insumos': [for (final i in _insumos) i.json],
      'custo_envio': lerNumero(_extra.text) ?? 0,
    };
  }

  Custo _custo(Map cad) {
    if (_comDados.isEmpty) return const Custo(0, 0, 0, 0, 0, 0);
    return custoDaReceita(_receitaKit(),
        filamentos: lista(cad['filamentos']),
        insumos: lista(cad['insumos']),
        impressoras: lista(cad['impressoras']),
        config: mapa(cad['config']),
        impressoraId: _impressora);
  }

  Map? _cad; // cadastros da última montagem, para salvar a peça no catálogo com o mesmo custo

  /// O orçamento inteiro vira um modelo: cada peça é uma parte impressa (gramas e tempo × quantidade),
  /// com os insumos, a embalagem e o preço escolhido. Abre o cadastro já preenchido para conferir e salvar.
  void _paraCatalogo(PrecoSugerido p) {
    final itens = _comDados;
    // Uma peça em quantidade (ex.: 10 chaveiros): o catálogo guarda UMA unidade, com custo e preço divididos.
    final n = itens.length == 1 ? itens.single.qtd : 1;
    if (n > 1) {
      final it = itens.single;
      final unidade = {
        'filamentos': [
          {
            'filamento_id': it.filamento ?? _filamento,
            if ((it.filamento ?? _filamento) == null) 'preco_kg': lerNumero(_precoKg.text) ?? 0,
            'gramas': lerNumero(it.gramas.text) ?? 0,
            'horas': lerHoras(it.tempo.text) ?? 0,
            if (it.nome.text.trim().isNotEmpty) 'nome': it.nome.text.trim(),
          }
        ],
        'horas': lerHoras(it.tempo.text) ?? 0,
        'mao_obra_min': lerNumero(_maoObra.text) ?? 0,
        'insumos': [for (final i in _insumos) {...i.json, 'qtd': i.qtd / n}],
        'custo_envio': (lerNumero(_extra.text) ?? 0) / n,
      };
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ModeloForm(dados: {
                    'nome': it.nome.text.trim(),
                    'preco_venda': arred2(p.preco / n),
                    'receita': unidade,
                    'impressora_id': _impressora,
                  })));
      return;
    }
    final receita = _receitaKit();
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ModeloForm(dados: {
                  'nome': itens.length == 1 ? itens.single.nome.text.trim() : '',
                  'preco_venda': p.preco,
                  'receita': receita,
                  'impressora_id': _impressora,
                })));
  }

  /// Preço digitado pelo Kerlon (vale mais que as margens), ou null.
  double? get _precoManual {
    final v = lerNumero(_meuPreco.text);
    return v == null || v <= 0 ? null : v;
  }

  PrecoSugerido _escolhido(double custo) {
    final manual = _precoManual;
    if (manual != null) return PrecoSugerido(arred2((manual - custo) / manual * 100), custo, manual, manual);
    final ops = opcoesDePreco(custo, ParamEmpresa.fromJson(mapa((_cad ?? const {})['config'])).margens);
    return ops.firstWhere((p) => p.margem == _margem, orElse: () => precoDestaque(custo));
  }

  Json _registro(PrecoSugerido p) => {
        'id': _id,
        'quando': DateTime.now().toUtc().toIso8601String(),
        'itens': [for (final i in _itens) if (!i.vazio) i.json],
        'filamento_id': _filamento,
        'preco_kg': _precoKg.text,
        'mao_obra': _maoObra.text,
        'extra': _extra.text,
        'margem': p.margem,
        'preco_manual': _meuPreco.text.trim(),
        'insumos': [for (final i in _insumos) i.json],
        'cliente': _cliente.text.trim(),
        'obs': _obs.text.trim(),
        'preco': p.preco,
        'custo': p.custo,
      };

  DadosEnvio _dados(PrecoSugerido p) {
    final mesmaCor = _itens.every((i) => i.filamento == null || i.filamento == _filamento);
    final fil = !mesmaCor ? null : lista((_cad ?? const {})['filamentos']).where((f) => f['id'] == _filamento).firstOrNull;
    return DadosEnvio(
      pecas: [
        for (final (i, it) in _itens.where((x) => !x.vazio).indexed)
          PecaEnvio(it.nome.text.trim().isEmpty ? 'Peça ${i + 1}' : it.nome.text.trim(), it.qtd, lerHoras(it.tempo.text) ?? 0)
      ],
      total: p.preco,
      material: fil == null ? null : '${fil['material'] ?? ''} ${fil['cor_nome'] ?? ''}'.trim(),
      cliente: _cliente.text.trim(),
      obs: _obs.text.trim(),
      data: DateTime.now(),
    );
  }

  /// "Pix copia e cola" com o valor do orçamento (cobrança avulsa, online). '' sem Pix; null = falhou (já avisou).
  Future<String?> _pix(PrecoSugerido p) async {
    if (!_comPix) return '';
    final r = await gerarCobranca(context, {'valor': arred2(p.preco)});
    return r == null ? null : 'Pix copia e cola:\n${r['copia_e_cola']}';
  }

  Future<void> _compartilharTexto(PrecoSugerido p) async {
    final pix = await _pix(p);
    if (pix == null) return;
    await salvarOrcamento(_registro(p));
    await SharePlus.instance.share(ShareParams(text: [textoOrcamento(_dados(p)), if (pix.isNotEmpty) pix].join('\n\n')));
  }

  Future<void> _compartilharImagem(PrecoSugerido p) async {
    final caixa = _imagem.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (caixa == null) return;
    final img = await caixa.toImage(pixelRatio: 3);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    final pix = await _pix(p);
    if (pix == null) return;
    await salvarOrcamento(_registro(p));
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: 'orcamento-cubo3.png')],
      fileNameOverrides: ['orcamento-cubo3.png'],
      text: pix.isEmpty ? null : pix,
    ));
  }

  /// Prévia do que o cliente recebe, com "Para" e "Observação" opcionais, e os dois jeitos de enviar.
  Future<void> _enviar(PrecoSugerido p) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => StatefulBuilder(
          builder: (c, atualizar) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RepaintBoundary(key: _imagem, child: CartaoOrcamento(_dados(p))),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('cliente'),
                  controller: _cliente,
                  onChanged: (_) => atualizar(() {}),
                  decoration: const InputDecoration(labelText: 'Para (opcional)', hintText: 'Nome do cliente'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('obs'),
                  controller: _obs,
                  onChanged: (_) => atualizar(() {}),
                  decoration: const InputDecoration(labelText: 'Observação (opcional)', hintText: 'Ex.: pronto em 3 dias'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.pix),
                  title: Text('Incluir Pix de ${moeda(p.preco)}'),
                  value: _comPix,
                  onChanged: (v) => atualizar(() => _comPix = v),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _compartilharTexto(p),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      icon: const Icon(Icons.notes),
                      label: const Text('Texto'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _compartilharImagem(p),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Imagem'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orçar peça'), actions: [
        IconButton(
          tooltip: 'Orçamentos feitos',
          icon: const Icon(Icons.history),
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoricoOrcamentosTela())),
        ),
      ]),
      body: EstadoTela<Map>(carregar: _carregar, construir: (context, cad) => _corpo(cad)),
    );
  }

  Widget _corpo(Map cad) {
    _cad = cad;
    final t = Theme.of(context);
    final filamentos = ativos(cad['filamentos']);
    final impressoras = [for (final i in lista(cad['impressoras'])) if (i['excluido'] != true) i];
    final comKlipper = [for (final i in impressoras) if ('${i['moonraker_url'] ?? ''}'.isNotEmpty) i];
    if (_filamento != null && !filamentos.any((f) => f['id'] == _filamento)) _filamento = null;
    if (_filamento == null && !_escolheuFilamento && filamentos.isNotEmpty) _filamento = filamentos.first['id'] as String;
    final emp = ParamEmpresa.fromJson(mapa(cad['config']));
    final custo = _custo(cad);
    final temCusto = custo.total > 0;
    final opcoes = opcoesDePreco(custo.total, emp.margens);
    final destaque = _escolhido(custo.total);

    return Column(children: [
      Expanded(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                Tooltip(
                  message: 'G-code ou 3MF fatiado: gramas e tempo vêm sozinhos',
                  child: OutlinedButton.icon(
                      onPressed: _doArquivo, icon: const Icon(Icons.upload_file), label: const Text('Do arquivo')),
                ),
                for (final i in comKlipper.take(1))
                  OutlinedButton.icon(
                      onPressed: () => _daImpressora(i),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Da impressora')),
              ]),
              AnimatedSize(
                duration: duracaoAnimacao(context, 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(children: [
                  for (var i = 0; i < _itens.length; i++) ...[
                    const SizedBox(height: 8),
                    Entrada(key: ObjectKey(_itens[i]), child: _item(i)),
                  ],
                ]),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _itens.add(ItemOrcado())),
                  icon: const Icon(Icons.add),
                  label: const Text('Outra peça'),
                ),
              ),
              if (filamentos.isEmpty)
                CampoDinheiro(_precoKg, 'Preço do filamento por kg', aoMudar: _mudou)
              else
                SeletorFilamento(
                  filamentos: filamentos,
                  valor: _filamento,
                  rotulo: 'Filamento',
                  aoMudar: (v) {
                    setState(() {
                      _filamento = v;
                      _escolheuFilamento = true;
                    });
                    SharedPreferences.getInstance().then((p) => v == null ? p.remove(_prefFilamento) : p.setString(_prefFilamento, v));
                  },
                ),
              if (filamentos.isNotEmpty && _filamento == null) ...[
                const SizedBox(height: 12),
                CampoDinheiro(_precoKg, 'Preço do filamento por kg', aoMudar: _mudou),
              ],
              const Secao('Insumos'),
              Text('Quantidade do orçamento todo', style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              EditorInsumos(linhas: _insumos, cadastro: lista(cad['insumos']), aoMudar: _mudou),
              MaisDetalhes(titulo: 'Ajustes', children: [
                CampoNumero(_maoObra, 'Mão de obra por peça', sufixo: 'min', key: const Key('mao_obra'), aoMudar: (v) {
                  _mudou();
                  SharedPreferences.getInstance().then((p) => p.setString(_prefMaoObra, v));
                }),
                CampoDinheiro(_extra, 'Embalagem e envio (total)', aoMudar: _mudou),
                if (impressoras.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: _impressora,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Impressora'),
                    items: [
                      for (final x in impressoras) DropdownMenuItem(value: x['id'] as String, child: Text('${x['nome']}'))
                    ],
                    onChanged: (v) => setState(() => _impressora = v),
                  ),
              ]),
              if (temCusto) ...[
                const Secao('Margem de lucro'),
                Row(children: [
                  for (final p in opcoes)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Entrada(
                            ordem: opcoes.indexOf(p),
                            child: _opcaoMargem(p, _precoManual == null && p.margem == destaque.margem)),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                CampoDinheiro(_meuPreco, 'Meu preço (opcional)',
                    key: const Key('meu_preco'),
                    aoMudar: _mudou,
                    ajuda: _precoManual == null ? null : 'Lucro ${moeda(destaque.lucro)} (${numero(destaque.lucroPct)}%)'),
                MaisDetalhes(titulo: 'Detalhe do custo', children: [QuebraCusto(custo)]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('para_catalogo'),
                    onPressed: () => _paraCatalogo(destaque),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Salvar no catálogo'),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
      _barraPreco(temCusto, destaque),
    ]);
  }

  /// Cartão de margem: tocar escolhe o preço do orçamento; o de 50% vem marcado como recomendado.
  Widget _opcaoMargem(PrecoSugerido p, bool escolhida) {
    final t = Theme.of(context);
    final fraco = TextStyle(fontSize: 11, color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: escolhida ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: escolhida ? t.colorScheme.primary : t.colorScheme.outlineVariant, width: escolhida ? 2 : 1),
      ),
      child: InkWell(
        key: Key('margem${p.margem.toInt()}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() {
          _margem = p.margem;
          _meuPreco.clear();
        }),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${numero(p.margem)}%', style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(moeda(p.preco), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: tabular)),
            ),
            Text('exato ${moeda(p.exato)}', style: fraco),
            if (p.margem == margemAlvo)
              Text('recomendado', style: TextStyle(fontSize: 11, color: t.colorScheme.primary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final it = _itens[i];
    final tempoInvalido = it.tempo.text.trim().isNotEmpty && lerHoras(it.tempo.text) == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: it.nome,
                decoration: InputDecoration(
                    hintText: 'Peça ${i + 1}', isDense: true, filled: false, border: InputBorder.none, enabledBorder: InputBorder.none),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Menos uma',
              onPressed: it.qtd > 1 ? () => setState(() => it.qtd--) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('${it.qtd}', key: Key('qtd$i'), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
            IconButton(
                tooltip: 'Mais uma', onPressed: () => setState(() => it.qtd++), icon: const Icon(Icons.add_circle_outline)),
            if (_itens.length > 1)
              IconButton(
                  tooltip: 'Tirar peça',
                  onPressed: () => setState(() => _itens.removeAt(i).dispose()),
                  icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: CampoNumero(it.gramas, 'Gramas', sufixo: 'g', key: Key('gramas$i'), aoMudar: _mudou)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: Key('tempo$i'),
                  controller: it.tempo,
                  onChanged: _mudou,
                  decoration: InputDecoration(
                    labelText: 'Tempo',
                    hintText: '2h30',
                    errorText: tempoInvalido ? 'Use 2h30 ou 2,5' : null,
                  ),
                ),
              ),
            ]),
          ),
          _corDaPeca(it),
        ]),
      ),
    );
  }

  /// Filamento da peça: o geral do orçamento ou outro (outra cor). Só aparece com filamentos cadastrados.
  Widget _corDaPeca(ItemOrcado it) {
    final filamentos = ativos((_cad ?? const {})['filamentos']);
    if (filamentos.isEmpty) return const SizedBox.shrink();
    final f = filamentos.where((x) => x['id'] == (it.filamento ?? _filamento)).firstOrNull;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () async {
          final escolhido = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
                ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('Igual ao filamento geral'),
                    onTap: () => Navigator.pop(c, '')),
                for (final x in filamentos)
                  ListTile(
                    leading: BolinhaCor(corHex(x['cor_hex'])),
                    title: Text(nomeFilamento(x)),
                    onTap: () => Navigator.pop(c, '${x['id']}'),
                  ),
              ]),
            ),
          );
          if (escolhido == null) return;
          setState(() => it.filamento = escolhido.isEmpty ? null : escolhido);
        },
        icon: BolinhaCor(corHex(f?['cor_hex']), tamanho: 14),
        label: Text(f == null ? 'Preço avulso' : '${nomeFilamento(f)}${it.filamento == null ? '' : ' (só esta peça)'}',
            overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _barraPreco(bool temCusto, PrecoSugerido p) {
    final t = Theme.of(context);
    final fraco = TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular);
    return Material(
      color: t.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: duracaoAnimacao(context, 250),
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
          duration: duracaoAnimacao(context, 250),
          child: Padding(
          key: ValueKey(temCusto),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: !temCusto
              ? Row(children: [
                  Expanded(child: Text('Digite os gramas e o tempo para ver o preço', style: fraco.copyWith(fontSize: 14))),
                ])
              : Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          _precoManual != null
                              ? 'Meu preço (${numero(p.margem)}% de lucro)'
                              : 'Preço com ${numero(p.margem)}% de lucro${p.margem == margemAlvo ? ' (recomendado)' : ''}',
                          style: fraco),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ValorAnimado(p.preco,
                            chaveTexto: const Key('preco'),
                            estilo: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: tabular, letterSpacing: -1)),
                      ),
                      Text('lucro ${moeda(p.lucro)} · custo ${moeda(p.custo)}', style: fraco, key: const Key('lucro')),
                    ]),
                  ),
                  FilledButton.icon(onPressed: () => _enviar(p), icon: const Icon(Icons.send), label: const Text('Enviar')),
                ]),
        ),
        ),
        ),
      ),
    );
  }
}

class PecaEnvio {
  const PecaEnvio(this.nome, this.qtd, this.horas);
  final String nome;
  final int qtd;
  final double horas;
}

/// O que vai para o cliente: peças, material, tempo e total (nunca custo nem lucro).
class DadosEnvio {
  const DadosEnvio(
      {required this.pecas, required this.total, this.material, this.cliente = '', this.obs = '', required this.data});
  final List<PecaEnvio> pecas;
  final double total;
  final String? material;
  final String cliente, obs;
  final DateTime data;

  double get horas => pecas.fold(0.0, (s, p) => s + p.horas * p.qtd);

  /// Preço de cada unidade quando é uma peça só em quantidade.
  double? get cada => pecas.length == 1 && pecas.single.qtd > 1 ? arred2(total / pecas.single.qtd) : null;

  bool get temMaterial => material != null && material!.isNotEmpty;
}

/// Texto para o WhatsApp (os * deixam em negrito).
String textoOrcamento(DadosEnvio d) => [
      '*Orçamento Cubo³* · ${DateFormat('dd/MM/yyyy').format(d.data)}',
      if (d.cliente.isNotEmpty) 'Para: ${d.cliente}',
      '',
      for (final p in d.pecas) '• ${p.nome}${p.qtd > 1 ? ' — ${p.qtd} un.' : ''}${d.temMaterial ? ' (${d.material})' : ''}',
      '',
      if (d.horas > 0) 'Tempo de impressão: ~${duracao(d.horas * 3600)}',
      '*Total: ${moeda(d.total)}*${d.cada == null ? '' : ' (${moeda(d.cada!)} cada)'}',
      if (d.obs.isNotEmpty) 'Obs.: ${d.obs}',
    ].join('\n');

/// Imagem do orçamento: sempre no visual escuro da marca, para ficar igual em qualquer celular.
class CartaoOrcamento extends StatelessWidget {
  const CartaoOrcamento(this.d, {super.key});
  final DadosEnvio d;

  @override
  Widget build(BuildContext context) {
    const fraco = Color(0xFF9D9DB8), linha = Color(0xFF2A2A3D);
    String detalhe(PecaEnvio p) =>
        [if (d.temMaterial) d.material!, if (p.horas > 0) '~${duracao(p.horas * 3600)} cada'].join(' · ');
    return Container(
      width: 360,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF22205A), Color(0xFF0E0E16)]),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const LogoCubo3(tamanho: 28, comNome: true),
            const Spacer(),
            Text(DateFormat('dd/MM/yyyy').format(d.data), style: const TextStyle(color: fraco, fontSize: 12)),
          ]),
          const SizedBox(height: 20),
          const Text('ORÇAMENTO',
              style: TextStyle(color: indigoEscuro, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
          if (d.cliente.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Para ${d.cliente}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          for (final p in d.pecas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration:
                      BoxDecoration(color: indigoEscuro.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                  child: Text('${p.qtd}x',
                      style: const TextStyle(color: indigoEscuro, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.nome, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if (detalhe(p).isNotEmpty) Text(detalhe(p), style: const TextStyle(color: fraco, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: linha, height: 1)),
          if (d.horas > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const Icon(Icons.schedule, size: 16, color: fraco),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Tempo de impressão ~${duracao(d.horas * 3600)}',
                      style: const TextStyle(color: fraco, fontSize: 13)),
                ),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: indigoEscuro.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Total', style: TextStyle(color: fraco, fontSize: 13)),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(moeda(d.total),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: tabular, letterSpacing: -1)),
                if (d.cada != null)
                  Text('${moeda(d.cada!)} cada', style: const TextStyle(color: fraco, fontSize: 12, fontFeatures: tabular)),
                  ]),
                ),
              ),
            ]),
          ),
          if (d.obs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(d.obs, style: const TextStyle(color: fraco, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          const Center(child: Text('Impressão 3D sob encomenda', style: TextStyle(color: fraco, fontSize: 11))),
        ]),
      ),
    );
  }
}

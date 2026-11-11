import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
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
import '../catalogo/modelo_form.dart' show caminhosCusto, ModeloForm, QuebraCusto;
import '../impressora/arquivos.dart' show resumoArquivo;
import 'historico.dart';

const _prefFilamento = 'orcar_filamento';
const _prefMaoObra = 'orcar_mao_obra';

/// Uma peça do orçamento (o kit pode ter várias).
class ItemOrcado {
  ItemOrcado({String nome = '', String gramas = '', String tempo = '', this.qtd = 1})
      : nome = TextEditingController(text: nome),
        gramas = TextEditingController(text: gramas),
        tempo = TextEditingController(text: tempo);

  factory ItemOrcado.deJson(Map j) =>
      ItemOrcado(nome: '${j['nome'] ?? ''}', gramas: '${j['gramas'] ?? ''}', tempo: '${j['tempo'] ?? ''}', qtd: num0(j['qtd'] ?? 1).toInt());

  final TextEditingController nome, gramas, tempo;
  int qtd;

  bool get vazio => gramas.text.trim().isEmpty && tempo.text.trim().isEmpty;
  Json get json => {'nome': nome.text.trim(), 'gramas': gramas.text.trim(), 'tempo': tempo.text.trim(), 'qtd': qtd};

  void dispose() {
    nome.dispose();
    gramas.dispose();
    tempo.dispose();
  }
}

/// Item vindo de um arquivo fatiado (do aparelho ou da impressora).
Json itemDeArquivo(String nomeArquivo, num? gramasLidos, num? segundos) => {
      'nome': nomeArquivo.replaceAll(RegExp(r'(\.gcode)?(\.3mf)?$|\.gcode$', caseSensitive: false), ''),
      'gramas': gramasLidos == null ? '' : paraCampo(gramasLidos.toDouble()),
      'tempo': segundos == null ? '' : duracao(segundos),
      'qtd': 1,
    };

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
  final _imagem = GlobalKey();
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
    final escolhidos = await FilePicker.pickFiles();
    if (escolhidos.isEmpty || !mounted) return;
    final f = escolhidos.first;
    final lido = lerArquivoFatiado(f.name, await f.readAsBytes());
    if (!mounted) return;
    if (!lido.temDados) {
      avisar(context, 'Esse arquivo não tem gramas nem tempo. No Bambu Studio, fatie e exporte o G-code ou o 3MF fatiado.');
      return;
    }
    _adicionar(itemDeArquivo(f.name, lido.gramas, lido.segundos));
  }

  Future<void> _daImpressora(Json impressora) async {
    final arquivo = await showModalBottomSheet<Json>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.7,
        child: EstadoTela<List>(
          carregar: () => buscar(c, '/api/impressoras/${impressora['id']}/arquivos'),
          construir: (c, l) => ListView(children: [
            for (final a in lista(l))
              ListTile(
                title: Text('${a['nome']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(resumoArquivo(a)),
                onTap: () => Navigator.pop(c, a),
              ),
          ]),
        ),
      ),
    );
    if (arquivo == null) return;
    _adicionar(itemDeArquivo('${arquivo['nome']}', arquivo['gramas'] as num?, arquivo['tempo_estimado_s'] as num?));
  }

  Custo _custo(Map cad) {
    final partes = <(Custo, int)>[];
    for (final i in _itens) {
      final g = lerNumero(i.gramas.text) ?? 0, h = lerHoras(i.tempo.text) ?? 0;
      if (g == 0 && h == 0) continue;
      final receita = {
        'filamentos': [
          {'filamento_id': _filamento, 'preco_kg': lerNumero(_precoKg.text) ?? 0, 'gramas': g}
        ],
        'horas': h,
        'mao_obra_min': lerNumero(_maoObra.text) ?? 0,
      };
      partes.add((
        custoDaReceita(receita,
            filamentos: lista(cad['filamentos']),
            insumos: const [],
            impressoras: lista(cad['impressoras']),
            config: mapa(cad['config']),
            impressoraId: _impressora),
        i.qtd
      ));
    }
    return somarCustos(partes, extra: partes.isEmpty ? 0 : lerNumero(_extra.text) ?? 0);
  }

  Map? _cad; // cadastros da última montagem, para salvar a peça no catálogo com o mesmo custo

  /// Uma peça vira modelo com a mesma receita (filamento ou preço avulso, gramas, tempo, mão de obra)
  /// e o preço de 50% de uma unidade.
  void _paraCatalogo(ItemOrcado it) {
    final cad = _cad ?? const {};
    final receita = {
      'filamentos': [
        {
          'filamento_id': _filamento,
          if (_filamento == null) 'preco_kg': lerNumero(_precoKg.text) ?? 0,
          'gramas': lerNumero(it.gramas.text) ?? 0,
        }
      ],
      'horas': lerHoras(it.tempo.text) ?? 0,
      'mao_obra_min': lerNumero(_maoObra.text) ?? 0,
      'insumos': const [],
      'custo_envio': 0,
    };
    final custo = custoDaReceita(receita,
        filamentos: lista(cad['filamentos']),
        insumos: const [],
        impressoras: lista(cad['impressoras']),
        config: mapa(cad['config']),
        impressoraId: _impressora);
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ModeloForm(dados: {
                  'nome': it.nome.text.trim(),
                  'preco_venda': _escolhido(custo.total).preco,
                  'receita': receita,
                  'impressora_id': _impressora,
                })));
  }

  PrecoSugerido _escolhido(double custo) {
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
        'cliente': _cliente.text.trim(),
        'obs': _obs.text.trim(),
        'preco': p.preco,
        'custo': p.custo,
      };

  DadosEnvio _dados(PrecoSugerido p) {
    final fil = lista((_cad ?? const {})['filamentos']).where((f) => f['id'] == _filamento).firstOrNull;
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

  Future<void> _compartilharTexto(PrecoSugerido p) async {
    await salvarOrcamento(_registro(p));
    await SharePlus.instance.share(ShareParams(text: textoOrcamento(_dados(p))));
  }

  Future<void> _compartilharImagem(PrecoSugerido p) async {
    final caixa = _imagem.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (caixa == null) return;
    final img = await caixa.toImage(pixelRatio: 3);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    await salvarOrcamento(_registro(p));
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: 'orcamento-cubo3.png')],
      fileNameOverrides: ['orcamento-cubo3.png'],
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
                const SizedBox(height: 16),
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
    final filamentos = lista(cad['filamentos']);
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
                OutlinedButton.icon(
                    onPressed: _doArquivo, icon: const Icon(Icons.upload_file), label: const Text('Do arquivo')),
                for (final i in comKlipper.take(1))
                  OutlinedButton.icon(
                      onPressed: () => _daImpressora(i),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Da impressora')),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text('G-code ou 3MF já fatiado: os gramas e o tempo vêm sozinhos.',
                    style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
              ),
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
                DropdownButtonFormField<String?>(
                  key: ValueKey('fil$_filamento'),
                  initialValue: _filamento,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Filamento'),
                  items: [
                    for (final f in filamentos)
                      DropdownMenuItem<String?>(
                          value: f['id'] as String, child: Text(nomeFilamento(f), overflow: TextOverflow.ellipsis)),
                    const DropdownMenuItem<String?>(value: null, child: Text('Preço avulso')),
                  ],
                  onChanged: (v) {
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
                        child: Entrada(ordem: opcoes.indexOf(p), child: _opcaoMargem(p, p.margem == destaque.margem)),
                      ),
                    ),
                ]),
                MaisDetalhes(titulo: 'Detalhe do custo', children: [QuebraCusto(custo)]),
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
        onTap: () => setState(() => _margem = p.margem),
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
            PopupMenuButton<String>(
              tooltip: 'Mais opções da peça',
              onSelected: (o) => o == 'tirar' ? setState(() => _itens.removeAt(i).dispose()) : _paraCatalogo(it),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'catalogo', enabled: !it.vazio, child: const Text('Salvar no catálogo')),
                if (_itens.length > 1) const PopupMenuItem(value: 'tirar', child: Text('Tirar peça')),
              ],
            ),
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
        ]),
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
                      Text('Preço com ${numero(p.margem)}% de lucro${p.margem == margemAlvo ? ' (recomendado)' : ''}',
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

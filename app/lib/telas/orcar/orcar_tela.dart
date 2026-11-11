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
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/logo.dart';
import '../../widgets/seletores.dart';
import '../catalogo/modelo_form.dart' show caminhosCusto, QuebraCusto;
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
  final _imagem = GlobalKey();
  String? _filamento;
  String? _impressora;
  bool _escolheuFilamento = false;

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

  Json _registro(PrecoSugerido p) => {
        'id': _id,
        'quando': DateTime.now().toUtc().toIso8601String(),
        'itens': [for (final i in _itens) if (!i.vazio) i.json],
        'filamento_id': _filamento,
        'preco_kg': _precoKg.text,
        'mao_obra': _maoObra.text,
        'extra': _extra.text,
        'preco': p.preco,
        'custo': p.custo,
      };

  String _texto(PrecoSugerido p) {
    final itens = [for (final i in _itens) if (!i.vazio) i.json];
    return ['Orçamento Cubo³', for (final l in linhasItens(itens)) '• $l', '', 'Total: ${moeda(p.preco)}']
        .join('\n');
  }

  Future<void> _enviarTexto(PrecoSugerido p) async {
    await salvarOrcamento(_registro(p));
    await SharePlus.instance.share(ShareParams(text: _texto(p)));
  }

  Future<void> _enviarImagem(PrecoSugerido p) async {
    final itens = [for (final i in _itens) if (!i.vazio) i.json];
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        contentPadding: const EdgeInsets.all(12),
        content: SingleChildScrollView(
          child: RepaintBoundary(key: _imagem, child: CartaoOrcamento(itens: itens, preco: p.preco)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Compartilhar'),
            onPressed: () async {
              final caixa = _imagem.currentContext?.findRenderObject() as RenderRepaintBoundary?;
              if (caixa == null) return;
              final img = await caixa.toImage(pixelRatio: 3);
              final png = await img.toByteData(format: ui.ImageByteFormat.png);
              if (png == null) return;
              await salvarOrcamento(_registro(p));
              await SharePlus.instance.share(ShareParams(files: [
                XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: 'orcamento-cubo3.png')
              ], fileNameOverrides: [
                'orcamento-cubo3.png'
              ]));
            },
          ),
        ],
      ),
    );
  }

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
    final t = Theme.of(context);
    final filamentos = lista(cad['filamentos']);
    final impressoras = [for (final i in lista(cad['impressoras'])) if (i['excluido'] != true) i];
    final comKlipper = [for (final i in impressoras) if ('${i['moonraker_url'] ?? ''}'.isNotEmpty) i];
    if (_filamento != null && !filamentos.any((f) => f['id'] == _filamento)) _filamento = null;
    if (_filamento == null && !_escolheuFilamento && filamentos.isNotEmpty) _filamento = filamentos.first['id'] as String;
    final emp = ParamEmpresa.fromJson(mapa(cad['config']));
    final custo = _custo(cad);
    final temCusto = custo.total > 0;
    final destaque = precoDestaque(custo.total);

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
              for (var i = 0; i < _itens.length; i++) ...[const SizedBox(height: 8), _item(i)],
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
                const Secao('Pelas margens'),
                Row(children: [
                  for (final p in precosPorMargem(custo.total, emp.margens))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${numero(p.margem)}%',
                                  style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(moeda(p.preco),
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                              ),
                              Text('exato ${moeda(p.exato)}',
                                  style: TextStyle(fontSize: 11, color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular)),
                            ]),
                          ),
                        ),
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
                icon: const Icon(Icons.close),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: !temCusto
              ? Row(children: [
                  Expanded(child: Text('Digite os gramas e o tempo para ver o preço', style: fraco.copyWith(fontSize: 14))),
                ])
              : Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('Preço com ${numero(margemAlvo)}% de lucro', style: fraco),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: FittedBox(
                          key: ValueKey(p.preco),
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(moeda(p.preco),
                              key: const Key('preco'),
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: tabular, letterSpacing: -1)),
                        ),
                      ),
                      Text('lucro ${moeda(p.lucro)} · custo ${moeda(p.custo)}', style: fraco, key: const Key('lucro')),
                    ]),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Enviar imagem',
                    onPressed: () => _enviarImagem(p),
                    icon: const Icon(Icons.image_outlined),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: () => _enviarTexto(p), icon: const Icon(Icons.send), label: const Text('Enviar')),
                ]),
        ),
      ),
    );
  }
}

/// O que o cliente recebe: só as peças e o total (sem custo nem lucro).
class CartaoOrcamento extends StatelessWidget {
  const CartaoOrcamento({super.key, required this.itens, required this.preco});
  final List<Json> itens;
  final double preco;

  @override
  Widget build(BuildContext context) {
    const fundo = Color(0xFF15151F), fraco = Color(0xFF9D9DB8);
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(20)),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const LogoCubo3(tamanho: 28, comNome: true),
          const SizedBox(height: 16),
          Text('Orçamento · ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
              style: const TextStyle(color: fraco, fontSize: 12)),
          const SizedBox(height: 8),
          for (final l in linhasItens(itens))
            Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(l, style: const TextStyle(fontSize: 15))),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Color(0xFF2A2A3D))),
          const Text('Total', style: TextStyle(color: fraco, fontSize: 12)),
          Text(moeda(preco),
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: indigoEscuro, fontFeatures: tabular)),
        ]),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import 'modelo_form.dart';
import 'modelo_tela.dart';

const _ordens = {'mais_vendidos': 'Mais vendidos', 'lucro': 'Mais lucrativos', 'recentes': 'Recentes', 'nome': 'Nome'};
const _periodos = {0: 'Sempre', 30: '30 dias', 90: '90 dias'};

class CatalogoAba extends StatefulWidget {
  const CatalogoAba({super.key});

  @override
  State<CatalogoAba> createState() => _CatalogoAbaState();
}

class _CatalogoAbaState extends State<CatalogoAba> {
  String _ordem = 'mais_vendidos';
  int _periodo = 0;
  String _busca = '';
  String? _filtro; // categoria ou "#tag"
  int _versao = 0;
  Timer? _espera;

  Map<String, String> get _query => {
        'ordem': _ordem,
        if (_periodo > 0) 'periodo_dias': '$_periodo',
        if (_busca.isNotEmpty) 'busca': _busca,
      };

  Future<void> _abrir(Widget tela) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    setState(() => _versao++);
  }

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo'), actions: [
        IconButton(tooltip: 'Novo modelo', icon: const Icon(Icons.add), onPressed: () => _abrir(const ModeloForm())),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar modelo', isDense: true),
            onChanged: (v) {
              _espera?.cancel();
              _espera = Timer(const Duration(milliseconds: 400), () => setState(() => _busca = v.trim()));
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            DropdownButton<String>(
              value: _ordem,
              underline: const SizedBox(),
              items: [for (final e in _ordens.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _ordem = v!),
            ),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _periodo,
              underline: const SizedBox(),
              items: [for (final e in _periodos.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _periodo = v!),
            ),
          ]),
        ),
        Expanded(
          child: EstadoTela<List>(
            key: ValueKey('$_versao|$_query'),
            carregar: () => buscar(context, '/api/modelos', query: _query),
            vazio: (l) => l.isEmpty,
            mensagemVazio: 'Nenhum modelo. Toque em + para cadastrar o primeiro.',
            construir: (context, dados) => _grade(lista(dados)),
          ),
        ),
      ]),
    );
  }

  Widget _grade(List<Json> modelos) {
    final filtros = <String>{
      for (final m in modelos)
        if ((m['categoria'] as String? ?? '').isNotEmpty) m['categoria'] as String,
      for (final m in modelos)
        for (final t in (m['tags'] as List? ?? const [])) '#$t',
    }.toList()
      ..sort();
    final visiveis = [
      for (final m in modelos)
        if (_filtro == null ||
            m['categoria'] == _filtro ||
            (m['tags'] as List? ?? const []).map((t) => '#$t').contains(_filtro))
          m
    ];
    return LayoutBuilder(builder: (context, c) {
      final colunas = (c.maxWidth / 220).floor().clamp(2, 6);
      return CustomScrollView(slivers: [
        if (filtros.isNotEmpty)
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                for (final f in filtros)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f),
                      selected: _filtro == f,
                      onSelected: (s) => setState(() => _filtro = s ? f : null),
                    ),
                  ),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverGrid.count(
            crossAxisCount: colunas,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
            children: [for (final m in visiveis) _cartao(m)],
          ),
        ),
      ]);
    });
  }

  Widget _cartao(Json m) {
    final lucro = numOu(m['lucro_unitario']);
    final preco = numOu(m['preco_venda']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrir(ModeloTela(id: m['id'] as String)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: ImagemApi(m['capa_url'] as String?)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['nome'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(preco == null ? 'Sem preço' : moeda(preco), style: const TextStyle(fontFeatures: tabular)),
              // Wrap: em cartão estreito o "vendidos" desce inteiro em vez de partir o valor do lucro.
              Wrap(spacing: 8, children: [
                if (lucro != null)
                  Text('lucro ${moeda(lucro)}',
                      style: TextStyle(fontSize: 12, color: corResultado(lucro), fontFeatures: tabular)),
                Text('${numero(num0(m['vendidos']))} vend.', style: const TextStyle(fontSize: 12)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

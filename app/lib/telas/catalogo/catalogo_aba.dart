import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/animacoes.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import 'modelo_form.dart';
import 'modelo_tela.dart';

const _ordens = {'mais_vendidos': 'Mais vendidos', 'lucro': 'Mais lucrativos', 'recentes': 'Recentes', 'nome': 'Nome'};
const _periodos = {0: 'Desde sempre', 30: 'Últimos 30 dias', 90: 'Últimos 90 dias'};

class CatalogoAba extends StatefulWidget {
  const CatalogoAba({super.key});

  @override
  State<CatalogoAba> createState() => _CatalogoAbaState();
}

class _CatalogoAbaState extends State<CatalogoAba> {
  String _ordem = 'mais_vendidos';
  int _periodo = 0;
  String _busca = '';
  String? _filtro; // categoria
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
        // Ordem e período num ícone só; o ponto avisa quando não está no padrão.
        PopupMenuButton<Object>(
          tooltip: 'Ordenar',
          icon: Badge(
              isLabelVisible: _ordem != 'mais_vendidos' || _periodo != 0, smallSize: 8, child: const Icon(Icons.sort)),
          onSelected: (v) => setState(() {
            if (v is int) {
              _periodo = v;
            } else {
              _ordem = v as String;
            }
          }),
          itemBuilder: (_) => [
            for (final e in _ordens.entries) CheckedPopupMenuItem(value: e.key, checked: _ordem == e.key, child: Text(e.value)),
            const PopupMenuDivider(),
            for (final e in _periodos.entries)
              CheckedPopupMenuItem(value: e.key, checked: _periodo == e.key, child: Text(e.value)),
          ],
        ),
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
        Expanded(
          child: EstadoTela<List>(
            key: ValueKey('$_versao|$_query'),
            carregar: () => buscar(context, '/api/modelos', query: _query),
            vazio: (l) => l.isEmpty,
            estadoVazio: EstadoVazio(
              icone: Icons.category_outlined,
              titulo: 'Seu catálogo está vazio',
              explicacao: 'Cada peça que você vende, com foto e preço.',
              acao: 'Cadastrar modelo',
              aoTocar: () => _abrir(const ModeloForm()),
            ),
            construir: (context, dados) => _grade(lista(dados)),
          ),
        ),
      ]),
    );
  }

  Widget _grade(List<Json> modelos) {
    final filtros = categoriasDe(modelos);
    final visiveis = [for (final m in modelos) if (_filtro == null || m['categoria'] == _filtro) m];
    return LayoutBuilder(builder: (context, c) {
      final colunas = (c.maxWidth / 220).floor().clamp(2, 6);
      return CustomScrollView(slivers: [
        if (filtros.isNotEmpty)
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                for (final f in [null, ...filtros])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f ?? 'Todos'),
                      selected: _filtro == f,
                      onSelected: (_) => setState(() => _filtro = f),
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
            childAspectRatio: 0.75,
            children: [for (final (i, m) in visiveis.indexed) Entrada(key: ValueKey(m['id']), ordem: i, child: _cartao(m))],
          ),
        ),
      ]);
    });
  }

  Widget _cartao(Json m) {
    final lucro = numOu(m['lucro_unitario']);
    final preco = numOu(m['preco_venda']);
    final r = resumoReceita(mapa(m['receita']));
    final fraco = TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontFeatures: tabular);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrir(ModeloTela(id: m['id'] as String)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: ImagemApi(m['capa_url'] as String?, enquadramento: mapa(m['capa_ajuste']))),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['nome'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              // Wrap: em cartão estreito o lucro desce inteiro em vez de cortar o preço.
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(preco == null ? 'Sem preço' : moeda(preco),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                if (receitaIncompleta(mapa(m['receita'])))
                  const Selo('falta receita', cor: amarelo)
                else if (lucro != null)
                  Tooltip(
                    message: 'Lucro por unidade',
                    child: Text('${lucro >= 0 ? '+' : ''}${moeda(lucro)}',
                        style: TextStyle(fontSize: 12, color: corResultado(lucro), fontFeatures: tabular)),
                  ),
              ]),
              Text(
                  [
                    if (r.gramas > 0) gramas(r.gramas),
                    if (r.horas > 0) duracao(r.horas * 3600),
                    '${numero(num0(m['vendidos']))} vend.',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: fraco),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Sem filamento com gramas ou sem tempo: o custo sai menor que o real e o lucro, inflado.
bool receitaIncompleta(Map receita) {
  final pecas = lista(receita['filamentos']);
  return pecas.isEmpty || pecas.any((f) => num0(f['gramas']) <= 0) || num0(receita['horas']) == 0;
}

/// Categorias em uso, sem repetir e em ordem alfabética (filtro do catálogo e sugestões do formulário).
List<String> categoriasDe(List modelos) =>
    {for (final m in modelos) if ('${m['categoria'] ?? ''}'.trim().isNotEmpty) '${m['categoria']}'.trim()}.toList()..sort();

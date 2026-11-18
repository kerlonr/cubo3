import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api.dart';
import '../../api/controle.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';
import '../impressoes/confirmar_tela.dart';
import '../impressora/envio.dart';
import 'arquivos.dart';
import 'capa_tela.dart';
import 'catalogo_aba.dart' show receitaIncompleta;
import 'insumos_receita.dart';
import 'modelo_form.dart';

/// Perfil do modelo: capa, preço × custo × lucro, estoque, arquivos e histórico.
class ModeloTela extends StatefulWidget {
  const ModeloTela({super.key, required this.id});
  final String id;

  @override
  State<ModeloTela> createState() => _ModeloTelaState();
}

class _ModeloTelaState extends State<ModeloTela> with EnvioComando {
  int _versao = 0;

  /// Impressora do envio em curso (a recusa do Klipper oferece Home nela).
  @override
  String impressoraId = '';
  Json? _modelo;

  void _recarregar() => setState(() => _versao++);

  Future<void> _editar() async {
    if (_modelo == null) return;
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ModeloForm(dados: _modelo)));
    if (ok == true) _recarregar();
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir modelo?', 'Vendas e impressões antigas continuam mostrando o nome.',
        sim: 'Excluir')) {
      return;
    }
    if (!mounted) return;
    try {
      await context.read<ApiCliente>().delete('/api/modelos/${widget.id}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  Future<void> _apagarArquivo(Json a) async {
    if (!await confirmar(context, 'Apagar arquivo?', '${a['nome_original']}', sim: 'Apagar')) return;
    if (!mounted) return;
    try {
      await context.read<ApiCliente>().delete('/api/arquivos/${a['id']}');
      _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  /// Manda o G-code direto à impressora (nunca pela fila); com mais de uma, pergunta qual.
  Future<void> _imprimir(Json a, List<Json> impressoras) async {
    final imp = impressoras.length == 1
        ? impressoras.single
        : await showDialog<Json>(
            context: context,
            builder: (c) => SimpleDialog(title: const Text('Imprimir em qual impressora?'), children: [
              for (final i in impressoras)
                SimpleDialogOption(onPressed: () => Navigator.pop(c, i), child: Text('${i['nome']}')),
            ]),
          );
    if (imp == null || !mounted) return;
    if (!await confirmar(context, 'Imprimir agora?', 'Arquivo: ${a['nome_original']}\nImpressora: ${imp['nome']}',
        sim: 'Imprimir')) {
      return;
    }
    if (!mounted) return;
    impressoraId = '${imp['id']}';
    await enviar((api) => imprimirArquivo(api, '${a['id']}', impressoraId), 'Impressão iniciada na ${imp['nome']}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_modelo?['nome'] as String? ?? 'Modelo'), actions: [
        IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: _editar),
        PopupMenuButton<String>(
          tooltip: 'Mais opções',
          onSelected: (_) => _excluir(),
          itemBuilder: (_) => const [PopupMenuItem(value: 'excluir', child: Text('Excluir modelo'))],
        ),
      ]),
      body: EstadoTela<Map>(
        key: ValueKey(_versao),
        carregar: () async {
          final r = await buscarVarios(context, {
            'modelo': '/api/modelos/${widget.id}',
            'impressoes': '/api/impressoes',
            'pedidos': '/api/pedidos',
            'impressoras': '/api/impressoras',
            'filamentos': '/api/filamentos?incluir_excluidos=true',
            'insumos': '/api/insumos?incluir_excluidos=true',
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _modelo = mapa((r.dados as Map)['modelo']));
          });
          return r;
        },
        construir: (context, dados) => _corpo(dados),
      ),
    );
  }

  /// Receita: uma linha com gramas, tempo e mão de obra, depois cada peça impressa (com a cor) e os insumos.
  Widget _ficha(Json m, List filamentos, List insumos) {
    final r = mapa(m['receita']);
    final res = resumoReceita(r);
    final fraco = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Secao('Receita'),
      Text(
          [
            gramas(res.gramas),
            res.horas > 0 ? duracao(res.horas * 3600) : 'sem tempo',
            if (res.porImpressao > 1) '${res.porImpressao} por impressão',
            if (num0(r['mao_obra_min']) > 0) '${numero(num0(r['mao_obra_min']))} min de mão de obra',
          ].join(' · '),
          key: const Key('ficha'),
          style: const TextStyle(fontFeatures: tabular)),
      const SizedBox(height: 4),
      for (final (n, p) in lista(r['filamentos']).indexed)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: BolinhaCor(corHex(filamentos.where((f) => f['id'] == p['filamento_id']).firstOrNull?['cor_hex'])),
          title: Text('${p['nome'] ?? ''}'.isEmpty ? 'Peça ${n + 1}' : '${p['nome']}'),
          subtitle: Text([
            p['filamento_id'] == null
                ? 'Filamento avulso'
                : nomeFilamento(filamentos.where((f) => f['id'] == p['filamento_id']).firstOrNull),
            gramas(num0(p['gramas'])) + (res.porImpressao > 1 ? ' por mesa' : ''),
            if (num0(p['horas']) > 0) duracao(num0(p['horas']) * 3600),
          ].join(' · ')),
        ),
      for (final i in lista(r['insumos']))
        Builder(builder: (_) {
          final l = LinhaInsumo.deJson(i)..sincronizar(insumos);
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(l.embalagem ? Icons.redeem_outlined : Icons.inventory_2_outlined, size: 20),
            title: Text(l.nome.isEmpty ? 'Insumo' : l.nome),
            trailing: Text('${numero(l.qtd)} × ${moeda(l.custo)}', style: fraco.copyWith(fontFeatures: tabular)),
          );
        }),
    ]);
  }

  /// Preço em destaque; custo, lucro, estoque e vendidos numa linha cada. Substitui os 5 cartões.
  Widget _resumo(Json m, double custo, double? preco, double? lucro) {
    final t = Theme.of(context);
    final fraco = TextStyle(color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular);
    final estoque = num0(m['estoque']);
    final categoria = '${m['categoria'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Wrap: categoria comprida desce para a linha de baixo em vez de estourar a tela.
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(preco == null ? 'Sem preço' : moeda(preco),
                    key: const Key('preco'),
                    style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular)),
                if (categoria.isNotEmpty) Selo(categoria),
              ]),
          const SizedBox(height: 4),
          Wrap(spacing: 12, children: [
            Text('custo ${moeda(custo)}', style: fraco),
            if (lucro != null)
              Text('lucro ${moeda(lucro)}${preco != null && preco > 0 ? ' (${numero(lucro / preco * 100)}%)' : ''}',
                  key: const Key('lucro'),
                  style: TextStyle(color: corResultado(lucro), fontWeight: FontWeight.w600, fontFeatures: tabular)),
          ]),
          if (numOu(m['custo_real']) case final real?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'custo real ${moeda(real)}'
                '${custo > 0 ? ' (${real >= custo ? '+' : ''}${numero((real - custo) / custo * 100)}% do catálogo)' : ''}',
                key: const Key('custo-real'),
                style: fraco.copyWith(color: real > custo * 1.05 ? vermelho : null),
              ),
            ),
          const Divider(height: 24),
          Wrap(spacing: 20, runSpacing: 4, children: [
            Text.rich(TextSpan(children: [
              const WidgetSpan(child: Icon(Icons.inventory_2_outlined, size: 16)),
              TextSpan(text: ' ${numero(estoque)} em estoque'),
            ]), style: TextStyle(color: estoque < 0 ? vermelho : null, fontFeatures: tabular)),
            Text.rich(TextSpan(children: [
              const WidgetSpan(child: Icon(Icons.shopping_bag_outlined, size: 16)),
              TextSpan(text: ' ${numero(num0(m['vendidos']))} vendidos'),
            ]), style: const TextStyle(fontFeatures: tabular)),
          ]),
        ]),
      ),
    );
  }

  Widget _corpo(Map dados) {
    final m = mapa(dados['modelo']);
    final custo = custoDoJson(mapa(m['custo']));
    final preco = numOu(m['preco_venda']);
    final lucro = numOu(m['lucro_unitario']);
    final impressoras = [
      if (context.watch<Sessao>().dono)
        for (final i in lista(dados['impressoras'])) if ((i['moonraker_url'] ?? '') != '') i
    ];
    final impressoes = [for (final i in lista(dados['impressoes'])) if (i['modelo_id'] == widget.id) i];
    final vendas = [
      for (final p in lista(dados['pedidos']))
        for (final it in lista(p['itens']))
          if (it['modelo_id'] == widget.id) {'pedido': p, 'item': it}
    ];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ImagemApi(m['capa_url'] as String?, enquadramento: mapa(m['capa_ajuste']))),
            ),
            if (lista(m['arquivos']).any((a) => a['tipo'] == 'foto'))
              Positioned(
                right: 8,
                bottom: 8,
                child: IconButton.filledTonal(
                  key: const Key('ajustar_foto'),
                  tooltip: 'Ajustar foto',
                  onPressed: () async {
                    final ok = await Navigator.push<bool>(
                        context, MaterialPageRoute(builder: (_) => CapaTela(modelo: m)));
                    if (ok == true) _recarregar();
                  },
                  icon: const Icon(Icons.crop),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          if (receitaIncompleta(mapa(m['receita'])))
            Card(
              color: amarelo.withValues(alpha: 0.15),
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: amarelo),
                title: const Text('Faltam gramas ou tempo'),
                subtitle: const Text('O custo sai menor que o real'),
                trailing: TextButton(onPressed: _editar, child: const Text('Completar')),
              ),
            ),
          _resumo(m, custo.total, preco, lucro),
          if ((m['descricao'] ?? '') != '') Padding(padding: const EdgeInsets.only(top: 12), child: Text(m['descricao'] as String)),
          _ficha(m, lista(dados['filamentos']), lista(dados['insumos'])),
          MaisDetalhes(titulo: 'Custo detalhado', children: [QuebraCusto(custo)]),
          if (lista(m['links']).isNotEmpty) ...[
            const Secao('Links'),
            for (final l in lista(m['links']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link),
                title: Text((l['titulo'] ?? '') == '' ? '${l['url']}' : '${l['titulo']}', overflow: TextOverflow.ellipsis),
                onTap: () => launchUrl(Uri.parse('${l['url']}'), mode: LaunchMode.externalApplication),
              ),
          ],
          const Secao('Arquivos'),
          for (final a in lista(m['arquivos']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(iconeArquivo(a['tipo'] as String?)),
              title: Text('${a['nome_original']}', overflow: TextOverflow.ellipsis),
              subtitle: Text(tamanhoArquivo(num0(a['tamanho']))),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (a['tipo'] == 'gcode' && impressoras.isNotEmpty)
                  IconButton(
                    tooltip: impressoras.length == 1 ? 'Imprimir na ${impressoras.single['nome']}' : 'Imprimir',
                    icon: const Icon(Icons.print_outlined),
                    onPressed: se(() => _imprimir(a, impressoras)),
                  ),
                IconButton(tooltip: 'Baixar', icon: const Icon(Icons.download), onPressed: () => baixarArquivo(context, a)),
                IconButton(tooltip: 'Apagar', icon: const Icon(Icons.delete_outline), onPressed: () => _apagarArquivo(a)),
              ]),
            ),
          if (emVoo)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              // Ícone parado: o envio pode levar minutos e um indicador animado não ajuda mais que o texto.
              leading: Icon(Icons.upload),
              title: Text('Enviando para a impressora…'),
            ),
          const SizedBox(height: 8),
          EnvioArquivos(modeloId: widget.id, aoEnviar: _recarregar),
          // Histórico recolhido: abre quem quer conferir, sem empurrar o resto da tela para baixo.
          MaisDetalhes(titulo: 'Impressões (${impressoes.length})', children: [
            for (final i in impressoes.reversed.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${lerData(i['fim']) == null ? '' : dataCurta(lerData(i['fim'])!)} · ${i['pecas_boas'] ?? 0} peça(s)'),
                subtitle: Text('${i['status']}'.replaceAll('_', ' ')),
                trailing: i['custo_total'] == null ? null : Text(moeda(num0(i['custo_total']))),
                onTap: i['status'] != 'confirmada' && i['status'] != 'descartada'
                    ? null
                    : () async {
                        if (!await reabrirImpressao(context, i) || !mounted) return;
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ConfirmarTela(impressao: {...i, 'status': 'a_confirmar'})));
                        _recarregar();
                      },
              ),
          ]),
          MaisDetalhes(titulo: 'Vendas (${vendas.length})', children: [
            for (final v in vendas.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    '${numero(num0(v['item']!['quantidade']))} × ${moeda(num0(v['item']!['preco_unitario']))}'),
                subtitle: Text([
                  if (lerData(v['pedido']!['data']) != null) dataCurta(lerData(v['pedido']!['data'])!),
                  mapa(v['pedido']!['cliente'])['nome'] ?? 'Sem cliente',
                  '${v['pedido']!['status']}',
                ].join(' · ')),
              ),
          ]),
          const SizedBox(height: 48),
        ]),
      ),
    );
  }
}

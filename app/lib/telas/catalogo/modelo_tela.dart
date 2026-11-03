import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api.dart';
import '../../api/controle.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../impressora/envio.dart';
import 'arquivos.dart';
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
        IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
      ]),
      body: EstadoTela<Map>(
        key: ValueKey(_versao),
        carregar: () async {
          final r = await buscarVarios(context, {
            'modelo': '/api/modelos/${widget.id}',
            'impressoes': '/api/impressoes',
            'pedidos': '/api/pedidos',
            'impressoras': '/api/impressoras',
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
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(aspectRatio: 16 / 10, child: ImagemApi(m['capa_url'] as String?)),
          ),
          const SizedBox(height: 12),
          if ((m['categoria'] ?? '') != '' || (m['tags'] as List? ?? const []).isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: [
              if ((m['categoria'] ?? '') != '') Selo(m['categoria'] as String),
              for (final t in (m['tags'] as List? ?? const [])) Selo('#$t', cor: Theme.of(context).colorScheme.onSurfaceVariant),
            ]),
          if ((m['descricao'] ?? '') != '') Padding(padding: const EdgeInsets.only(top: 8), child: Text(m['descricao'] as String)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: CartaoValor('Preço', preco == null ? '—' : moeda(preco))),
            const SizedBox(width: 8),
            Expanded(child: CartaoValor('Custo', moeda(custo.total))),
            const SizedBox(width: 8),
            Expanded(child: CartaoValor('Lucro', lucro == null ? '—' : moeda(lucro), cor: lucro == null ? null : corResultado(lucro))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: CartaoValor('Em estoque', numero(num0(m['estoque'])),
                    cor: num0(m['estoque']) < 0 ? vermelho : null)),
            const SizedBox(width: 8),
            Expanded(child: CartaoValor('Vendidos', numero(num0(m['vendidos'])))),
          ]),
          const Secao('Custo'),
          QuebraCusto(custo),
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
          const Secao('Impressões'),
          if (impressoes.isEmpty) const Text('Nenhuma impressão registrada.'),
          for (final i in impressoes.reversed.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${lerData(i['fim']) == null ? '' : dataCurta(lerData(i['fim'])!)} · ${i['pecas_boas'] ?? 0} peça(s)'),
              subtitle: Text('${i['status']}'.replaceAll('_', ' ')),
              trailing: i['custo_total'] == null ? null : Text(moeda(num0(i['custo_total']))),
            ),
          const Secao('Vendas'),
          if (vendas.isEmpty) const Text('Nenhuma venda ainda.'),
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
          const SizedBox(height: 48),
        ]),
      ),
    );
  }
}

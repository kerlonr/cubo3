import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/fila.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import 'venda_rapida_tela.dart';

const nomesStatusPedido = {
  'orcamento': 'Orçamento',
  'aprovado': 'Aprovado',
  'produzindo': 'Produzindo',
  'pronto': 'Pronto',
  'entregue': 'Entregue',
  'cancelado': 'Cancelado',
};
/// Etapas pedidas pelo Kerlon; "pago" fica à parte. Pedidos antigos em Aprovado/Pronto seguem dali.
const fluxoPedido = ['orcamento', 'produzindo', 'entregue'];
const _etapaEquivalente = {'aprovado': 'orcamento', 'pronto': 'produzindo'};

/// Próximas etapas a partir do status atual (vazio para entregue/cancelado).
List<String> proximasEtapas(String status) {
  final i = fluxoPedido.indexOf(_etapaEquivalente[status] ?? status);
  return i < 0 ? const [] : fluxoPedido.sublist(i + 1);
}

/// Nome do item: o do modelo (mesmo excluído, marcado) ou a descrição.
String nomeItem(Map it) {
  final m = it['modelo'];
  if (m is Map) return m['excluido'] == true ? '${m['nome']} (excluído)' : '${m['nome']}';
  return '${it['descricao']}';
}

String resumoItens(Map p) {
  final itens = lista(p['itens']);
  if (itens.isEmpty) return 'Pedido';
  return itens.length == 1 ? nomeItem(itens.single) : '${nomeItem(itens.first)} +${itens.length - 1}';
}

/// Receita congelada se entregue; senão a conta dos itens.
double totalPedido(Map p) {
  if (p['receita'] != null) return num0(p['receita']);
  final bruto = lista(p['itens']).fold<double>(0, (s, i) => s + num0(i['quantidade']) * num0(i['preco_unitario']));
  return bruto - num0(p['desconto']) + num0(p['frete_cobrado']);
}

class PedidoTela extends StatefulWidget {
  const PedidoTela({super.key, required this.id});
  final String id;

  @override
  State<PedidoTela> createState() => _PedidoTelaState();
}

class _PedidoTelaState extends State<PedidoTela> {
  int _versao = 0;

  Future<void> _status(String novo) async {
    if (novo == 'cancelado' &&
        !await confirmar(context, 'Cancelar pedido?', 'Cancelado é final. Peças de um pedido entregue voltam ao estoque.',
            sim: 'Cancelar pedido')) {
      return;
    }
    if (!mounted) return;
    try {
      // Entregue guarda a hora em que foi entregue (vale a do aparelho, mesmo se for enviado depois pela fila).
      final op = novo == 'entregue'
          ? Operacao.nova('PUT', '/api/pedidos/${widget.id}',
              {'status': 'entregue', 'entregue_em': DateTime.now().toUtc().toIso8601String()})
          : Operacao.nova('POST', '/api/pedidos/${widget.id}/status', {'status': novo});
      final r = await context.read<FilaOffline>().enviarOuGuardar(op);
      if (!mounted) return;
      avisarEnvio(context, r, nomesStatusPedido[novo]!);
      if (r.recusada != null) return;
      await mostrarAvisos(context, r.resposta);
      setState(() => _versao++);
    } catch (e) {
      if (mounted) avisarErro(context, e); // 409 traz a regra ("entregue só pode ser cancelado")
    }
  }

  Future<void> _pago() async {
    if (await salvar(context, 'PUT', '/api/pedidos/${widget.id}', {'pago': true}, feito: 'Marcado como pago')) {
      setState(() => _versao++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pedido')),
      body: EstadoTela<Map>(
        key: ValueKey(_versao),
        carregar: () => buscar(context, '/api/pedidos/${widget.id}'),
        construir: (context, p) => _corpo(p),
      ),
    );
  }

  Widget _corpo(Map p) {
    final status = '${p['status']}';
    final proximos = proximasEtapas(status);
    Widget linha(String r, Object? v, {Color? cor, bool forte = false}) => v == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(r)),
              Text(moeda(num0(v)),
                  style: TextStyle(fontFeatures: tabular, color: cor, fontWeight: forte ? FontWeight.w600 : null)),
            ]),
          );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(
              child: Text(mapa(p['cliente'])['nome'] as String? ?? 'Sem cliente',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ),
            Selo(nomesStatusPedido[status] ?? status, cor: status == 'cancelado' ? vermelho : null),
          ]),
          if (lerData(p['entregue_em'] ?? p['data']) != null)
            Text(dataHora(lerData(p['entregue_em'] ?? p['data'])!)),
          const Secao('Itens'),
          for (final it in lista(p['itens']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(nomeItem(it)),
              subtitle: Text('${numero(num0(it['quantidade']))} × ${moeda(num0(it['preco_unitario']))}'),
              trailing: Text(moeda(num0(it['quantidade']) * num0(it['preco_unitario'])),
                  style: const TextStyle(fontFeatures: tabular)),
            ),
          const Divider(),
          if (p['receita'] != null) ...[
            linha('Itens', p['bruto']),
            if (num0(p['desconto']) > 0) linha('Desconto', -num0(p['desconto'])),
            if (num0(p['frete_cobrado']) > 0) linha('Frete cobrado', p['frete_cobrado']),
            linha('Receita', p['receita'], forte: true),
            linha('Custo das peças', -num0(p['custo_itens'])),
            if (num0(p['taxas']) > 0) linha('Taxas do canal', -num0(p['taxas'])),
            if (num0(p['custo_envio']) > 0) linha('Envio', -num0(p['custo_envio'])),
            linha('Lucro', p['lucro'], cor: corResultado(num0(p['lucro'])), forte: true),
          ] else
            linha('Total', totalPedido(p), forte: true),
          const SizedBox(height: 8),
          Text(p['pago'] == true ? 'Pago${p['forma_pagamento'] == null ? '' : ' · ${p['forma_pagamento']}'}' : 'Não pago',
              style: TextStyle(color: p['pago'] == true ? verde : amarelo)),
          if (p['pago'] != true && status != 'cancelado')
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _pago, child: const Text('Marcar como pago'))),
          if (proximos.isNotEmpty) ...[
            const Secao('Mudar status'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in proximos)
                s == proximos.first
                    ? FilledButton(onPressed: () => _status(s), child: Text(nomesStatusPedido[s]!))
                    : OutlinedButton(onPressed: () => _status(s), child: Text(nomesStatusPedido[s]!)),
            ]),
          ],
          if (status != 'cancelado')
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextButton(
                onPressed: () => _status('cancelado'),
                style: TextButton.styleFrom(foregroundColor: vermelho),
                child: const Text('Cancelar pedido'),
              ),
            ),
        ]),
      ),
    );
  }
}

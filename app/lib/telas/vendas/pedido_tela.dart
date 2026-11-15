import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/fila.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../dominio/mensagens.dart';
import 'clientes_tela.dart' show BotaoWhatsapp;
import 'comprovantes.dart';
import 'venda_rapida_tela.dart';

const nomesStatusPedido = {
  'orcamento': 'Orçamento',
  'aprovado': 'Aprovado',
  'produzindo': 'Produzindo',
  'pronto': 'Pronto',
  'entregue': 'Entregue',
  'cancelado': 'Cancelado',
};
const formasPagamento = ['Pix', 'Dinheiro', 'Cartão', 'Outro'];

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

/// Preços unitários novos para os itens somarem [alvo]: proporcional ao valor de cada linha (sem valor, igual por
/// unidade). A sobra de centavos vai no último item de 1 unidade (fecha exato); sem nenhum, no último.
List<double> distribuirTotal(List<({double quantidade, double preco})> itens, double alvo) {
  final soma = itens.fold<double>(0, (s, i) => s + i.quantidade * i.preco);
  final unidades = itens.fold<double>(0, (s, i) => s + i.quantidade);
  final precos = [for (final i in itens) arred2(soma > 0 ? i.preco * alvo / soma : alvo / unidades)];
  var k = itens.lastIndexWhere((i) => i.quantidade == 1);
  if (k < 0) k = itens.length - 1;
  var outros = 0.0;
  for (var j = 0; j < itens.length; j++) {
    if (j != k) outros += precos[j] * itens[j].quantidade;
  }
  precos[k] = arred2((alvo - outros) / itens[k].quantidade);
  if (precos[k] < 0) precos[k] = 0;
  return precos;
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

  /// Pergunta a forma (um toque) e marca pago; [pago] false desfaz (marcou errado).
  Future<void> _pago(bool pago) async {
    final forma = pago
        ? await showDialog<String>(
            context: context,
            builder: (c) => SimpleDialog(title: const Text('Como foi pago?'), children: [
              for (final f in formasPagamento)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, f),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(f)),
                ),
            ]),
          )
        : null;
    if (!mounted || (pago && forma == null)) return;
    if (!await salvar(context, 'PUT', '/api/pedidos/${widget.id}', {'pago': pago, 'forma_pagamento': forma},
            feito: pago ? 'Marcado como pago' : 'Voltou para a receber') ||
        !mounted) {
      return;
    }
    // Comprovante só sobe online: se o "pago" ficou guardado na fila, não oferece.
    if (pago && context.read<FilaOffline>().pendentes == 0) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('Marcado como pago'),
          behavior: SnackBarBehavior.floating,
          persist: false,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Anexar comprovante',
            onPressed: () async {
              if (await escolherComprovante(context, widget.id) && mounted) setState(() => _versao++);
            },
          ),
        ));
    }
    setState(() => _versao++);
  }

  /// Preços, desconto e frete (também em pedido entregue: o servidor recalcula receita e lucro).
  Future<void> _editarValores(Map p) async {
    final corpo = await showModalBottomSheet<Map>(
        context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => EditarValores(pedido: p));
    if (corpo == null || !mounted) return;
    if (await salvar(context, 'PUT', '/api/pedidos/${widget.id}', corpo,
            feito: 'Valores salvos', versaoBase: p['atualizado_em'] as String?) &&
        mounted) {
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
          if ('${mapa(p['cliente'])['telefone'] ?? ''}'.isNotEmpty && status != 'cancelado')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BotaoWhatsapp(
                  rotulo: 'Avisar no WhatsApp',
                  telefone: '${mapa(p['cliente'])['telefone']}',
                  texto: mensagemPedido(
                    nome: '${mapa(p['cliente'])['nome']}',
                    status: status,
                    itens: [
                      for (final it in lista(p['itens']))
                        '${nomeItem(it)}${num0(it['quantidade']) > 1 ? ' (${numero(num0(it['quantidade']))} un.)' : ''}'
                    ],
                    total: totalPedido(p),
                  ),
                ),
              ),
            ),
          Secao('Itens',
              acao: status == 'cancelado'
                  ? null
                  : IconButton(
                      tooltip: 'Editar valores',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editarValores(p))),
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
          Row(children: [
            Expanded(
              child: Text(
                  p['pago'] == true ? 'Pago${p['forma_pagamento'] == null ? '' : ' · ${p['forma_pagamento']}'}' : 'A receber',
                  style: TextStyle(color: p['pago'] == true ? verde : amarelo, fontWeight: FontWeight.w600)),
            ),
            if (p['pago'] == true)
              TextButton(onPressed: () => _pago(false), child: const Text('Desfazer pago'))
            else if (status != 'cancelado')
              FilledButton.tonal(onPressed: () => _pago(true), child: const Text('Marcar como pago')),
          ]),
          Comprovantes(pedidoId: widget.id, anexos: lista(p['anexos']), aoMudar: () => setState(() => _versao++)),
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

/// Folha de editar valores: "Total do pedido" (digitar 45 ajusta os preços) e o preço de cada item.
class EditarValores extends StatefulWidget {
  const EditarValores({super.key, required this.pedido});
  final Map pedido;

  @override
  State<EditarValores> createState() => _EditarValoresState();
}

class _EditarValoresState extends State<EditarValores> {
  late final _itens = lista(widget.pedido['itens']);
  late final _precos = [for (final it in _itens) ctrlDinheiro(num0(it['preco_unitario']))];
  late final _desconto = ctrlDinheiro(num0(widget.pedido['desconto']));
  late final _frete = ctrlDinheiro(num0(widget.pedido['frete_cobrado']));
  late final _total = ctrlDinheiro(_somaTotal());

  /// Preços de onde o total distribui (os do pedido ou os digitados à mão): sem isso, cada tecla
  /// redistribuiria o arredondamento da anterior.
  late var _base = [for (final it in _itens) num0(it['preco_unitario'])];

  double _v(TextEditingController c) => lerNumero(c.text) ?? 0;
  double _qtd(int k) => num0(_itens[k]['quantidade']);

  double _somaTotal() {
    var s = 0.0;
    for (var k = 0; k < _itens.length; k++) {
      s += _qtd(k) * _v(_precos[k]);
    }
    return s - _v(_desconto) + _v(_frete);
  }

  void _recalcular() {
    _base = [for (final c in _precos) _v(c)];
    _total.text = DinheiroFormatter.formatar(_somaTotal());
  }

  void _distribuir(String _) {
    final alvo = _v(_total) + _v(_desconto) - _v(_frete);
    if (_itens.isEmpty || alvo < 0) return;
    final novos = distribuirTotal([for (var k = 0; k < _itens.length; k++) (quantidade: _qtd(k), preco: _base[k])], alvo);
    for (var k = 0; k < _itens.length; k++) {
      _precos[k].text = DinheiroFormatter.formatar(novos[k]);
    }
  }

  @override
  void dispose() {
    for (final c in [..._precos, _desconto, _frete, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const Text('Editar valores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            CampoDinheiro(_total, 'Total do pedido',
                key: const Key('total-pedido'),
                aoMudar: _distribuir,
                ajuda: 'Os itens se ajustam ao total'),
            for (var k = 0; k < _itens.length; k++)
              CampoDinheiro(_precos[k],
                  _qtd(k) == 1 ? nomeItem(_itens[k]) : '${nomeItem(_itens[k])} · cada (${numero(_qtd(k))} un.)',
                  key: Key('preco$k'), aoMudar: (_) => _recalcular()),
            Row(children: [
              Expanded(child: CampoDinheiro(_desconto, 'Desconto', aoMudar: (_) => _recalcular())),
              const SizedBox(width: 12),
              Expanded(child: CampoDinheiro(_frete, 'Frete cobrado', aoMudar: (_) => _recalcular())),
            ]),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(context, {
                'itens': [
                  for (var k = 0; k < _itens.length; k++)
                    {
                      'id': _itens[k]['id'],
                      'modelo_id': _itens[k]['modelo_id'],
                      'descricao': _itens[k]['descricao'] ?? nomeItem(_itens[k]),
                      'quantidade': _itens[k]['quantidade'],
                      'preco_unitario': arred2(_v(_precos[k])),
                    }
                ],
                'desconto': arred2(_v(_desconto)),
                'frete_cobrado': arred2(_v(_frete)),
              }),
              child: const Text('Salvar'),
            ),
          ]),
        ),
      );
}

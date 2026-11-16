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
import 'pix.dart';
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
const iconesForma = {'Pix': Icons.pix, 'Dinheiro': Icons.payments_outlined, 'Cartão': Icons.credit_card};

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

/// Recebido e saldo vêm do servidor; pedido sem esses campos (cache antigo) segue o "pago" marcado.
double recebidoPedido(Map p) => numOu(p['recebido']) ?? (p['pago'] == true ? totalPedido(p) : 0);
double saldoPedido(Map p) => numOu(p['saldo']) ?? (p['pago'] == true ? 0 : totalPedido(p));

/// "Pago", "Parcial" ou "A receber"; null quando não há o que receber (orçamento sem sinal, cancelado).
String? seloPagamento(Map p) {
  if (p['status'] == 'cancelado') return null;
  final recebido = recebidoPedido(p);
  if (p['pago'] == true || (recebido > 0 && saldoPedido(p) < 0.005)) return 'Pago';
  if (recebido > 0) return 'Parcial';
  return p['status'] == 'orcamento' ? null : 'A receber';
}

const coresSeloPagamento = {'Pago': verde, 'Parcial': indigo, 'A receber': amarelo};

/// Itens como vão na mensagem ao cliente: "Vaso (2 un.)".
List<String> itensMensagem(Map p) => [
      for (final it in lista(p['itens']))
        '${nomeItem(it)}${num0(it['quantidade']) > 1 ? ' (${numero(num0(it['quantidade']))} un.)' : ''}'
    ];

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

  /// Reabrir um entregue (errou a entrega, o cliente devolveu): volta para Produzindo.
  Future<void> _reabrir() async {
    if (await confirmar(context, 'Reabrir pedido?', 'Volta para Produzindo e as peças voltam ao estoque.', sim: 'Reabrir') &&
        mounted) {
      await _status('produzindo');
    }
  }

  /// Nova parcela (padrão: o saldo) ou corrige uma ([pag]). Vai pela fila: o id nasce aqui.
  Future<void> _receber(Map p, [Json? pag]) async {
    final corpo = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FolhaPagamento(
          pedidoId: widget.id, pagamento: pag, maximo: saldoPedido(p) + (pag == null ? 0 : num0(pag['valor']))),
    );
    if (corpo == null || !mounted) return;
    if (await salvar(context, 'PUT', '/api/pedidos/${widget.id}/pagamentos/${pag?['id'] ?? novoId()}', corpo,
            feito: pag == null ? 'Recebido' : 'Pagamento salvo') &&
        mounted) {
      setState(() => _versao++);
    }
  }

  Future<void> _apagarPagamento(Map pag) async {
    if (!await confirmar(context, 'Apagar pagamento?', '${moeda(num0(pag['valor']))} sai do recebido.',
            sim: 'Apagar', cor: vermelho) ||
        !mounted) {
      return;
    }
    if (await salvar(context, 'DELETE', '/api/pagamentos/${pag['id']}', {}, feito: 'Pagamento apagado') && mounted) {
      setState(() => _versao++);
    }
  }

  /// Com parcelas, desfazer = apagar a última; pedido antigo (pago sem parcelas) volta pelo "pago" marcado.
  Future<void> _desfazerPago(Map p) async {
    final pags = lista(p['pagamentos']);
    if (pags.isNotEmpty) return _apagarPagamento(pags.last);
    if (await salvar(context, 'PUT', '/api/pedidos/${widget.id}', {'pago': false, 'forma_pagamento': null},
            feito: 'Voltou para a receber') &&
        mounted) {
      setState(() => _versao++);
    }
  }

  Future<void> _cobrar(Map p) {
    final cliente = mapa(p['cliente']);
    return cobrarPedido(context,
        pedidoId: widget.id,
        telefone: cliente['telefone'] as String?,
        mensagem: (valor, codigo) =>
            mensagemCobranca(nome: '${cliente['nome'] ?? ''}', itens: itensMensagem(p), valor: valor, codigo: codigo));
  }

  /// Itens, quantidades, preços, desconto e frete (também em pedido entregue: o servidor refaz a baixa do estoque,
  /// a receita e o lucro).
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

  /// "Recebido X de Y", a barra, as parcelas (tocar edita) e Receber / Cobrar no Pix.
  List<Widget> _pagamentos(Map p) {
    final aberto = p['status'] != 'cancelado';
    final pags = lista(p['pagamentos']);
    final total = numOu(p['total']) ?? totalPedido(p);
    final recebido = recebidoPedido(p);
    final saldo = saldoPedido(p);
    final selo = seloPagamento(p);
    if (!aberto && pags.isEmpty) return const [];
    return [
      Secao('Pagamentos',
          acao: aberto && saldo >= 0.005
              ? IconButton(tooltip: 'Cobrar no Pix', icon: const Icon(Icons.pix), onPressed: () => _cobrar(p))
              : null),
      Row(children: [
        Expanded(
          child: Text('Recebido ${moeda(recebido)} de ${moeda(total)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ),
        if (selo != null) Selo(selo, cor: coresSeloPagamento[selo]),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
            minHeight: 6, value: total > 0 ? (recebido / total).clamp(0, 1) : 1, color: saldo < 0.005 ? verde : null),
      ),
      for (final pag in pags)
        ListTile(
          key: ValueKey('pagamento-${pag['id']}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(iconesForma[pag['forma']] ?? Icons.attach_money),
          title: Text(moeda(num0(pag['valor'])), style: const TextStyle(fontFeatures: tabular)),
          subtitle: Text([
            if (lerData(pag['data']) != null) dataCurta(lerData(pag['data'])!),
            if ('${pag['forma'] ?? ''}'.isNotEmpty) '${pag['forma']}',
            if ('${pag['obs'] ?? ''}'.isNotEmpty) '${pag['obs']}',
          ].join(' · ')),
          onTap: aberto ? () => _receber(p, pag) : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (pag['anexo_id'] != null)
              const Tooltip(message: 'Com comprovante', child: Icon(Icons.receipt_long_outlined, size: 20)),
            IconButton(
                tooltip: 'Apagar pagamento', icon: const Icon(Icons.delete_outline), onPressed: () => _apagarPagamento(pag)),
          ]),
        ),
      if (aberto)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            if (selo == 'Pago') TextButton(onPressed: () => _desfazerPago(p), child: const Text('Desfazer pago')),
            const Spacer(),
            if (saldo >= 0.005)
              FilledButton.tonalIcon(
                  onPressed: () => _receber(p), icon: const Icon(Icons.payments_outlined), label: const Text('Receber')),
          ]),
        ),
    ];
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
            if (status == 'entregue')
              PopupMenuButton<void>(
                tooltip: 'Mais opções',
                itemBuilder: (_) => [
                  PopupMenuItem(
                    onTap: _reabrir,
                    child: const ListTile(leading: Icon(Icons.undo), title: Text('Reabrir pedido')),
                  ),
                ],
              ),
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
                    itens: itensMensagem(p),
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
          ..._pagamentos(p),
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

/// Uma linha da folha de editar: item do pedido ([item]) ou novo (modelo do catálogo ou avulso).
class _Linha {
  _Linha(this.item, {double preco = 0, this.qtd = 1})
      : modelo = item?['modelo_id'] as String?,
        preco = ctrlDinheiro(preco),
        base = preco;
  final Json? item;
  String? modelo;
  int qtd;
  final TextEditingController preco;
  final nome = TextEditingController();

  /// Preço de onde o total distribui (o do pedido ou o digitado à mão): sem isso, cada tecla
  /// redistribuiria o arredondamento da anterior.
  double base;

  String get descricao => item == null ? nome.text.trim() : '${item!['descricao'] ?? nomeItem(item!)}';
}

/// Folha de editar o pedido: "Total do pedido" (digitar 45 ajusta os preços), quantidade e preço de cada item,
/// tirar e adicionar item. Vale também no entregue (o servidor refaz a baixa do estoque).
class EditarValores extends StatefulWidget {
  const EditarValores({super.key, required this.pedido});
  final Map pedido;

  @override
  State<EditarValores> createState() => _EditarValoresState();
}

class _EditarValoresState extends State<EditarValores> {
  late final _linhas = [
    for (final it in lista(widget.pedido['itens']))
      _Linha(it, preco: num0(it['preco_unitario']), qtd: num0(it['quantidade']).round()),
  ];
  final _tiradas = <_Linha>[];
  late final _desconto = ctrlDinheiro(num0(widget.pedido['desconto']));
  late final _frete = ctrlDinheiro(num0(widget.pedido['frete_cobrado']));
  late final _total = ctrlDinheiro(_somaTotal());
  List<Json> _modelos = const [];

  @override
  void initState() {
    super.initState();
    _carregarModelos();
  }

  /// Catálogo para adicionar item; sem ele (erro), ainda dá para lançar item avulso.
  Future<void> _carregarModelos() async {
    try {
      final r = await buscar(context, '/api/modelos');
      if (mounted) setState(() => _modelos = [for (final m in lista(r.dados)) if (m['excluido'] != true) m]);
    } catch (_) {}
  }

  double _v(TextEditingController c) => lerNumero(c.text) ?? 0;

  double _somaTotal() =>
      _linhas.fold<double>(0, (s, l) => s + l.qtd * _v(l.preco)) - _v(_desconto) + _v(_frete);

  /// Quando as quantidades não fecham o total digitado em centavos (ex.: 3 un. por R$ 10,00), diz quanto fecha.
  String? _naoFecha;

  void _recalcular() {
    for (final l in _linhas) {
      l.base = _v(l.preco);
    }
    _total.text = DinheiroFormatter.formatar(_somaTotal());
    setState(() => _naoFecha = null);
  }

  void _distribuir(String _) {
    final alvo = _v(_total) + _v(_desconto) - _v(_frete);
    if (_linhas.isEmpty || alvo < 0) return;
    final novos = distribuirTotal([for (final l in _linhas) (quantidade: l.qtd.toDouble(), preco: l.base)], alvo);
    for (var k = 0; k < _linhas.length; k++) {
      _linhas[k].preco.text = DinheiroFormatter.formatar(novos[k]);
    }
    final fecha = _somaTotal();
    setState(() => _naoFecha = (fecha - _v(_total)).abs() >= 0.005 ? 'Com essas quantidades fecha em ${moeda(fecha)}' : null);
  }

  @override
  void dispose() {
    for (final l in [..._linhas, ..._tiradas]) {
      l.preco.dispose();
      l.nome.dispose();
    }
    for (final c in [_desconto, _frete, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _linha(int k) {
    final l = _linhas[k];
    final nome = l.item != null
        ? Text(nomeItem(l.item!), style: const TextStyle(fontWeight: FontWeight.w600))
        : DropdownMenu<String>(
            controller: l.nome,
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            requestFocusOnTap: true,
            label: const Text('Modelo ou descrição'),
            dropdownMenuEntries: [for (final m in _modelos) DropdownMenuEntry(value: m['id'] as String, label: '${m['nome']}')],
            onSelected: (v) {
              l.modelo = v;
              if (v == null) return; // texto livre: item avulso
              l.preco.text = DinheiroFormatter.formatar(numOu(_modelos.firstWhere((m) => m['id'] == v)['preco_venda']));
              _recalcular();
            },
          );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: nome),
          if (_linhas.length > 1)
            IconButton(
              tooltip: 'Tirar item',
              icon: const Icon(Icons.close),
              onPressed: () {
                _tiradas.add(_linhas.removeAt(k));
                _recalcular();
              },
            ),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Quantidade(
                key: Key('qtd$k'),
                valor: l.qtd,
                aoMudar: (v) {
                  l.qtd = v;
                  _recalcular();
                }),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: CampoDinheiro(l.preco, l.qtd == 1 ? 'Preço' : 'Preço cada',
                  key: Key('preco$k'), aoMudar: (_) => _recalcular())),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itens = [for (final l in _linhas) if (l.item != null || l.modelo != null || l.descricao.isNotEmpty) l];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Editar pedido', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          CampoDinheiro(_total, 'Total do pedido',
              key: const Key('total-pedido'), aoMudar: _distribuir, ajuda: _naoFecha ?? 'Os itens se ajustam ao total'),
          for (var k = 0; k < _linhas.length; k++) _linha(k),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: () => setState(() => _linhas.add(_Linha(null))),
                icon: const Icon(Icons.add),
                label: const Text('Item')),
          ),
          Row(children: [
            Expanded(child: CampoDinheiro(_desconto, 'Desconto', aoMudar: (_) => _recalcular())),
            const SizedBox(width: 12),
            Expanded(child: CampoDinheiro(_frete, 'Frete cobrado', aoMudar: (_) => _recalcular())),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _somaTotal() < 0 || itens.isEmpty
                ? null
                : () => Navigator.pop(context, {
                      'itens': [
                        for (final l in itens)
                          {
                            'id': l.item?['id'] ?? novoId(),
                            'modelo_id': l.modelo,
                            'descricao': l.descricao,
                            'quantidade': l.qtd,
                            'preco_unitario': arred2(_v(l.preco)),
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
}

/// Receber (parcela nova) ou corrigir uma: valor (padrão o que falta), forma, data e comprovante.
class FolhaPagamento extends StatefulWidget {
  const FolhaPagamento({super.key, required this.pedidoId, this.pagamento, required this.maximo});
  final String pedidoId;
  final Json? pagamento;

  /// O que ainda cabe (saldo, mais o valor da própria parcela ao editar).
  final double maximo;

  @override
  State<FolhaPagamento> createState() => _FolhaPagamentoState();
}

class _FolhaPagamentoState extends State<FolhaPagamento> {
  late final Json _p = widget.pagamento ?? {};
  late final _valor = ctrlDinheiro(numOu(_p['valor']) ?? widget.maximo);
  late final _obs = TextEditingController(text: _p['obs'] as String?);
  late String _forma = _p['forma'] as String? ?? 'Pix';
  late DateTime _data = lerData(_p['data'])?.toLocal() ?? DateTime.now();
  late String? _anexo = _p['anexo_id'] as String?;

  @override
  void dispose() {
    _valor.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
        context: context, initialDate: _data, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d != null) setState(() => _data = DateTime(d.year, d.month, d.day, _data.hour, _data.minute));
  }

  Future<void> _anexar() async {
    final id = await escolherComprovante(context, widget.pedidoId);
    if (id != null && mounted) setState(() => _anexo = id);
  }

  @override
  Widget build(BuildContext context) {
    final v = arred2(lerNumero(_valor.text) ?? 0);
    final passa = v > widget.maximo + 0.005;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.pagamento == null ? 'Receber' : 'Pagamento',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          CampoDinheiro(_valor, 'Valor',
              key: const Key('valor-pagamento'),
              aoMudar: (_) => setState(() {}),
              ajuda: passa ? 'Falta receber ${moeda(widget.maximo)}' : null),
          const SizedBox(height: 8),
          SeletorChips<String>(
              opcoes: {for (final f in formasPagamento) f: f}, valor: _forma, aoMudar: (f) => setState(() => _forma = f)),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
                onPressed: _escolherData, icon: const Icon(Icons.event_outlined), label: Text(dataCurta(_data))),
            const Spacer(),
            IconButton(
              tooltip: _anexo == null ? 'Anexar comprovante' : 'Comprovante anexado (trocar)',
              onPressed: _anexar,
              icon: Icon(_anexo == null ? Icons.attach_file : Icons.task_alt, color: _anexo == null ? null : verde),
            ),
          ]),
          MaisDetalhes(titulo: 'Observação', children: [CampoTexto(_obs, 'Observação')]),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: v <= 0 || passa
                ? null
                : () => Navigator.pop(context, {
                      'valor': v,
                      'data': _data.toUtc().toIso8601String(),
                      'forma': _forma,
                      if (_obs.text.trim().isNotEmpty) 'obs': _obs.text.trim(),
                      'anexo_id': _anexo,
                    }),
            child: Text(widget.pagamento == null ? 'Receber ${moeda(v)}' : 'Salvar'),
          ),
        ]),
      ),
    );
  }
}


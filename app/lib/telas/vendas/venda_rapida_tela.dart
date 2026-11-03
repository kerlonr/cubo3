import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/fila.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import 'clientes_tela.dart';

class _Item {
  String? modelo;
  String descricao = '';
  int qtd = 1;
  final preco = TextEditingController();
}

/// Mostra os avisos do servidor (ex.: estoque negativo) num diálogo amarelo.
Future<void> mostrarAvisos(BuildContext context, Object? resposta) async {
  final avisos = resposta is Map ? (resposta['avisos'] as List? ?? const []) : const [];
  if (avisos.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: amarelo),
      title: const Text('Atenção'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [for (final a in avisos) Text('$a')]),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
    ),
  );
}

/// Venda rápida (já entregue) ou novo pedido (orçamento): uma tela.
class VendaRapidaTela extends StatefulWidget {
  const VendaRapidaTela({super.key, this.orcamento = false, this.itensIniciais});

  final bool orcamento;

  /// Itens já preenchidos (ex.: vindo da calculadora): {descricao, preco_unitario, modelo_id?}.
  final List<Json>? itensIniciais;

  @override
  State<VendaRapidaTela> createState() => _VendaRapidaTelaState();
}

class _VendaRapidaTelaState extends State<VendaRapidaTela> {
  late final _itens = [
    for (final i in widget.itensIniciais ?? const <Json>[])
      _Item()
        ..modelo = i['modelo_id'] as String?
        ..descricao = '${i['descricao'] ?? ''}'
        ..preco.text = DinheiroFormatter.formatar(numOu(i['preco_unitario'])),
    if (widget.itensIniciais == null) _Item(),
  ];
  String? _canal;
  String? _cliente;
  late bool _pago = !widget.orcamento;
  final _envio = TextEditingController();
  final _frete = TextEditingController();
  final _desconto = TextEditingController();
  final _forma = TextEditingController();
  final _novosClientes = <Json>[];
  bool _enviando = false;

  double get _total =>
      _itens.fold<double>(0, (s, i) => s + i.qtd * (lerNumero(i.preco.text) ?? 0)) -
      (lerNumero(_desconto.text) ?? 0) +
      (lerNumero(_frete.text) ?? 0);

  Future<void> _salvar() async {
    final itens = [for (final i in _itens) if (i.modelo != null || i.descricao.isNotEmpty) i];
    if (itens.isEmpty) return avisar(context, 'Escolha o modelo');
    final fila = context.read<FilaOffline>();
    setState(() => _enviando = true);
    try {
      final r = await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/pedidos/${novoId()}', {
        'cliente_id': _cliente,
        'canal_id': _canal,
        'status': widget.orcamento ? 'orcamento' : 'entregue',
        if (!widget.orcamento) 'entregue_em': DateTime.now().toUtc().toIso8601String(),
        'pago': _pago,
        'custo_envio': lerNumero(_envio.text) ?? 0,
        'frete_cobrado': lerNumero(_frete.text) ?? 0,
        'desconto': lerNumero(_desconto.text) ?? 0,
        if (_forma.text.trim().isNotEmpty) 'forma_pagamento': _forma.text.trim(),
        'itens': [
          for (final i in itens)
            {
              'id': novoId(),
              'modelo_id': i.modelo,
              'descricao': i.descricao,
              'quantidade': i.qtd,
              'preco_unitario': lerNumero(i.preco.text) ?? 0,
            }
        ],
      }));
      if (!mounted) return;
      avisarEnvio(context, r, widget.orcamento ? 'Pedido criado' : 'Venda registrada');
      await mostrarAvisos(context, r.resposta);
      if (mounted) Navigator.maybePop(context, true);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _novoCliente() async {
    final c = await Navigator.push<Json>(context, MaterialPageRoute(builder: (_) => const ClienteForm()));
    if (c != null) {
      setState(() {
        _novosClientes.add(c);
        _cliente = c['id'] as String;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.orcamento ? 'Novo pedido' : 'Venda rápida')),
      body: EstadoTela<Map>(
        carregar: () => buscarVarios(context, {'modelos': '/api/modelos', 'canais': '/api/canais', 'clientes': '/api/clientes'}),
        construir: (context, d) => _corpo(d),
      ),
    );
  }

  Widget _corpo(Map d) {
    final modelos = [for (final m in lista(d['modelos'])) if (m['excluido'] != true) m];
    final canais = lista(d['canais']);
    final clientes = [...lista(d['clientes']), ..._novosClientes];
    _canal ??= canais.isEmpty
        ? null
        : (canais.firstWhere((c) => c['nome'] == 'Direto', orElse: () => canais.first)['id'] as String);
    return CorpoFormulario(children: [
      for (var i = 0; i < _itens.length; i++) _linhaItem(i, modelos),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
            onPressed: () => setState(() => _itens.add(_Item())), icon: const Icon(Icons.add), label: const Text('Item')),
      ),
      if (canais.length > 1)
        DropdownButtonFormField<String>(
          initialValue: _canal,
          decoration: const InputDecoration(labelText: 'Canal de venda'),
          items: [for (final c in canais) DropdownMenuItem(value: c['id'] as String, child: Text('${c['nome']}'))],
          onChanged: (v) => setState(() => _canal = v),
        ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: DropdownMenu<String>(
            key: ValueKey('cliente${_novosClientes.length}'),
            initialSelection: _cliente,
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            requestFocusOnTap: true,
            label: const Text('Cliente (opcional)'),
            dropdownMenuEntries: [
              for (final c in clientes) DropdownMenuEntry(value: c['id'] as String, label: '${c['nome']}'),
            ],
            onSelected: (v) => setState(() => _cliente = v),
          ),
        ),
        IconButton(tooltip: 'Novo cliente', onPressed: _novoCliente, icon: const Icon(Icons.person_add_alt)),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Pago'),
        value: _pago,
        onChanged: (v) => setState(() => _pago = v),
      ),
      MaisDetalhes(children: [
        CampoDinheiro(_envio, 'Custo de envio (você paga)'),
        CampoDinheiro(_frete, 'Frete cobrado do cliente', aoMudar: (_) => setState(() {})),
        CampoDinheiro(_desconto, 'Desconto', aoMudar: (_) => setState(() {})),
        CampoTexto(_forma, 'Forma de pagamento (Pix, dinheiro...)'),
      ]),
      const SizedBox(height: 12),
      Text('Total ${moeda(_total)}',
          textAlign: TextAlign.end, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, fontFeatures: tabular)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _enviando ? null : _salvar,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(widget.orcamento ? 'Criar pedido' : 'Registrar venda'),
      ),
    ]);
  }

  Widget _linhaItem(int i, List<Json> modelos) {
    final it = _itens[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: DropdownMenu<String>(
              key: Key('modelo$i'),
              initialSelection: it.modelo,
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              label: Text(it.modelo == null && it.descricao.isNotEmpty ? it.descricao : 'Modelo'),
              dropdownMenuEntries: [
                for (final m in modelos) DropdownMenuEntry(value: m['id'] as String, label: '${m['nome']}'),
              ],
              onSelected: (v) => setState(() {
                final m = modelos.firstWhere((x) => x['id'] == v);
                it.modelo = v;
                it.descricao = '${m['nome']}';
                it.preco.text = DinheiroFormatter.formatar(numOu(m['preco_venda']));
              }),
            ),
          ),
          if (_itens.length > 1)
            IconButton(onPressed: () => setState(() => _itens.removeAt(i)), icon: const Icon(Icons.close)),
        ]),
        Row(children: [
          IconButton.outlined(onPressed: it.qtd > 1 ? () => setState(() => it.qtd--) : null, icon: const Icon(Icons.remove)),
          SizedBox(
            width: 40,
            child: Text('${it.qtd}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFeatures: tabular)),
          ),
          IconButton.outlined(onPressed: () => setState(() => it.qtd++), icon: const Icon(Icons.add)),
          const SizedBox(width: 12),
          Expanded(child: CampoDinheiro(it.preco, 'Preço unitário', aoMudar: (_) => setState(() {}))),
        ]),
      ]),
    );
  }
}

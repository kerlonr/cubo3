import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../widgets/animacoes.dart';
import '../../widgets/estado_tela.dart';
import '../casca.dart';
import 'clientes_tela.dart';
import 'pedido_tela.dart';
import 'venda_rapida_tela.dart';

const _filtros = {
  'Orçamentos': {'orcamento'},
  'Em andamento': {'aprovado', 'produzindo', 'pronto'},
  'Entregues': {'entregue'},
  'Todos': <String>{},
};

class VendasAba extends StatefulWidget {
  const VendasAba({super.key});

  @override
  State<VendasAba> createState() => _VendasAbaState();
}

class _VendasAbaState extends State<VendasAba> {
  String _filtro = 'Entregues';
  // Na volta, todas as telas recarregam (o Início mostra a venda nova).
  Future<void> _abrir(Widget tela) => abrirTela(context, tela);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendas'), actions: [
        IconButton(tooltip: 'Clientes', icon: const Icon(Icons.people_outline), onPressed: () => _abrir(const ClientesTela())),
        IconButton(
            tooltip: 'Novo pedido', icon: const Icon(Icons.note_add_outlined), onPressed: () => _abrir(const VendaRapidaTela(orcamento: true))),
        IconButton(tooltip: 'Venda rápida', icon: const Icon(Icons.add), onPressed: () => _abrir(const VendaRapidaTela())),
      ]),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            for (final f in _filtros.keys)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(f), selected: _filtro == f, onSelected: (_) => setState(() => _filtro = f)),
              ),
          ]),
        ),
        Expanded(
          child: EstadoTela<List>(
            carregar: () => buscar(context, '/api/pedidos'),
            construir: (context, l) {
              final status = _filtros[_filtro]!;
              final pedidos = [for (final p in lista(l)) if (status.isEmpty || status.contains(p['status'])) p];
              if (pedidos.isEmpty) {
                return ListView(children: [
                  EstadoVazio(
                    icone: Icons.receipt_long_outlined,
                    titulo: lista(l).isEmpty ? 'Nenhuma venda ainda' : 'Nenhum pedido em "$_filtro"',
                    explicacao: 'Registre uma venda em poucos toques: escolha o modelo, a quantidade e pronto. '
                        'Para orçamento, use o ícone de novo pedido no topo.',
                    acao: 'Registrar venda',
                    aoTocar: () => _abrir(const VendaRapidaTela()),
                  ),
                ]);
              }
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
                    for (final (i, p) in pedidos.indexed)
                      Entrada(
                          key: ValueKey(p['id']),
                          ordem: i,
                          child: LinhaPedido(p, aoTocar: () => _abrir(PedidoTela(id: p['id'] as String)))),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

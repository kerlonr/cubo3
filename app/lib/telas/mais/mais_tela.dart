import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/sessao.dart';
import '../estoque/estoque_aba.dart';
import '../vendas/clientes_tela.dart';
import 'configuracoes_tela.dart';
import 'financeiro_tela.dart';

/// Tudo o que não cabe nas 4 abas. Empresa, custos, canais e impressoras ficam nas Configurações.
class MaisTela extends StatelessWidget {
  const MaisTela({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Sessao>();
    void abrir(Widget tela) => Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    return Scaffold(
      appBar: AppBar(title: const Text('Mais')),
      body: ListView(children: [
        ListTile(
          title: Text(s.eu?['nome'] as String? ?? ''),
          subtitle: Text('${s.empresaAtual?['nome'] ?? ''} · ${s.dono ? 'dono' : 'membro'}'),
        ),
        const Divider(),
        ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Estoque'), onTap: () => abrir(const EstoqueAba())),
        ListTile(leading: const Icon(Icons.people_outline), title: const Text('Clientes'), onTap: () => abrir(const ClientesTela())),
        ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Financeiro'),
            onTap: () => abrir(const FinanceiroTela())),
        ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Configurações'),
            onTap: () => abrir(const ConfiguracoesTela())),
        if (s.empresas.length > 1)
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Trocar de empresa'),
            onTap: () {
              Navigator.pop(context);
              s.trocarEmpresa();
            },
          ),
      ]),
    );
  }
}

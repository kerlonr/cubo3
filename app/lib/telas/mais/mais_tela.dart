import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/sessao.dart';
import '../vendas/clientes_tela.dart';
import 'calculadora_tela.dart';
import 'configuracoes_tela.dart';
import 'despesas_tela.dart';
import 'empresa_tela.dart';
import 'impressoras_tela.dart';

/// Tudo o que não cabe nas 5 abas.
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
        ListTile(leading: const Icon(Icons.people_outline), title: const Text('Clientes'), onTap: () => abrir(const ClientesTela())),
        ListTile(leading: const Icon(Icons.print_outlined), title: const Text('Impressoras'), onTap: () => abrir(const ImpressorasTela())),
        ListTile(
            leading: const Icon(Icons.calculate_outlined), title: const Text('Calculadora'), onTap: () => abrir(const CalculadoraTela())),
        ListTile(leading: const Icon(Icons.payments_outlined), title: const Text('Despesas'), onTap: () => abrir(const DespesasTela())),
        ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text('Empresa e usuários'),
            onTap: () => abrir(const EmpresaTela())),
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

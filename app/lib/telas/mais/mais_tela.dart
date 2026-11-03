import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/sessao.dart';

/// Tudo o que não cabe nas 5 abas.
class MaisTela extends StatelessWidget {
  const MaisTela({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Sessao>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mais')),
      body: ListView(children: [
        ListTile(
          title: Text(s.eu?['nome'] as String? ?? ''),
          subtitle: Text('${s.empresaAtual?['nome'] ?? ''} · ${s.dono ? 'dono' : 'membro'}'),
        ),
        const Divider(),
        if (s.empresas.length > 1)
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Trocar de empresa'),
            onTap: () {
              Navigator.pop(context);
              s.trocarEmpresa();
            },
          ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sair'),
          onTap: () {
            Navigator.pop(context);
            s.sair();
          },
        ),
      ]),
    );
  }
}

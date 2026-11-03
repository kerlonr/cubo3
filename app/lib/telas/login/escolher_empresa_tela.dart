import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/sessao.dart';
import 'login_tela.dart';

class EscolherEmpresaTela extends StatelessWidget {
  const EscolherEmpresaTela({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Sessao>();
    return MolduraEntrada(children: [
      const Text('Escolha a empresa', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      if (s.empresas.isEmpty) const Text('Você ainda não faz parte de nenhuma empresa. Peça acesso ao dono.'),
      for (final e in s.empresas)
        Card(
          child: ListTile(
            title: Text(e['nome'] as String),
            subtitle: Text(e['papel'] == 'dono' ? 'Dono' : 'Membro'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => s.escolherEmpresa(e['id'] as String),
          ),
        ),
      const SizedBox(height: 12),
      TextButton(onPressed: s.sair, child: const Text('Sair')),
    ]);
  }
}

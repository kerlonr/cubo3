import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/sessao.dart';
import 'login_tela.dart';

/// Primeiro login (senha inicial dada pelo dono) ou troca pelas Configurações.
class TrocarSenhaTela extends StatefulWidget {
  const TrocarSenhaTela({super.key, this.voluntaria = false});

  /// true quando aberta pelas Configurações (volta ao terminar).
  final bool voluntaria;

  @override
  State<TrocarSenhaTela> createState() => _TrocarSenhaTelaState();
}

class _TrocarSenhaTelaState extends State<TrocarSenhaTela> {
  final _atual = TextEditingController();
  final _nova = TextEditingController();
  final _repete = TextEditingController();
  String? _erro;
  bool _enviando = false;

  Future<void> _trocar() async {
    if (_nova.text.length < 8) return setState(() => _erro = 'A senha precisa ter pelo menos 8 caracteres');
    if (_nova.text != _repete.text) return setState(() => _erro = 'As senhas não conferem');
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.read<Sessao>().trocarSenha(_atual.text, _nova.text);
      if (widget.voluntaria && mounted) Navigator.pop(context);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MolduraEntrada(children: [
      Text(widget.voluntaria ? 'Trocar senha' : 'Crie sua senha',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      if (!widget.voluntaria) const Text('A senha inicial foi dada pelo dono da empresa. Escolha uma só sua.'),
      const SizedBox(height: 16),
      TextField(controller: _atual, obscureText: true, decoration: const InputDecoration(labelText: 'Senha atual')),
      const SizedBox(height: 12),
      TextField(controller: _nova, obscureText: true, decoration: const InputDecoration(labelText: 'Nova senha')),
      const SizedBox(height: 12),
      TextField(controller: _repete, obscureText: true, decoration: const InputDecoration(labelText: 'Repita a nova senha')),
      if (_erro != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      const SizedBox(height: 20),
      FilledButton(onPressed: _enviando ? null : _trocar, child: const Text('Salvar senha')),
      if (!widget.voluntaria) TextButton(onPressed: () => context.read<Sessao>().sair(), child: const Text('Sair')),
    ]);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api.dart';
import '../../api/sessao.dart';
import '../../config.dart';
import '../../main.dart' show chaveServidor;
import '../../widgets/logo.dart';

/// Cartão centralizado usado nas telas de entrada.
class MolduraEntrada extends StatelessWidget {
  const MolduraEntrada({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: LogoCubo3(tamanho: 44, comNome: true)),
                  const SizedBox(height: 32),
                  ...children,
                ]),
              ),
            ),
          ),
        ),
      );
}

class LoginTela extends StatefulWidget {
  const LoginTela({super.key});

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  String? _erro;
  bool _enviando = false;

  Future<void> _entrar() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await context.read<Sessao>().entrar(_email.text, _senha.text);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _servidor() async {
    final api = context.read<ApiCliente>();
    final c = TextEditingController(text: api.base.toString());
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Endereço do servidor'),
        content: TextField(controller: c, keyboardType: TextInputType.url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, servidorPadrao), child: const Text('Padrão')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
    if (novo == null || novo.isEmpty) return;
    api.base = Uri.parse(novo);
    await (await SharedPreferences.getInstance()).setString(chaveServidor, novo);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MolduraEntrada(children: [
      TextField(
        key: const Key('email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'E-mail'),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('senha'),
        controller: _senha,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(labelText: 'Senha'),
        onSubmitted: (_) => _entrar(),
      ),
      if (_erro != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _enviando ? null : _entrar,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Entrar'),
      ),
      if (!kIsWeb)
        TextButton(
          onPressed: _servidor,
          child: Text('Servidor: ${context.read<ApiCliente>().base.host}', style: const TextStyle(fontSize: 12)),
        ),
    ]);
  }
}

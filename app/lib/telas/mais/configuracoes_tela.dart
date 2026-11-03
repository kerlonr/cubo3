import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ao_vivo/servico_notificacao.dart';
import '../../api/api.dart';
import '../../api/fila.dart';
import '../../api/sessao.dart';
import '../../config.dart';
import '../../main.dart' show chaveServidor;
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../login/trocar_senha_tela.dart';

class ConfiguracoesTela extends StatefulWidget {
  const ConfiguracoesTela({super.key});

  @override
  State<ConfiguracoesTela> createState() => _ConfiguracoesTelaState();
}

class _ConfiguracoesTelaState extends State<ConfiguracoesTela> {
  String _versao = '';
  bool _monitor = false;

  @override
  void initState() {
    super.initState();
    ServicoNotificacao.ligado.then((v) {
      if (mounted) setState(() => _monitor = v);
    }).catchError((_) {});
    PackageInfo.fromPlatform()
        .then((i) => setState(() => _versao = '${i.version} (build ${i.buildNumber})'))
        .catchError((_) {});
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
    final fila = context.watch<FilaOffline>();
    final api = context.read<ApiCliente>();
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        const Secao('  Notificações'),
        if (kIsWeb)
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Avisar no navegador quando a impressão terminar'),
            subtitle: const Text('Funciona com esta aba aberta'),
            onTap: () async {
              final ok = await pedirPermissaoNavegador();
              if (context.mounted) avisar(context, ok ? 'Avisos ligados' : 'O navegador recusou os avisos');
            },
          )
        else
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Monitorar impressoras'),
            subtitle: const Text('Progresso na barra de notificações e alerta no fim, mesmo com o app fechado. '
                'Gasta um pouco mais de bateria.'),
            value: _monitor,
            onChanged: (v) async {
              if (v) {
                final erro = await ServicoNotificacao.ligar(api);
                if (erro != null && context.mounted) avisar(context, erro);
              } else {
                await ServicoNotificacao.desligar();
              }
              final agora = await ServicoNotificacao.ligado;
              if (mounted) setState(() => _monitor = agora);
            },
          ),
        if (!kIsWeb) ...[
          const Secao('  Servidor'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Endereço do servidor'),
            subtitle: Text(api.base.toString()),
            onTap: _servidor,
          ),
          const Secao('  Sem internet'),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(fila.pendentes == 0 ? 'Nada pendente' : '${fila.pendentes} alteração(ões) esperando internet'),
            trailing: fila.pendentes == 0 ? null : TextButton(onPressed: fila.esvaziar, child: const Text('Enviar agora')),
          ),
          for (final op in fila.operacoes)
            ListTile(
              dense: true,
              title: Text(descreverOperacao(op)),
              subtitle: Text('${op.metodo} · ${dataHora(op.criadaEm)}'),
              trailing: IconButton(
                tooltip: 'Descartar',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirmar(context, 'Descartar alteração?',
                      '${descreverOperacao(op)} não será enviada ao servidor. Isso não pode ser desfeito.',
                      sim: 'Descartar')) {
                    await fila.descartar(op);
                  }
                },
              ),
            ),
          for (final e in fila.erros)
            ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text(e.mensagem),
              subtitle: Text('${e.operacao.metodo} ${e.operacao.caminho} · ${dataHora(e.operacao.criadaEm)}'),
            ),
          if (fila.erros.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: fila.limparErros, child: const Text('Limpar erros')),
            ),
        ],
        const Secao('  Conta'),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Trocar senha'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrocarSenhaTela(voluntaria: true))),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sair'),
          onTap: () {
            Navigator.popUntil(context, (r) => r.isFirst);
            context.read<Sessao>().sair();
          },
        ),
        ListTile(leading: const Icon(Icons.info_outline), title: const Text('Versão'), subtitle: Text(_versao)),
      ]),
    );
  }
}

const _nomesRecurso = {
  'pedidos': 'Pedido',
  'clientes': 'Cliente',
  'impressoes': 'Impressão',
  'impressoras': 'Impressora',
  'modelos': 'Modelo',
  'filamentos': 'Filamento',
  'carreteis': 'Carretel',
  'insumos': 'Insumo',
  'movimentos': 'Movimento de estoque',
  'despesas': 'Despesa',
  'canais': 'Canal de venda',
};

/// `/api/impressoes/{id}/confirmar` → "Impressão · confirmar".
String descreverOperacao(Operacao op) {
  final p = op.caminho.split('/');
  final nome = p.length > 2 ? _nomesRecurso[p[2]] ?? p[2] : op.caminho;
  return p.length > 4 ? '$nome · ${p[4]}' : nome;
}

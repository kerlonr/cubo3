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
import '../../api/modelos.dart';
import '../../widgets/estado_tela.dart';
import '../login/trocar_senha_tela.dart';
import 'empresa_tela.dart';
import 'impressoras_tela.dart';

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

  void _abrir(Widget tela) => Navigator.push(context, MaterialPageRoute(builder: (_) => tela));

  Future<void> _custos() async {
    try {
      final cfg = mapa((await buscar(context, '/api/empresa/config')).dados);
      if (mounted) _abrir(ConfigEmpresaForm(dados: cfg));
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  /// Seção que abre outra tela: ícone, nome e uma linha dizendo para que serve.
  Widget _item(IconData icone, String titulo, String descricao, VoidCallback aoTocar) => ListTile(
        leading: Icon(icone, color: Theme.of(context).colorScheme.primary),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(descricao),
        trailing: const Icon(Icons.chevron_right),
        onTap: aoTocar,
      );

  /// Cabeçalho de seção com os ajustes logo abaixo.
  Widget _secao(IconData icone, String titulo, String descricao) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Row(children: [
          Icon(icone, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(descricao,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final fila = context.watch<FilaOffline>();
    final api = context.read<ApiCliente>();
    final dono = context.watch<Sessao>().dono;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        _item(Icons.business_outlined, 'Empresa', 'Seu Pix e quem tem acesso', () => _abrir(const EmpresaTela())),
        if (dono)
          _item(Icons.calculate_outlined, 'Custos', 'Mão de obra, energia e margens, com exemplo ao vivo', _custos),
        _item(Icons.storefront_outlined, 'Canais de venda', 'Onde você vende e quanto cada um cobra',
            () => _abrir(const CanaisTela())),
        _item(Icons.print_outlined, 'Impressoras', 'Custo de máquina e conexão com o Klipper',
            () => _abrir(const ImpressorasTela())),
        _secao(Icons.notifications_outlined, 'Notificações', 'Avisos de impressão terminando ou com problema'),
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
        _secao(Icons.person_outline, 'Conta', 'Sua senha e sair deste aparelho'),
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
        if (!kIsWeb) ...[
          _secao(Icons.tune, 'Avançado', 'Endereço do servidor e alterações esperando internet'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Endereço do servidor'),
            subtitle: Text(api.base.toString()),
            onTap: _servidor,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(fila.pendentes == 0 ? 'Nada pendente' : '${fila.pendentes} alteração(ões) esperando internet'),
            trailing: fila.pendentes == 0 ? null : TextButton(onPressed: () => fila.esvaziar(forcar: true), child: const Text('Enviar agora')),
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
              trailing: TextButton(onPressed: () => fila.tentarDeNovo(e), child: const Text('Tentar de novo')),
            ),
          if (fila.erros.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: fila.limparErros, child: const Text('Limpar erros')),
            ),
        ],
        ListTile(leading: const Icon(Icons.info_outline), title: const Text('Versão'), subtitle: Text(_versao)),
          ]),
        ),
      ),
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

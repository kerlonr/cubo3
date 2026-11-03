import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import 'pedido_tela.dart';

/// wa.me precisa do número com DDI; telefone brasileiro sem DDI ganha o 55.
Uri linkWhatsapp(String telefone) {
  final d = telefone.replaceAll(RegExp(r'\D'), '');
  return Uri.parse('https://wa.me/${d.length <= 11 ? '55$d' : d}');
}

class ClientesTela extends StatefulWidget {
  const ClientesTela({super.key});

  @override
  State<ClientesTela> createState() => _ClientesTelaState();
}

class _ClientesTelaState extends State<ClientesTela> {
  String _busca = '';
  int _versao = 0;

  Future<void> _abrir(Widget tela) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes'), actions: [
        IconButton(tooltip: 'Novo cliente', icon: const Icon(Icons.person_add_alt), onPressed: () => _abrir(const ClienteForm())),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar', isDense: true),
            onChanged: (v) => setState(() => _busca = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: EstadoTela<List>(
            key: ValueKey(_versao),
            carregar: () => buscar(context, '/api/clientes'),
            vazio: (l) => l.isEmpty,
            mensagemVazio: 'Nenhum cliente ainda.',
            construir: (context, l) {
              final clientes = [
                for (final c in lista(l))
                  if ('${c['nome']} ${c['telefone'] ?? ''} ${c['email'] ?? ''}'.toLowerCase().contains(_busca)) c
              ]..sort((a, b) => '${a['nome']}'.toLowerCase().compareTo('${b['nome']}'.toLowerCase()));
              return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
                for (final c in clientes)
                  Card(
                    child: ListTile(
                      title: Text('${c['nome']}'),
                      subtitle: Text([c['telefone'], c['email']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                      onTap: () => _abrir(ClienteTela(id: c['id'] as String)),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

/// Cadastro de cliente. Devolve o cliente salvo (para o cadastro rápido da venda).
class ClienteForm extends StatefulWidget {
  const ClienteForm({super.key, this.dados});
  final Json? dados;

  @override
  State<ClienteForm> createState() => _ClienteFormState();
}

class _ClienteFormState extends State<ClienteForm> {
  final _form = GlobalKey<FormState>();
  late final Json d = widget.dados ?? {};
  late final _nome = TextEditingController(text: d['nome'] as String?);
  late final _telefone = TextEditingController(text: d['telefone'] as String?);
  late final _email = TextEditingController(text: d['email'] as String?);
  late final _obs = TextEditingController(text: d['obs'] as String?);

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final dados = {'nome': _nome.text.trim(), 'telefone': v(_telefone), 'email': v(_email), 'obs': v(_obs)};
    final id = d['id'] as String? ?? novoId();
    if (await salvar(context, 'PUT', '/api/clientes/$id', dados) && mounted) {
      Navigator.pop(context, {...dados, 'id': id});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dados == null ? 'Novo cliente' : 'Editar cliente')),
      body: CorpoFormulario(chave: _form, children: [
        CampoTexto(_nome, 'Nome', obrigatorio: true),
        CampoTexto(_telefone, 'Telefone (WhatsApp)', teclado: TextInputType.phone),
        CampoTexto(_email, 'E-mail', teclado: TextInputType.emailAddress),
        MaisDetalhes(children: [CampoTexto(_obs, 'Observações', linhas: 3)]),
        const SizedBox(height: 16),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ]),
    );
  }
}

/// Perfil do cliente: total comprado, histórico de pedidos e WhatsApp.
class ClienteTela extends StatefulWidget {
  const ClienteTela({super.key, required this.id});
  final String id;

  @override
  State<ClienteTela> createState() => _ClienteTelaState();
}

class _ClienteTelaState extends State<ClienteTela> {
  int _versao = 0;

  Future<void> _abrir(Widget tela) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cliente')),
      body: EstadoTela<Map>(
        key: ValueKey(_versao),
        carregar: () => buscar(context, '/api/clientes/${widget.id}/historico'),
        construir: (context, h) {
          final c = mapa(h['cliente']);
          final telefone = '${c['telefone'] ?? ''}';
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text('${c['nome']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
              IconButton(
                  tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _abrir(ClienteForm(dados: c))),
            ]),
            if (c['email'] != null) Text('${c['email']}'),
            if (telefone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => launchUrl(linkWhatsapp(telefone), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text('WhatsApp $telefone'),
                  ),
                ),
              ),
            if (c['obs'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${c['obs']}')),
            const SizedBox(height: 12),
            CartaoValor('Total comprado', moeda(num0(h['total_comprado']))),
            const Secao('Pedidos'),
            for (final p in lista(h['pedidos'])) LinhaPedido(p, aoTocar: () => _abrir(PedidoTela(id: p['id'] as String))),
          ]);
        },
      ),
    );
  }
}

/// Linha de pedido usada nas listas (cliente, total, lucro).
class LinhaPedido extends StatelessWidget {
  const LinhaPedido(this.p, {super.key, this.aoTocar});
  final Json p;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final lucro = numOu(p['lucro']);
    final data = lerData(p['entregue_em']) ?? lerData(p['data']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: aoTocar,
        title: Text(mapa(p['cliente'])['nome'] as String? ?? resumoItens(p)),
        subtitle: Text([if (data != null) dataCurta(data), nomesStatusPedido[p['status']] ?? '${p['status']}'].join(' · ')),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(moeda(totalPedido(p)), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
          if (lucro != null)
            Text('lucro ${moeda(lucro)}', style: TextStyle(fontSize: 12, color: corResultado(lucro), fontFeatures: tabular)),
        ]),
      ),
    );
  }
}

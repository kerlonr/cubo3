import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/modelos.dart';
import '../../dominio/mensagens.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/animacoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import 'pedido_tela.dart';

/// wa.me precisa do número com DDI; telefone brasileiro sem DDI ganha o 55.
/// [texto] já abre a conversa com a mensagem escrita (o Kerlon só confere e envia).
Uri linkWhatsapp(String telefone, {String? texto}) {
  final d = telefone.replaceAll(RegExp(r'\D'), '');
  return Uri.https('wa.me', '/${d.length <= 11 ? '55$d' : d}', texto == null ? null : {'text': texto});
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
    final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    if (!mounted) return;
    if (r is Map && r['excluido'] == true) return Navigator.pop(context, true); // excluiu na edição
    setState(() => _versao++);
  }

  Widget _linha(Json c) {
    final nome = '${c['nome']}', telefone = '${c['telefone'] ?? ''}';
    return ListTile(
      leading: AvatarCliente(nome),
      title: Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(telefone.isNotEmpty ? formatarTelefone(telefone) : '${c['email'] ?? 'Sem contato'}'),
      trailing: telefone.isEmpty
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: 'WhatsApp',
              icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
              onPressed: () => launchUrl(linkWhatsapp(telefone, texto: mensagemCliente(nome)),
                  mode: LaunchMode.externalApplication),
            ),
      onTap: () => _abrir(ClienteTela(id: c['id'] as String)),
    );
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
            estadoVazio: EstadoVazio(
              icone: Icons.people_outline,
              titulo: 'Nenhum cliente ainda',
              explicacao: 'Nome e contato de quem compra, com os pedidos de cada um.',
              acao: 'Cadastrar cliente',
              aoTocar: () => _abrir(const ClienteForm()),
            ),
            construir: (context, l) {
              final clientes = [
                for (final c in lista(l))
                  if ('${c['nome']} ${c['telefone'] ?? ''} ${c['email'] ?? ''}'.toLowerCase().contains(_busca)) c
              ]..sort((a, b) => '${a['nome']}'.toLowerCase().compareTo('${b['nome']}'.toLowerCase()));
              if (clientes.isEmpty) {
                return ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Ninguém encontrado para "$_busca"', textAlign: TextAlign.center),
                  ),
                ]);
              }
              // Agrupa pela primeira letra (sem acento), como a agenda do celular.
              final grupos = <String, List<Json>>{};
              for (final c in clientes) {
                grupos.putIfAbsent(letraInicial('${c['nome']}'), () => []).add(c);
              }
              final t = Theme.of(context);
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
                    for (final (i, g) in grupos.entries.indexed) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(6, i == 0 ? 4 : 18, 6, 6),
                        child: Text(g.key,
                            style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      Entrada(
                        ordem: i,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(children: [
                            for (final (j, c) in g.value.indexed) ...[
                              if (j > 0) const Divider(indent: 72, height: 1),
                              _linha(c),
                            ],
                          ]),
                        ),
                      ),
                    ],
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
    if (await salvar(context, 'PUT', '/api/clientes/$id', dados, versaoBase: d['atualizado_em'] as String?) && mounted) {
      Navigator.pop(context, {...dados, 'id': id});
    }
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir cliente?', 'Os pedidos dele continuam, mostrando o nome.',
            sim: 'Excluir', cor: vermelho) ||
        !mounted) {
      return;
    }
    if (await salvar(context, 'DELETE', '/api/clientes/${d['id']}', {}, feito: 'Cliente excluído') && mounted) {
      Navigator.pop(context, {'excluido': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dados == null ? 'Novo cliente' : 'Editar cliente'), actions: [
        if (widget.dados != null)
          IconButton(tooltip: 'Excluir', onPressed: _excluir, icon: const Icon(Icons.delete_outline, color: vermelho)),
      ]),
      bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
      body: CorpoFormulario(chave: _form, children: [
        CampoTexto(_nome, 'Nome', obrigatorio: true),
        CampoTexto(_telefone, 'Telefone (WhatsApp)', teclado: TextInputType.phone),
        CampoTexto(_email, 'E-mail', teclado: TextInputType.emailAddress),
        MaisDetalhes(children: [CampoTexto(_obs, 'Observações', linhas: 3, dica: 'Endereço, preferências...')]),
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
              AvatarCliente('${c['nome']}', raio: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['nome']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  if (telefone.isNotEmpty) Text(formatarTelefone(telefone)),
                  if (c['email'] != null) Text('${c['email']}'),
                ]),
              ),
              IconButton(
                  tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _abrir(ClienteForm(dados: c))),
            ]),
            if (telefone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BotaoWhatsapp(
                      rotulo: 'Chamar no WhatsApp', telefone: telefone, texto: mensagemCliente('${c['nome']}')),
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
        title: Text(mapa(p['cliente'])['nome'] as String? ?? resumoItens(p), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text([if (data != null) dataCurta(data), nomesStatusPedido[p['status']] ?? '${p['status']}'].join(' · ')),
          if (seloPagamento(p) case final selo?) Selo(selo, cor: coresSeloPagamento[selo]),
        ]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(moeda(totalPedido(p)), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
          if (lucro != null)
            Text('lucro ${moeda(lucro)}', style: TextStyle(fontSize: 12, color: corResultado(lucro), fontFeatures: tabular)),
        ]),
      ),
    );
  }
}

/// "Ágata" → "A"; nome vazio ou que não começa com letra → "#".
String letraInicial(String nome) {
  final t = nome.trim();
  if (t.isEmpty) return '#';
  const sem = {'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'É': 'E', 'Ê': 'E', 'Í': 'I', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ú': 'U', 'Ç': 'C'};
  final l = t[0].toUpperCase();
  final base = sem[l] ?? l;
  return RegExp(r'[A-Z]').hasMatch(base) ? base : '#';
}

/// Iniciais em um círculo colorido (a cor sai do nome, então cada cliente fica sempre com a mesma).
class AvatarCliente extends StatelessWidget {
  const AvatarCliente(this.nome, {super.key, this.raio = 20});
  final String nome;
  final double raio;

  static const _cores = [Color(0xFF5E5CE6), Color(0xFF3F8CFF), Color(0xFF8E5CE6), Color(0xFF2BB3A3), Color(0xFFE0703D), Color(0xFFD9488F)];

  @override
  Widget build(BuildContext context) {
    final partes = nome.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final iniciais = partes.isEmpty
        ? '?'
        : (partes.first[0] + (partes.length > 1 ? partes.last[0] : '')).toUpperCase();
    return CircleAvatar(
      radius: raio,
      backgroundColor: _cores[nome.codeUnits.fold(0, (s, c) => s + c) % _cores.length],
      child: Text(iniciais, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: raio * 0.7)),
    );
  }
}

/// Abre o WhatsApp do cliente já com a mensagem escrita.
class BotaoWhatsapp extends StatelessWidget {
  const BotaoWhatsapp({super.key, required this.rotulo, required this.telefone, required this.texto});
  final String rotulo, telefone, texto;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
        onPressed: () => launchUrl(linkWhatsapp(telefone, texto: texto), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.chat_outlined),
        label: Text(rotulo),
      );
}

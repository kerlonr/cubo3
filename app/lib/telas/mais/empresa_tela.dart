import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../dominio/custos.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';

/// Empresa: quem tem acesso (só o dono adiciona e remove).
class EmpresaTela extends StatefulWidget {
  const EmpresaTela({super.key});

  @override
  State<EmpresaTela> createState() => _EmpresaTelaState();
}

class _EmpresaTelaState extends State<EmpresaTela> {
  int _versao = 0;

  void _recarregar([bool ok = true]) {
    if (ok) setState(() => _versao++);
  }

  Future<void> _adicionar() async {
    final nome = TextEditingController(), email = TextEditingController(), senha = TextEditingController();
    var papel = 'membro';
    final api = context.read<ApiCliente>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Adicionar usuário'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
              const SizedBox(height: 8),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail')),
              const SizedBox(height: 8),
              TextField(
                  controller: senha,
                  decoration: const InputDecoration(labelText: 'Senha inicial', helperText: 'A pessoa troca no primeiro login')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'membro', label: Text('Membro')),
                  ButtonSegment(value: 'dono', label: Text('Dono')),
                ],
                selected: {papel},
                onSelectionChanged: (s) => set(() => papel = s.first),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Adicionar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await api.post('/api/empresa/membros',
          {'nome': nome.text.trim(), 'email': email.text.trim(), 'senha_inicial': senha.text, 'papel': papel});
      if (mounted) avisar(context, 'Usuário adicionado');
      _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  Future<void> _remover(Json m) async {
    if (!await confirmar(context, 'Remover ${m['nome']}?', 'A pessoa perde o acesso a esta empresa.', sim: 'Remover')) {
      return;
    }
    if (!mounted) return;
    try {
      await context.read<ApiCliente>().delete('/api/empresa/membros/${m['id']}');
      _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dono = context.watch<Sessao>().dono;
    return Scaffold(
      appBar: AppBar(title: Text('${context.read<Sessao>().empresaAtual?['nome'] ?? 'Empresa'}')),
      body: EstadoTela<Map>(
        key: ValueKey(_versao),
        carregar: () => buscarVarios(context, {'membros': '/api/empresa/membros'}),
        construir: (context, d) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Secao('Usuários',
                    acao: dono ? TextButton(onPressed: _adicionar, child: const Text('Adicionar usuário')) : null),
                for (final m in lista(d['membros']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${m['nome']}'),
                    subtitle: Text('${m['email']} · ${m['papel']}'),
                    trailing: dono
                        ? IconButton(tooltip: 'Remover', icon: const Icon(Icons.person_remove_outlined), onPressed: () => _remover(m))
                        : null,
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Canais de venda com a taxa e o exemplo do que sobra numa venda de R$ 100.
class CanaisTela extends StatefulWidget {
  const CanaisTela({super.key});

  @override
  State<CanaisTela> createState() => _CanaisTelaState();
}

class _CanaisTelaState extends State<CanaisTela> {
  int _versao = 0;

  Future<void> _abrir(Widget tela) async {
    if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => tela)) == true) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Canais de venda'), actions: [
          IconButton(tooltip: 'Novo canal', icon: const Icon(Icons.add), onPressed: () => _abrir(const CanalForm())),
        ]),
        body: EstadoTela<List>(
          key: ValueKey(_versao),
          carregar: () => buscar(context, '/api/canais'),
          vazio: (l) => l.isEmpty,
          estadoVazio: EstadoVazio(
            icone: Icons.storefront_outlined,
            titulo: 'Nenhum canal de venda',
            explicacao: 'Canal é onde você vende (Direto, Shopee, Mercado Livre). A taxa de cada um entra no lucro.',
            acao: 'Cadastrar canal',
            aoTocar: () => _abrir(const CanalForm()),
          ),
          construir: (context, l) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
            for (final c in lista(l))
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${c['nome']}'),
                  subtitle: Text('${numero(num0(c['taxa_pct']))}% + ${moeda(num0(c['taxa_fixa']))} por venda\n'
                      '${exemploCanal(num0(c['taxa_pct']), num0(c['taxa_fixa']))}'),
                  onTap: () => _abrir(CanalForm(dados: c)),
                ),
              ),
          ]),
        ),
      );
}

class ConfigEmpresaForm extends StatefulWidget {
  const ConfigEmpresaForm({super.key, required this.dados});
  final Json dados;

  @override
  State<ConfigEmpresaForm> createState() => _ConfigEmpresaFormState();
}

class _ConfigEmpresaFormState extends State<ConfigEmpresaForm> {
  final _form = GlobalKey<FormState>();
  late final _eficiencia = ctrlNumero(numOu(widget.dados['eficiencia']) ?? 1.1);
  late final _maoObra = ctrlDinheiro(numOu(widget.dados['mao_obra_hora']) ?? 10);
  late final _kwh = ctrlNumero(numOu(widget.dados['kwh']) ?? 0.656);
  late final _reserva = ctrlNumero(numOu(widget.dados['reserva']) ?? 1.3);
  late final _margens = TextEditingController(
      text: (widget.dados['margens'] as List? ?? const [20, 30, 50]).map((m) => paraCampo(num0(m))).join('; '));

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final margens = [for (final m in _margens.text.split(';')) if (lerNumero(m) != null) lerNumero(m)];
    if (margens.isEmpty) return avisar(context, 'Informe ao menos uma margem');
    try {
      await context.read<ApiCliente>().put('/api/empresa/config', {
        'eficiencia': lerNumero(_eficiencia.text),
        'mao_obra_hora': lerNumero(_maoObra.text) ?? 0,
        'kwh': lerNumero(_kwh.text),
        'reserva': lerNumero(_reserva.text),
        'margens': margens,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  void _mudou([_]) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = ParamEmpresa(
      eficiencia: lerNumero(_eficiencia.text) ?? 1.1,
      maoObraHora: lerNumero(_maoObra.text) ?? 0,
      kwh: lerNumero(_kwh.text) ?? 0.656,
      reserva: lerNumero(_reserva.text) ?? 1.3,
    );
    // O caso da planilha: PLA a R$ 100/kg, 33 g, 3 h de impressão, 10 min de trabalho, impressora padrão.
    final exemplo = calcularCusto(const Receita([ItemFilamento(33, 100)], 3, 10), const ParamImpressora(), p);
    return Scaffold(
      appBar: AppBar(title: const Text('Custos da empresa')),
      bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
      body: CorpoFormulario(chave: _form, children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: Text('Uma peça de 33 g e 3 h custa ${moeda(exemplo.total)}'),
            subtitle: const Text('PLA a R\$ 100/kg e 10 min de trabalho. Muda na hora conforme você ajusta abaixo.'),
          ),
        ),
        const SizedBox(height: 8),
        CampoDinheiro(_maoObra, 'Mão de obra por hora',
            aoMudar: _mudou, ajuda: 'Quanto vale 1 hora do seu trabalho (preparar, tirar da mesa, acabamento).'),
        CampoNumero(_kwh, 'Energia',
            sufixo: 'R\$/kWh', obrigatorio: true, aoMudar: _mudou, ajuda: 'Preço do kWh na conta de luz.'),
        CampoTexto(_margens, 'Margens sugeridas (%)',
            ajuda: 'Separe com ";". A do meio é a usada para sugerir preço.', dica: '20; 30; 50'),
        MaisDetalhes(children: [
          CampoNumero(_eficiencia, 'Perda de material',
              obrigatorio: true, minimo: 0.01, aoMudar: _mudou, ajuda: '1,1 = 10% a mais de filamento (purga, falhas).'),
          CampoNumero(_reserva, 'Fator de reserva',
              obrigatorio: true, minimo: 0.01, aoMudar: _mudou, ajuda: '1,3 = 30% a mais no custo da máquina para imprevistos.'),
        ]),
      ]),
    );
  }
}

/// "Numa venda de R$ 100,00 você recebe R$ 76,00" (20 % + R$ 4).
String exemploCanal(num taxaPct, num taxaFixa) =>
    'Numa venda de ${moeda(100)} você recebe ${moeda(100 - taxaPct - taxaFixa)}';

class CanalForm extends StatefulWidget {
  const CanalForm({super.key, this.dados});
  final Json? dados;

  @override
  State<CanalForm> createState() => _CanalFormState();
}

class _CanalFormState extends State<CanalForm> {
  final _form = GlobalKey<FormState>();
  late final Json d = widget.dados ?? {};
  late final _nome = TextEditingController(text: d['nome'] as String?);
  late final _taxaPct = ctrlNumero(numOu(d['taxa_pct']));
  late final _taxaFixa = ctrlDinheiro(numOu(d['taxa_fixa']));

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final ok = await salvar(context, 'PUT', '/api/canais/${d['id'] ?? novoId()}', versaoBase: d['atualizado_em'] as String?, {
      'nome': _nome.text.trim(),
      'taxa_pct': lerNumero(_taxaPct.text) ?? 0,
      'taxa_fixa': lerNumero(_taxaFixa.text) ?? 0,
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir canal?', '${d['nome']}', sim: 'Excluir') || !mounted) return;
    if (await salvar(context, 'DELETE', '/api/canais/${d['id']}', {}, feito: 'Canal excluído') && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.dados == null ? 'Novo canal' : 'Editar canal'), actions: [
          if (widget.dados != null) IconButton(tooltip: 'Excluir', onPressed: _excluir, icon: const Icon(Icons.delete_outline)),
        ]),
        bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
        body: CorpoFormulario(chave: _form, children: [
          CampoTexto(_nome, 'Nome', obrigatorio: true, dica: 'Direto, Shopee, Mercado Livre...'),
          CampoNumero(_taxaPct, 'Taxa sobre a venda',
              key: const Key('taxa_pct'), sufixo: '%', aoMudar: (_) => setState(() {}), ajuda: 'Comissão do canal.'),
          CampoDinheiro(_taxaFixa, 'Taxa fixa por venda',
              key: const Key('taxa_fixa'), aoMudar: (_) => setState(() {}), ajuda: 'Valor cobrado em toda venda, se houver.'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(exemploCanal(lerNumero(_taxaPct.text) ?? 0, lerNumero(_taxaFixa.text) ?? 0)),
              subtitle: const Text('Use as taxas atuais do canal; o app não preenche valores "oficiais".'),
            ),
          ),
        ]),
      );
}

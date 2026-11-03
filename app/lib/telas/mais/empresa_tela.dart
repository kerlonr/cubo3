import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';

/// Empresa: usuários (só o dono mexe), custos da planilha e canais de venda.
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

  Future<void> _abrir(Widget tela) async =>
      _recarregar(await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => tela)) == true);

  @override
  Widget build(BuildContext context) {
    final dono = context.watch<Sessao>().dono;
    return Scaffold(
      appBar: AppBar(title: Text('${context.read<Sessao>().empresaAtual?['nome'] ?? 'Empresa'}')),
      body: EstadoTela<Map>(
        key: ValueKey(_versao),
        carregar: () =>
            buscarVarios(context, {'membros': '/api/empresa/membros', 'config': '/api/empresa/config', 'canais': '/api/canais'}),
        construir: (context, d) {
          final cfg = mapa(d['config']);
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
                Secao('Custos da empresa',
                    acao: dono
                        ? TextButton(onPressed: () => _abrir(ConfigEmpresaForm(dados: cfg)), child: const Text('Editar'))
                        : null),
                Text([
                  'Eficiência ${numero(num0(cfg['eficiencia']))}',
                  'Mão de obra ${moeda(num0(cfg['mao_obra_hora']))}/h',
                  'Energia ${moeda(num0(cfg['kwh']))}/kWh',
                  'Reserva ${numero(num0(cfg['reserva']))}',
                  'Margens ${(cfg['margens'] as List? ?? const []).map((m) => '${numero(num0(m))}%').join(' / ')}',
                ].join('\n')),
                Secao('Canais de venda',
                    acao: TextButton(onPressed: () => _abrir(const CanalForm()), child: const Text('Novo canal'))),
                for (final c in lista(d['canais']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${c['nome']}'),
                    subtitle: Text('${numero(num0(c['taxa_pct']))}% + ${moeda(num0(c['taxa_fixa']))} por venda'),
                    onTap: () => _abrir(CanalForm(dados: c)),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Custos da empresa')),
        body: CorpoFormulario(chave: _form, children: [
          CampoNumero(_eficiencia, 'Eficiência do material (perda)', obrigatorio: true, minimo: 0.01),
          CampoDinheiro(_maoObra, 'Mão de obra por hora'),
          CampoNumero(_kwh, 'Energia', sufixo: 'R\$/kWh', obrigatorio: true),
          CampoNumero(_reserva, 'Fator de reserva', obrigatorio: true, minimo: 0.01),
          CampoTexto(_margens, 'Margens sugeridas em % (separe com ;)'),
          const SizedBox(height: 16),
          FilledButton(onPressed: _salvar, child: const Text('Salvar')),
        ]),
      );
}

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
    final ok = await salvar(context, 'PUT', '/api/canais/${d['id'] ?? novoId()}', {
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
          if (widget.dados != null) IconButton(onPressed: _excluir, icon: const Icon(Icons.delete_outline)),
        ]),
        body: CorpoFormulario(chave: _form, children: [
          CampoTexto(_nome, 'Nome (Direto, Shopee, Mercado Livre...)', obrigatorio: true),
          CampoNumero(_taxaPct, 'Taxa', sufixo: '%'),
          CampoDinheiro(_taxaFixa, 'Taxa fixa por venda'),
          const Text('Digite as taxas atuais do canal; o app não pré-preenche valores "oficiais".',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _salvar, child: const Text('Salvar')),
        ]),
      );
}

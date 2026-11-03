import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';

const categoriasDespesa = {
  'equipamento': 'Equipamento',
  'manutencao': 'Manutenção',
  'energia': 'Energia',
  'ferramenta': 'Ferramenta',
  'outros': 'Outros',
};

class DespesasTela extends StatefulWidget {
  const DespesasTela({super.key});

  @override
  State<DespesasTela> createState() => _DespesasTelaState();
}

class _DespesasTelaState extends State<DespesasTela> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  int _versao = 0;

  Future<void> _abrir(Widget tela) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => tela));
    if (ok == true) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final nome = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    final prefixo = DateFormat('yyyy-MM').format(_mes);
    return Scaffold(
      appBar: AppBar(title: const Text('Despesas'), actions: [
        IconButton(tooltip: 'Nova despesa', icon: const Icon(Icons.add), onPressed: () => _abrir(const DespesaForm())),
      ]),
      body: Column(children: [
        Row(children: [
          IconButton(
              onPressed: () => setState(() => _mes = DateTime(_mes.year, _mes.month - 1)), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(nome[0].toUpperCase() + nome.substring(1),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
              onPressed: () => setState(() => _mes = DateTime(_mes.year, _mes.month + 1)), icon: const Icon(Icons.chevron_right)),
        ]),
        Expanded(
          child: EstadoTela<List>(
            key: ValueKey(_versao),
            carregar: () => buscar(context, '/api/despesas'),
            construir: (context, l) {
              final doMes = [for (final d in lista(l)) if ('${d['data']}'.startsWith(prefixo)) d]
                ..sort((a, b) => '${b['data']}'.compareTo('${a['data']}'));
              final total = doMes.fold<double>(0, (s, d) => s + num0(d['valor']));
              return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
                CartaoValor('Despesas do mês', moeda(total)),
                const SizedBox(height: 8),
                const Text('Compras de carretel e de insumo entram sozinhas nos gastos do painel.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                for (final d in doMes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('${d['descricao'] ?? categoriasDespesa[d['categoria']] ?? d['categoria']}'),
                      subtitle: Text('${dataCurta(DateTime.parse('${d['data']}'))} · ${categoriasDespesa[d['categoria']] ?? ''}'),
                      trailing: Text(moeda(num0(d['valor'])), style: const TextStyle(fontFeatures: tabular)),
                      onTap: () => _abrir(DespesaForm(dados: d)),
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

class DespesaForm extends StatefulWidget {
  const DespesaForm({super.key, this.dados});
  final Json? dados;

  @override
  State<DespesaForm> createState() => _DespesaFormState();
}

class _DespesaFormState extends State<DespesaForm> {
  final _form = GlobalKey<FormState>();
  late final Json d = widget.dados ?? {};
  late DateTime _data = d['data'] == null ? DateTime.now() : DateTime.parse('${d['data']}');
  late String _categoria = d['categoria'] as String? ?? 'outros';
  late final _valor = ctrlDinheiro(numOu(d['valor']));
  late final _descricao = TextEditingController(text: d['descricao'] as String?);

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final ok = await salvar(context, 'PUT', '/api/despesas/${d['id'] ?? novoId()}', {
      'data': diaIso(_data),
      'categoria': _categoria,
      'valor': lerNumero(_valor.text),
      'descricao': _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir despesa?', moeda(num0(d['valor'])), sim: 'Excluir') || !mounted) return;
    if (await salvar(context, 'DELETE', '/api/despesas/${d['id']}', {}, feito: 'Despesa excluída') && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.dados == null ? 'Nova despesa' : 'Editar despesa'), actions: [
          if (widget.dados != null)
            IconButton(onPressed: _excluir, icon: const Icon(Icons.delete_outline, color: vermelho)),
        ]),
        body: CorpoFormulario(chave: _form, children: [
          CampoDinheiro(_valor, 'Valor', obrigatorio: true),
          DropdownButtonFormField<String>(
            initialValue: _categoria,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [for (final e in categoriasDespesa.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _categoria = v!),
          ),
          CampoTexto(_descricao, 'Descrição'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(dataCurta(_data)),
            onTap: () async {
              final novo =
                  await showDatePicker(context: context, initialDate: _data, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (novo != null) setState(() => _data = novo);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _salvar, child: const Text('Salvar')),
        ]),
      );
}

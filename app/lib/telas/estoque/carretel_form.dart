import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';
import 'filamento_form.dart';

/// "Novo carretel": filamento, peso, preço pago e data (hoje). Local em mais detalhes.
class CarretelForm extends StatefulWidget {
  const CarretelForm({super.key, this.filamentoId});
  final String? filamentoId;

  @override
  State<CarretelForm> createState() => _CarretelFormState();
}

class _CarretelFormState extends State<CarretelForm> {
  final _form = GlobalKey<FormState>();
  final _peso = TextEditingController(text: '1000');
  final _preco = TextEditingController();
  final _local = TextEditingController();
  late String? _filamento = widget.filamentoId;
  DateTime _data = DateTime.now();
  int _versao = 0;

  Future<void> _salvar() async {
    if (_filamento == null) return avisar(context, 'Escolha o filamento');
    if (!_form.currentState!.validate()) return;
    final ok = await salvar(context, 'PUT', '/api/carreteis/${novoId()}', {
      'filamento_id': _filamento,
      'peso_inicial_g': lerNumero(_peso.text),
      'preco_pago': lerNumero(_preco.text),
      'data_compra': diaIso(_data),
      if (_local.text.trim().isNotEmpty) 'local': _local.text.trim(),
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _novoFilamento() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const FilamentoForm()));
    if (ok == true) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo carretel')),
      body: EstadoTela<List>(
        key: ValueKey(_versao),
        carregar: () => buscar(context, '/api/filamentos'),
        construir: (context, dados) {
          final filamentos = lista(dados);
          if (_filamento == null && filamentos.length == 1) _filamento = filamentos.single['id'] as String;
          return CorpoFormulario(chave: _form, children: [
            DropdownButtonFormField<String>(
              initialValue: filamentos.any((f) => f['id'] == _filamento) ? _filamento : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Filamento'),
              hint: Text(filamentos.isEmpty ? 'Cadastre um filamento primeiro' : 'Escolha'),
              items: [
                for (final f in filamentos)
                  DropdownMenuItem(value: f['id'] as String, child: Text(nomeFilamento(f), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _filamento = v),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _novoFilamento, icon: const Icon(Icons.add), label: const Text('Cadastrar filamento')),
            ),
            CampoNumero(_peso, 'Peso do filamento', key: const Key('peso'), sufixo: 'g', obrigatorio: true, minimo: 1),
            CampoDinheiro(_preco, 'Preço pago', key: const Key('preco'), obrigatorio: true),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Comprado em ${dataCurta(_data)}'),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _data, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) setState(() => _data = d);
              },
            ),
            MaisDetalhes(children: [CampoTexto(_local, 'Local (prateleira, caixa...)')]),
            const SizedBox(height: 16),
            FilledButton(onPressed: _salvar, child: const Text('Salvar')),
          ]);
        },
      ),
    );
  }
}

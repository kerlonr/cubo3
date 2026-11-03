import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';
import 'filamento_form.dart';

const _pesos = {250: '250 g', 500: '500 g', 1000: '1 kg', 0: 'Outro'};

/// "Novo carretel": filamento (o último usado já vem marcado), peso em chips, preço pago e data (hoje).
class CarretelForm extends StatefulWidget {
  const CarretelForm({super.key, this.filamentoId});
  final String? filamentoId;

  @override
  State<CarretelForm> createState() => _CarretelFormState();
}

class _CarretelFormState extends State<CarretelForm> {
  final _form = GlobalKey<FormState>();
  int _pesoChip = 1000;
  final _peso = TextEditingController();
  final _preco = TextEditingController();
  final _local = TextEditingController();
  late String? _filamento = widget.filamentoId;
  String? _ultimo;
  DateTime _data = DateTime.now();
  int _versao = 0;

  String get _chaveUltimo => 'ultimo_filamento:${context.read<ApiCliente>().empresaId}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _ultimo = p.getString(_chaveUltimo));
    });
  }

  Future<void> _salvar() async {
    if (_filamento == null) return avisar(context, 'Escolha o filamento');
    if (!_form.currentState!.validate()) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final ok = await salvar(context, 'PUT', '/api/carreteis/${novoId()}', {
      'filamento_id': _filamento,
      'peso_inicial_g': _pesoChip > 0 ? _pesoChip : lerNumero(_peso.text),
      'preco_pago': lerNumero(_preco.text),
      'data_compra': diaIso(_data),
      if (_local.text.trim().isNotEmpty) 'local': _local.text.trim(),
    });
    if (!ok || !mounted) return;
    await prefs.setString(_chaveUltimo, _filamento!);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _novoFilamento() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const FilamentoForm()));
    if (ok == true) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo carretel')),
      bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
      body: EstadoTela<List>(
        key: ValueKey(_versao),
        carregar: () => buscar(context, '/api/filamentos'),
        construir: (context, dados) {
          final filamentos = lista(dados);
          bool existe(String? id) => filamentos.any((f) => f['id'] == id);
          if (!existe(_filamento)) {
            _filamento = existe(_ultimo) ? _ultimo : (filamentos.length == 1 ? filamentos.single['id'] as String : null);
          }
          return CorpoFormulario(chave: _form, children: [
            CampoComAjuda(
              rotulo: 'Filamento',
              ajuda: 'O tipo que você comprou (marca, material e cor).',
              child: DropdownButtonFormField<String>(
                key: ValueKey(_filamento),
                initialValue: _filamento,
                isExpanded: true,
                hint: Text(filamentos.isEmpty ? 'Cadastre um filamento primeiro' : 'Escolha'),
                items: [
                  for (final f in filamentos)
                    DropdownMenuItem(
                        value: f['id'] as String, child: Text(nomeFilamento(f), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _filamento = v),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _novoFilamento, icon: const Icon(Icons.add), label: const Text('Cadastrar filamento')),
            ),
            CampoComAjuda(
              rotulo: 'Peso do filamento',
              ajuda: 'Só o filamento, sem o carretel (vem escrito na caixa).',
              child: SeletorChips<int>(
                  opcoes: _pesos, valor: _pesoChip, aoMudar: (p) => setState(() => _pesoChip = p)),
            ),
            if (_pesoChip == 0)
              CampoNumero(_peso, 'Quantos gramas?', key: const Key('peso'), sufixo: 'g', obrigatorio: true, minimo: 1),
            CampoDinheiro(_preco, 'Preço pago',
                key: const Key('preco'), obrigatorio: true, ajuda: 'Com frete, se houver: entra no custo de cada grama.'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Comprado em ${dataCurta(_data)}'),
              subtitle: const Text('Toque para mudar'),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _data, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) setState(() => _data = d);
              },
            ),
            MaisDetalhes(children: [CampoTexto(_local, 'Onde fica', dica: 'Prateleira, caixa...')]),
          ]);
        },
      ),
    );
  }
}

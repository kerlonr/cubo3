import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';
import 'filamento_form.dart';

const _pesos = {250: '250 g', 500: '500 g', 1000: '1 kg', 0: 'Outro'};

/// "Novo carretel": filamento (o último usado já vem marcado), peso em chips, preço pago e data (hoje).
/// Com [dados]: corrige preço, peso, data e local de um carretel já cadastrado (o gasto no financeiro acompanha).
class CarretelForm extends StatefulWidget {
  const CarretelForm({super.key, this.filamentoId, this.dados});
  final String? filamentoId;
  final Json? dados;

  @override
  State<CarretelForm> createState() => _CarretelFormState();
}

class _CarretelFormState extends State<CarretelForm> {
  final _form = GlobalKey<FormState>();
  late final Json? _d = widget.dados;
  late int _pesoChip =
      _d == null ? 1000 : _pesos.keys.firstWhere((p) => p == num0(_d['peso_inicial_g']), orElse: () => 0);
  late final _peso = _pesoChip == 0 ? ctrlNumero(numOu(_d?['peso_inicial_g'])) : TextEditingController();
  late final _preco = ctrlDinheiro(numOu(_d?['preco_pago']));
  late final _local = TextEditingController(text: _d?['local'] as String?);
  late String? _filamento = _d?['filamento_id'] as String? ?? widget.filamentoId;
  String? _ultimo;
  late DateTime _data = DateTime.tryParse('${_d?['data_compra']}') ?? DateTime.now();
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
    final local = _local.text.trim();
    final ok = await salvar(context, 'PUT', '/api/carreteis/${_d?['id'] ?? novoId()}', versaoBase: _d?['atualizado_em'] as String?, {
      if (_d == null) 'filamento_id': _filamento,
      'peso_inicial_g': _pesoChip > 0 ? _pesoChip : lerNumero(_peso.text),
      'preco_pago': lerNumero(_preco.text),
      'data_compra': diaIso(_data),
      if (local.isNotEmpty || _d != null) 'local': local.isEmpty ? null : local,
    });
    if (!ok || !mounted) return;
    if (_d == null) await prefs.setString(_chaveUltimo, _filamento!);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _excluir() async {
    if (!await confirmar(
            context,
            'Excluir carretel?',
            'O gasto de ${moeda(num0(_d!['preco_pago']))} sai do financeiro e o carretel some do estoque. '
                'Use para carretel cadastrado por engano; se ele só acabou, arquive.',
            sim: 'Excluir',
            cor: vermelho) ||
        !mounted) {
      return;
    }
    if (await salvar(context, 'DELETE', '/api/carreteis/${_d['id']}', {}, feito: 'Carretel excluído') && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _novoFilamento() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const FilamentoForm()));
    if (ok == true) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_d == null ? 'Novo carretel' : 'Editar carretel'), actions: [
        if (_d != null)
          IconButton(tooltip: 'Excluir', onPressed: _excluir, icon: const Icon(Icons.delete_outline, color: vermelho)),
      ]),
      bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
      body: EstadoTela<List>(
        key: ValueKey(_versao),
        carregar: () => buscar(context, '/api/filamentos'),
        construir: (context, dados) {
          final filamentos = lista(dados);
          bool existe(String? id) => filamentos.any((f) => f['id'] == id);
          if (_d == null && !existe(_filamento)) {
            _filamento = existe(_ultimo) ? _ultimo : (filamentos.length == 1 ? filamentos.single['id'] as String : null);
          }
          return CorpoFormulario(chave: _form, children: [
            // Na edição o filamento fica: o que muda é o que foi digitado errado (preço, peso, data, local).
            if (_d != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: BolinhaCor(corHex(mapa(_d['filamento'])['cor_hex'])),
                title: Text(nomeFilamento(mapa(_d['filamento']))),
                subtitle: Text('Saldo agora: ${gramas(num0(_d['saldo_g']))}'),
              )
            else ...[
            SeletorFilamento(
                filamentos: filamentos,
                valor: _filamento,
                comAvulso: false,
                aoMudar: (v) => setState(() => _filamento = v)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _novoFilamento, icon: const Icon(Icons.add), label: const Text('Cadastrar filamento')),
            ),
            ],
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

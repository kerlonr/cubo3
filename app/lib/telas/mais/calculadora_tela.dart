import 'package:flutter/material.dart';

import '../../api/cache.dart';
import '../../api/modelos.dart';
import '../../dominio/custos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';
import '../catalogo/modelo_form.dart';
import '../vendas/venda_rapida_tela.dart';

class _LinhaFilamento extends LinhaReceita {
  _LinhaFilamento(super.id, super.qtd);
  final precoKg = TextEditingController();
}

/// "Orçar peça": custo, preços pelas margens e por canal. Funciona sem internet
/// (cadastros do cache ou, sem cache nenhum, os padrões da planilha e preço avulso).
class CalculadoraTela extends StatefulWidget {
  const CalculadoraTela({super.key});

  @override
  State<CalculadoraTela> createState() => _CalculadoraTelaState();
}

class _CalculadoraTelaState extends State<CalculadoraTela> {
  final _filamentos = [_LinhaFilamento(null, null)];
  final _insumos = <LinhaReceita>[];
  final _horas = TextEditingController();
  final _maoObra = TextEditingController();
  final _envio = TextEditingController();
  String? _impressora;
  bool _iniciado = false;

  void _mudou([_]) => setState(() {});

  Json get _receita => {
        'filamentos': [
          for (final f in _filamentos)
            {'filamento_id': f.id, 'preco_kg': lerNumero(f.precoKg.text) ?? 0, 'gramas': lerNumero(f.qtd.text) ?? 0}
        ],
        'horas': lerNumero(_horas.text) ?? 0,
        'mao_obra_min': lerNumero(_maoObra.text) ?? 0,
        'insumos': [
          for (final i in _insumos)
            if (i.id != null) {'insumo_id': i.id, 'qtd': lerNumero(i.qtd.text) ?? 0}
        ],
        'custo_envio': lerNumero(_envio.text) ?? 0,
      };

  Future<RespostaCache> _carregar() async {
    try {
      return await buscarVarios(context, {...caminhosCusto, 'canais': '/api/canais'});
    } catch (_) {
      return RespostaCache(const {}, true, DateTime.now()); // nunca abriu online: padrões da planilha
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orçar peça')),
      body: EstadoTela<Map>(carregar: _carregar, construir: (context, cad) => _corpo(cad)),
    );
  }

  Widget _corpo(Map cad) {
    final filamentos = lista(cad['filamentos']);
    final insumos = lista(cad['insumos']);
    final impressoras = lista(cad['impressoras']);
    final canais = lista(cad['canais']);
    final config = mapa(cad['config']);
    if (!_iniciado) {
      _iniciado = true;
      if (filamentos.length == 1) _filamentos.first.id = filamentos.single['id'] as String;
    }
    final custo = custoDaReceita(_receita,
        filamentos: filamentos, insumos: insumos, impressoras: impressoras, config: config, impressoraId: _impressora);
    final emp = ParamEmpresa.fromJson(config);
    final precoMeio = precoComMargem(custo.total, emp.margemMeio);

    return CorpoFormulario(children: [
      for (var i = 0; i < _filamentos.length; i++)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(children: [
              DropdownButtonFormField<String?>(
                initialValue: _filamentos[i].id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Filamento'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Preço avulso')),
                  for (final f in filamentos)
                    DropdownMenuItem<String?>(value: f['id'] as String, child: Text(nomeFilamento(f), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _filamentos[i].id = v),
              ),
              if (_filamentos[i].id == null) CampoDinheiro(_filamentos[i].precoKg, 'Preço por kg', aoMudar: _mudou),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 96, child: CampoNumero(_filamentos[i].qtd, 'Gramas', key: Key('gramas$i'), sufixo: 'g', aoMudar: _mudou)),
          if (_filamentos.length > 1)
            IconButton(onPressed: () => setState(() => _filamentos.removeAt(i)), icon: const Icon(Icons.close)),
        ]),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _filamentos.add(_LinhaFilamento(null, null))),
          icon: const Icon(Icons.add),
          label: const Text('Outro filamento'),
        ),
      ),
      Row(children: [
        Expanded(child: CampoNumero(_horas, 'Tempo de impressão', key: const Key('horas'), sufixo: 'h', aoMudar: _mudou)),
        const SizedBox(width: 12),
        Expanded(child: CampoNumero(_maoObra, 'Mão de obra', key: const Key('mao_obra'), sufixo: 'min', aoMudar: _mudou)),
      ]),
      MaisDetalhes(children: [
        for (var i = 0; i < _insumos.length; i++)
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _insumos[i].id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Insumo / embalagem'),
                items: [for (final x in insumos) DropdownMenuItem(value: x['id'] as String, child: Text('${x['nome']}'))],
                onChanged: (v) => setState(() => _insumos[i].id = v),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: CampoNumero(_insumos[i].qtd, 'Qtd', aoMudar: _mudou)),
            IconButton(onPressed: () => setState(() => _insumos.removeAt(i)), icon: const Icon(Icons.close)),
          ]),
        if (insumos.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: () => setState(() => _insumos.add(LinhaReceita(null, 1))),
                icon: const Icon(Icons.add),
                label: const Text('Insumo')),
          ),
        CampoDinheiro(_envio, 'Custo médio de envio', aoMudar: _mudou),
        if (impressoras.length > 1)
          DropdownButtonFormField<String>(
            initialValue: _impressora,
            decoration: const InputDecoration(labelText: 'Impressora'),
            items: [for (final x in impressoras) DropdownMenuItem(value: x['id'] as String, child: Text('${x['nome']}'))],
            onChanged: (v) => setState(() => _impressora = v),
          ),
      ]),
      const SizedBox(height: 12),
      CartaoValor('Custo', moeda(custo.total)),
      const SizedBox(height: 8),
      QuebraCusto(custo),
      const Secao('Preço sugerido'),
      Row(children: [
        for (final m in emp.margens)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CartaoValor('Margem ${numero(m)}%', moeda(precoComMargem(custo.total, m))),
            ),
          ),
      ]),
      if (canais.isNotEmpty) ...[
        Secao('Por canal (margem ${numero(emp.margemMeio)}%)'),
        Card(
          child: Column(children: [
            for (final c in canais) _linhaCanal(c, custo.total, emp.margemMeio),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ModeloForm(dados: {
                          'receita': {
                            ..._receita,
                            'filamentos': [
                              for (final f in _receita['filamentos'] as List)
                                if (f['filamento_id'] != null) {'filamento_id': f['filamento_id'], 'gramas': f['gramas']}
                            ],
                          },
                          'preco_venda': precoMeio,
                          'impressora_id': _impressora,
                        }))),
            child: const Text('Virar modelo'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => VendaRapidaTela(orcamento: true, itensIniciais: [
                          {'descricao': 'Peça orçada', 'preco_unitario': precoMeio}
                        ]))),
            child: const Text('Virar orçamento'),
          ),
        ),
      ]),
    ]);
  }

  Widget _linhaCanal(Json c, double custo, double margem) {
    final taxaPct = num0(c['taxa_pct']), taxaFixa = num0(c['taxa_fixa']);
    final preco = precoComCanal(custo, margem, taxaPct, taxaFixa);
    final lucro = preco == null ? null : lucroVenda(preco, custo, taxaPct, taxaFixa);
    return ListTile(
      title: Text('${c['nome']}'),
      subtitle: Text('taxa ${numero(taxaPct)}% + ${moeda(taxaFixa)}'),
      trailing: preco == null
          ? const Text('inviável', style: TextStyle(color: vermelho))
          : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(moeda(preco), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
              Text('lucro ${moeda(lucro!)}', style: TextStyle(fontSize: 12, color: corResultado(lucro), fontFeatures: tabular)),
            ]),
    );
  }
}

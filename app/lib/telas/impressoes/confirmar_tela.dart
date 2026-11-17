import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/fila.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';

/// Gramas por filamento a partir da estimativa do fatiador. Se só veio o total e há várias cores,
/// divide igualmente em centavos de grama (a soma fecha com o total) e pede para conferir.
({List<double?> gramas, bool aviso}) dividirEstimativa(Map estimativa) {
  final fils = lista(estimativa['filamentos']);
  final total = numOu(estimativa['gramas_total']);
  if (fils.isEmpty) return (gramas: [total], aviso: false);
  if (fils.every((f) => f['gramas'] != null)) return (gramas: [for (final f in fils) num0(f['gramas'])], aviso: false);
  if (total == null) return (gramas: [for (final _ in fils) null], aviso: true);
  final centesimos = (arred2(total) * 100).round();
  final base = centesimos ~/ fils.length, sobra = centesimos % fils.length;
  return (gramas: [for (var i = 0; i < fils.length; i++) (base + (i < sobra ? 1 : 0)) / 100], aviso: fils.length > 1);
}

/// Confirmada errada ou descartada sem querer: volta para "a confirmar" (o que lançou no estoque sai)
/// para confirmar de novo. true = reabriu (quem chama abre a [ConfirmarTela]).
Future<bool> reabrirImpressao(BuildContext context, Json i) async {
  if (!await confirmar(context, 'Reabrir impressão?', 'O que ela lançou no estoque sai; em seguida confirme de novo.',
          sim: 'Reabrir') ||
      !context.mounted) {
    return false;
  }
  return salvar(context, 'POST', '/api/impressoes/${i['id']}/reabrir', {}, feito: 'Reaberta');
}

class _Linha {
  _Linha({this.material, this.cor, double? gramas, this.carretel}) : gramas = ctrlNumero(gramas);
  final String? material, cor;
  final TextEditingController gramas;
  String? carretel;
}

/// Confirmar impressão (do Klipper) ou lançar uma manual — tudo numa tela.
class ConfirmarTela extends StatefulWidget {
  const ConfirmarTela({super.key, this.impressao, this.impressaoId});

  /// null (com impressaoId null) = lançamento manual.
  final Json? impressao;
  final String? impressaoId;

  bool get manual => impressao == null && impressaoId == null;

  @override
  State<ConfirmarTela> createState() => _ConfirmarTelaState();
}

class _ConfirmarTelaState extends State<ConfirmarTela> {
  Json? _imp;
  bool _iniciado = false;
  bool _aviso = false;
  String? _modelo;
  String? _finalidade;
  String? _impressora;
  int _pecas = 1;

  /// Peça da receita que esta impressão fez (null = o item inteiro). Só para itens de várias peças.
  int? _parte;

  List<String> _partesDo(List modelos, String? id) => [
        for (final (i, f) in lista(mapa(modelos.where((m) => m['id'] == id).firstOrNull?['receita'])['filamentos']).indexed)
          '${f['nome'] ?? ''}'.isEmpty ? 'Peça ${i + 1}' : '${f['nome']}'
      ];

  /// Arquivo "keycap.gcode" de um modelo com a peça "Keycap": já sugere a peça.
  int? _adivinharParte(List modelos, String? id) {
    final partes = _partesDo(modelos, id);
    final arquivo = '${_imp?['arquivo'] ?? ''}'.toLowerCase();
    if (partes.length < 2 || arquivo.isEmpty) return null;
    final i = partes.indexWhere((p) => arquivo.contains(p.toLowerCase()));
    return i < 0 ? null : i;
  }
  final _linhas = <_Linha>[];
  final _perdas = <_Linha>[];
  final _horas = TextEditingController();
  final _maoObra = TextEditingController();
  bool _enviando = false;

  /// Peças que saem numa impressão do modelo (6 chaveiros na mesa = 6 peças boas de cara).
  int _porImpressao(List modelos, String? id) {
    final m = modelos.where((m) => m['id'] == id).firstOrNull;
    return m == null ? 1 : num0(mapa(m['receita'])['pecas_por_impressao'] ?? 1).clamp(1, 1000).toInt();
  }

  void _iniciar(Map cad) {
    if (_iniciado) return;
    _iniciado = true;
    _imp = widget.impressao ?? (cad['impressao'] == null ? null : mapa(cad['impressao']));
    final carreteis = lista(mapa(cad['estoque'])['carreteis']);
    _modelo = _imp?['modelo_id'] as String?;
    if (_modelo != null) _finalidade = 'venda';
    _pecas = _porImpressao(lista(cad['modelos']), _modelo);
    _parte = _adivinharParte(lista(cad['modelos']), _modelo);
    // Lançamento manual: com uma impressora só (sem seletor) ou sem escolha, usa a primeira — sem ela o custo/hora sai do padrão.
    final impressoras = lista(cad['impressoras']);
    if (impressoras.isNotEmpty) _impressora = impressoras.first['id'] as String;
    final est = mapa(_imp?['estimativa']);
    final fils = lista(est['filamentos']);
    final d = dividirEstimativa(est);
    _aviso = d.aviso;
    for (var i = 0; i < d.gramas.length; i++) {
      final f = i < fils.length ? fils[i] : <String, dynamic>{};
      final mat = f['tipo'] as String?, cor = f['cor'] as String?;
      final ordem = ordenarCarreteis(carreteis, material: mat, cor: cor);
      _linhas.add(_Linha(material: mat, cor: cor, gramas: d.gramas[i], carretel: ordem.isEmpty ? null : ordem.first['id'] as String));
    }
    if (_linhas.isEmpty) _linhas.add(_Linha());
  }

  Future<void> _confirmar() async {
    if (_finalidade == null) return avisar(context, 'Escolha para que foi a impressão');
    if (_finalidade == 'venda' && _modelo == null) return avisar(context, 'Escolha o modelo');
    List<Map>? usos(List<_Linha> l) {
      final r = <Map>[];
      for (final x in l) {
        final g = lerNumero(x.gramas.text) ?? 0;
        if (g <= 0) continue;
        if (x.carretel == null) return null;
        r.add({'carretel_id': x.carretel, 'gramas': g});
      }
      return r;
    }

    final consumos = usos(_linhas), perdas = usos(_perdas);
    if (consumos == null || perdas == null) return avisar(context, 'Escolha o carretel de cada filamento');
    final fila = context.read<FilaOffline>();
    setState(() => _enviando = true);
    try {
      var id = _imp?['id'] as String?;
      ResultadoEnvio? criada;
      if (widget.manual) {
        id = novoId();
        criada = await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/impressoes/$id', {
          'impressora_id': _impressora,
          'modelo_id': _modelo,
          'fim': DateTime.now().toUtc().toIso8601String(),
          'duracao_s': ((lerNumero(_horas.text) ?? 0) * 3600).round(),
        }));
        if (criada.recusada != null) {
          if (mounted) avisarEnvio(context, criada);
          return;
        }
      }
      final r = await fila.enviarOuGuardar(Operacao.nova('POST', '/api/impressoes/$id/confirmar', {
        'finalidade': _finalidade,
        'pecas_boas': _pecas,
        'consumos': consumos,
        'perdas': perdas,
        'modelo_id': ?_modelo,
        'parte': ?_parte,
        if (lerNumero(_maoObra.text) != null) 'mao_obra_min': lerNumero(_maoObra.text),
      }));
      if (!mounted) return;
      if (r.recusada != null) return avisarEnvio(context, r);
      avisarEnvio(context, ResultadoEnvio((criada?.guardada ?? false) || r.guardada), 'Impressão registrada');
      Navigator.maybePop(context, true);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _descartar() async {
    if (!await confirmar(context, 'Descartar impressão?', 'Ela sai das pendências e não mexe no estoque.',
        sim: 'Descartar')) {
      return;
    }
    if (!mounted) return;
    if (await salvar(context, 'POST', '/api/impressoes/${_imp!['id']}/descartar', {}, feito: 'Descartada') && mounted) {
      Navigator.maybePop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.manual ? 'Lançar impressão' : 'Confirmar impressão')),
      body: EstadoTela<Map>(
        carregar: () => buscarVarios(context, {
          'estoque': '/api/estoque',
          'modelos': '/api/modelos',
          'impressoras': '/api/impressoras',
          if (widget.impressao == null && widget.impressaoId != null) 'impressao': '/api/impressoes/${widget.impressaoId}',
        }),
        construir: (context, cad) {
          _iniciar(cad);
          return _corpo(cad);
        },
      ),
    );
  }

  Widget _corpo(Map cad) {
    final carreteis = lista(mapa(cad['estoque'])['carreteis']);
    final modelos = [for (final m in lista(cad['modelos'])) if (m['excluido'] != true) m];
    final impressoras = lista(cad['impressoras']);
    final t = Theme.of(context);
    Widget linhaUso(_Linha l, int i, {required bool perda}) => Row(children: [
          Expanded(
            child: SeletorCarretel(
              carreteis: carreteis,
              valor: l.carretel,
              filtroMaterial: l.material,
              filtroCor: l.cor,
              rotulo: perda ? 'Carretel (perda)' : [l.material, l.cor].whereType<String>().join(' ').ifEmpty('Carretel'),
              aoMudar: (v) => setState(() => l.carretel = v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 96, child: CampoNumero(l.gramas, 'Gramas', sufixo: 'g')),
          IconButton(
            tooltip: 'Tirar',
            onPressed: () => setState(() => (perda ? _perdas : _linhas).removeAt(i)),
            icon: const Icon(Icons.close),
          ),
        ]);

    return CorpoFormulario(children: [
      if (_imp != null)
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 72, height: 72, child: ImagemApi(_imp!['miniatura_url'] as String?, ajuste: BoxFit.contain)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_imp!['arquivo'] ?? 'Impressão'}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text([
                duracao(num0(_imp!['duracao_s'])),
                if (lerData(_imp!['fim']) != null) dataHora(lerData(_imp!['fim'])!),
                if (_imp!['situacao_klipper'] != null && _imp!['situacao_klipper'] != 'completed') 'parou: ${_imp!['situacao_klipper']}',
              ].join(' · '), style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular)),
            ]),
          ),
        ]),
      if (widget.manual) ...[
        if (impressoras.length > 1)
          DropdownButtonFormField<String>(
            initialValue: _impressora,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Impressora'),
            items: [for (final i in impressoras) DropdownMenuItem(value: i['id'] as String, child: Text('${i['nome']}'))],
            onChanged: (v) => setState(() => _impressora = v),
          ),
        CampoNumero(_horas, 'Tempo de impressão', sufixo: 'h'),
      ],
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: modelos.any((m) => m['id'] == _modelo) ? _modelo : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Modelo'),
        hint: const Text('Sem modelo'),
        items: [for (final m in modelos) DropdownMenuItem(value: m['id'] as String, child: Text('${m['nome']}'))],
        onChanged: (v) => setState(() {
          _modelo = v;
          if (_finalidade != 'falhou') _pecas = _porImpressao(modelos, v);
          _parte = _adivinharParte(modelos, v);
        }),
      ),
      if (_partesDo(modelos, _modelo).length > 1) ...[
        const SizedBox(height: 8),
        const Text('O que saiu nesta impressão?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
              key: const Key('parte-inteiro'),
              label: const Text('O item inteiro'),
              selected: _parte == null,
              onSelected: (_) => setState(() => _parte = null)),
          for (final (i, nome) in _partesDo(modelos, _modelo).indexed)
            ChoiceChip(
                key: Key('parte$i'), label: Text('Só $nome'), selected: _parte == i, onSelected: (_) => setState(() => _parte = i)),
        ]),
        if (_parte != null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('O item entra no estoque quando houver uma de cada peça.', style: TextStyle(fontSize: 12)),
          ),
      ],
      const SizedBox(height: 12),
      SegmentedButton<String>(
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity(vertical: 1)),
        segments: const [
          ButtonSegment(value: 'venda', label: Text('Venda')),
          ButtonSegment(value: 'pessoal', label: Text('Pessoal')),
          ButtonSegment(value: 'teste', label: Text('Teste')),
          ButtonSegment(value: 'falhou', label: Text('Falhou')),
        ],
        selected: {?_finalidade},
        onSelectionChanged: (s) => setState(() {
          if (s.isEmpty) return; // tocar de novo na escolhida não desmarca
          _finalidade = s.first;
          if (_finalidade == 'falhou') _pecas = 0;
        }),
      ),
      const SizedBox(height: 8),
      Row(children: [
        const Expanded(child: Text('Peças boas')),
        Quantidade(valor: _pecas, minimo: 0, aoMudar: (v) => setState(() => _pecas = v)),
      ]),
      const Secao('Filamento usado'),
      if (_aviso)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('O fatiador só informou o total; dividimos entre as cores — confira os gramas.',
              style: TextStyle(color: amarelo.withValues(alpha: 1), fontSize: 13)),
        ),
      for (var i = 0; i < _linhas.length; i++) linhaUso(_linhas[i], i, perda: false),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
            onPressed: () => setState(() => _linhas.add(_Linha())), icon: const Icon(Icons.add), label: const Text('Outro filamento')),
      ),
      MaisDetalhes(titulo: 'Perdi material / mais detalhes', children: [
        for (var i = 0; i < _perdas.length; i++) linhaUso(_perdas[i], i, perda: true),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: () => setState(() => _perdas.add(_Linha())),
              icon: const Icon(Icons.add),
              label: const Text('Perdi material')),
        ),
        CampoNumero(_maoObra, 'Mão de obra (se diferente do modelo)', sufixo: 'min'),
      ]),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _enviando ? null : _confirmar,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Confirmar'),
      ),
      if (!widget.manual) TextButton(onPressed: _descartar, child: const Text('Não era para registrar')),
    ]);
  }
}

extension on String {
  String ifEmpty(String outro) => isEmpty ? outro : this;
}

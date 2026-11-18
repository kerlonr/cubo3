import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/fila.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import '../casca.dart';
import '../inicio/inicio_aba.dart' show GraficoMeses;
import '../estoque/carretel_form.dart';
import '../vendas/pedido_tela.dart';

/// Gastos lançados à mão. Filamento e desperdício ficam no fim: carretel cadastrado no Estoque
/// e falha de impressão já entram sozinhos, e lançar de novo contaria em dobro.
const categoriasDespesa = {
  'insumo': 'Insumo',
  'embalagem': 'Embalagem',
  'equipamento': 'Equipamento',
  'manutencao': 'Manutenção',
  'energia': 'Energia',
  'ferramenta': 'Ferramenta',
  'filamento': 'Filamento',
  'desperdicio': 'Desperdício',
  'outros': 'Outros',
};

const _icones = {
  'venda': Icons.sell_outlined,
  'filamento': Icons.album_outlined,
  'insumo': Icons.inventory_2_outlined,
  'desperdicio': Icons.delete_sweep_outlined,
  'embalagem': Icons.redeem_outlined,
  'equipamento': Icons.precision_manufacturing_outlined,
  'manutencao': Icons.build_outlined,
  'energia': Icons.bolt_outlined,
  'ferramenta': Icons.handyman_outlined,
};

/// null = tudo; true = só entradas (vendas); false = só saídas.
const _filtros = {'Tudo': null, 'Entradas': true, 'Saídas': false};

/// Período em análise. "Geral" é o padrão: sem início nem fim o servidor soma desde sempre.
enum Escopo { geral, mes, ano }

/// Extrato: o que entrou (vendas entregues) e o que saiu (compras do Estoque e gastos lançados),
/// com resumo por mês e por categoria. Tocar numa linha abre onde ela se corrige.
class FinanceiroTela extends StatefulWidget {
  const FinanceiroTela({super.key});

  @override
  State<FinanceiroTela> createState() => _FinanceiroTelaState();
}

class _FinanceiroTelaState extends State<FinanceiroTela> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  Escopo _escopo = Escopo.geral;
  String _filtro = 'Tudo';

  /// Geral: sem datas (o servidor soma desde sempre). Mês e ano mandam o intervalo.
  Map<String, String> get _periodo => switch (_escopo) {
        Escopo.geral => const {},
        Escopo.mes => {'inicio': diaIso(_mes), 'fim': diaIso(DateTime(_mes.year, _mes.month + 1, 0))},
        Escopo.ano => {'inicio': diaIso(DateTime(_mes.year)), 'fim': diaIso(DateTime(_mes.year, 12, 31))},
      };

  String get _titulo => switch (_escopo) {
        Escopo.geral => 'Desde o começo',
        Escopo.mes => capitalizar(DateFormat('MMMM yyyy', 'pt_BR').format(_mes)),
        Escopo.ano => '${_mes.year}',
      };

  void _andar(int passo) => setState(() => _mes = _escopo == Escopo.ano
      ? DateTime(_mes.year + passo, _mes.month)
      : DateTime(_mes.year, _mes.month + passo));

  void _verMes(String mes) => setState(() {
        final partes = mes.split('-');
        _mes = DateTime(int.parse(partes.first), int.parse(partes.last));
        _escopo = Escopo.mes;
      });

  /// Compra de insumo: lançamentos de estoque não se editam (são a soma do saldo), então corrigir =
  /// excluir o errado e lançar o certo, na mesma data, pela fila (em ordem, funciona sem internet).
  Future<void> _corrigirCompra(Map l) async {
    final qtd = ctrlNumero(numOu(l['quantidade']));
    final valor = ctrlDinheiro(num0(l['valor']));
    final acao = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Corrigir compra'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${l['descricao']}'),
          CampoNumero(qtd, 'Quantidade', key: const Key('compra_qtd')),
          CampoDinheiro(valor, 'Valor pago (total)', key: const Key('compra_valor')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, 'excluir'),
              style: TextButton.styleFrom(foregroundColor: vermelho),
              child: const Text('Excluir')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, 'salvar'), child: const Text('Salvar')),
        ],
      ),
    );
    if (acao == null || !mounted) return;
    final q = lerNumero(qtd.text) ?? 0, v = lerNumero(valor.text) ?? 0;
    if (acao == 'salvar' && (q <= 0 || v <= 0)) return avisar(context, 'Quantidade e valor precisam ser maiores que zero', erro: true);
    if (acao == 'excluir' &&
        (!await confirmar(context, 'Excluir este lançamento?',
                'O gasto sai do financeiro e a quantidade sai do estoque.', sim: 'Excluir', cor: vermelho) ||
            !mounted)) {
      return;
    }
    if (!await salvar(context, 'DELETE', '/api/movimentos/${l['id']}', {},
            feito: acao == 'excluir' ? 'Lançamento excluído' : 'Compra corrigida') ||
        !mounted) {
      return;
    }
    if (acao == 'salvar') {
      final d = DateTime.parse('${l['data']}');
      await salvar(context, 'PUT', '/api/movimentos/${novoId()}', {
        'item_tipo': l['item_tipo'],
        'item_id': l['item_id'],
        'tipo': 'compra',
        'quantidade': q,
        'valor': v,
        'data': DateTime(d.year, d.month, d.day, 12).toUtc().toIso8601String(),
      }, feito: 'Compra corrigida');
    }
    dadosMudaram.value++;
  }

  Future<void> _tocar(Map l) async {
    try {
      switch (l['tipo']) {
        case 'venda':
          await abrirTela(context, PedidoTela(id: '${l['id']}'));
        case 'despesa':
          final d = mapa((await buscar(context, '/api/despesas/${l['id']}')).dados);
          if (mounted) await abrirTela(context, DespesaForm(dados: d));
        case 'compra' when l['item_tipo'] == 'carretel':
          final c = mapa((await buscar(context, '/api/carreteis/${l['item_id']}')).dados);
          if (mounted) await abrirTela(context, CarretelForm(dados: c));
        default: // compra de insumo lançada no Estoque: corrige (troca o lançamento) ou exclui
          await _corrigirCompra(l);
      }
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Financeiro'), actions: [
        const BotaoOlho(),
        IconButton(
            tooltip: 'Lançar gasto', icon: const Icon(Icons.add), onPressed: () => abrirTela(context, const DespesaForm())),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            for (final (e, rotulo) in const [(Escopo.geral, 'Geral'), (Escopo.mes, 'Mês'), (Escopo.ano, 'Ano')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                    label: Text(rotulo), selected: _escopo == e, onSelected: (_) => setState(() => _escopo = e)),
              ),
          ]),
        ),
        if (_escopo != Escopo.geral)
          Row(children: [
            IconButton(tooltip: 'Anterior', onPressed: () => _andar(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(_titulo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(tooltip: 'Próximo', onPressed: () => _andar(1), icon: const Icon(Icons.chevron_right)),
          ]),
        Expanded(
          child: EstadoTela<Map>(
            key: ValueKey('$_escopo|$_mes'),
            carregar: () => buscar(context, '/api/extrato', query: _periodo),
            construir: (context, e) => ValueListenableBuilder<bool>(
              valueListenable: valoresOcultos,
              builder: (_, oculto, _) => _corpo(e, oculto),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _corpo(Map e, bool oculto) {
    final t = Theme.of(context);
    final fraco = TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant);
    String m(num v) => oculto ? mascaraValor : moeda(v);
    final entradas = _filtros[_filtro];
    final linhas = [for (final l in lista(e['linhas'])) if (entradas == null || (l['tipo'] == 'venda') == entradas) l];
    final resultado = num0(e['resultado']);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
          Row(children: [
            // Tocar no cartão filtra a lista; tocar de novo volta para Tudo.
            Expanded(
                child: CartaoValor('Entrou', m(num0(e['entrou'])),
                    icone: Icons.south_west, aoTocar: () => setState(() => _filtro = _filtro == 'Entradas' ? 'Tudo' : 'Entradas'))),
            const SizedBox(width: 8),
            Expanded(
                child: CartaoValor('Saiu', m(num0(e['saiu'])),
                    icone: Icons.north_east, aoTocar: () => setState(() => _filtro = _filtro == 'Saídas' ? 'Tudo' : 'Saídas'))),
          ]),
          const SizedBox(height: 8),
          CartaoValor(_escopo == Escopo.geral ? 'Resultado geral' : 'Resultado · $_titulo', m(resultado),
              cor: oculto ? null : corResultado(resultado)),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text('Lucro das vendas ${m(num0(e['lucro_vendas']))}', style: fraco),
          ),
          if (e['recebido_parcelas'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
              child: Text('Recebido (parcelas) ${m(num0(e['recebido_parcelas']))}', style: fraco),
            ),
          if (num0(e['perdas_g']) > 0)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('Perdas: ${gramas(num0(e['perdas_g']))} · ${m(num0(e['perdas_valor']))}'),
                subtitle: const Text('Já no custo do carretel: não soma no "Saiu"'),
              ),
            ),
          ..._porMes(lista(e['por_mes']), oculto, fraco),
          ..._porCategoria(lista(e['por_categoria']), num0(e['saiu']), m, fraco),
          const Secao('Lançamentos'),
          Wrap(spacing: 8, children: [
            for (final f in _filtros.keys)
              ChoiceChip(label: Text(f), selected: _filtro == f, onSelected: (_) => setState(() => _filtro = f)),
          ]),
          const SizedBox(height: 8),
          if (num0(e['total_linhas']) > lista(e['linhas']).length)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  'Mostrando os ${lista(e['linhas']).length} mais recentes de ${numero(num0(e['total_linhas']))}. '
                  'Os totais acima contam tudo.',
                  style: fraco),
            ),
          if (linhas.isEmpty)
            EstadoVazio(
              icone: Icons.receipt_outlined,
              titulo: _escopo == Escopo.geral ? 'Nada lançado ainda' : 'Nada em $_titulo',
              explicacao: 'Vendas entregues, compras do Estoque e gastos.',
              acao: 'Lançar gasto',
              aoTocar: () => abrirTela(context, const DespesaForm()),
            ),
          for (final l in linhas) _linha(l, m, oculto, fraco),
        ]),
      ),
    );
  }

  /// Gráfico dos últimos 12 meses do período e a média mensal; tocar numa barra abre aquele mês.
  List<Widget> _porMes(List meses, bool oculto, TextStyle fraco) {
    if (meses.length < 2) return const [];
    final ultimos = meses.length > 12 ? meses.sublist(meses.length - 12) : meses;
    final receita = meses.fold(0.0, (t, x) => t + num0(x['receita'])) / meses.length;
    final gastos = meses.fold(0.0, (t, x) => t + num0(x['gastos'])) / meses.length;
    return [
      Secao(ultimos.length < meses.length ? 'Por mês (últimos 12)' : 'Por mês'),
      SizedBox(
        height: 180,
        child: GraficoMeses(
          [for (final x in ultimos) mapa(x)],
          oculto: oculto,
          aoTocar: (i) => _verMes('${ultimos[i]['mes']}'),
        ),
      ),
      const SizedBox(height: 4),
      Text(
          oculto
              ? 'Média por mês: $mascaraValor'
              : 'Média por mês: entrou ${moeda(receita)} · saiu ${moeda(gastos)} · sobra ${moeda(receita - gastos)}',
          key: const Key('media_mes'),
          style: fraco),
    ];
  }

  /// Para onde o dinheiro foi: cada categoria com a fatia que ocupa do que saiu.
  List<Widget> _porCategoria(List categorias, double saiu, String Function(num) m, TextStyle fraco) {
    if (categorias.isEmpty) return const [];
    final t = Theme.of(context);
    return [
      const Secao('Para onde foi o dinheiro'),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(children: [
            for (final c in categorias)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(_icones['${c['categoria']}'] ?? Icons.receipt_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(categoriasDespesa['${c['categoria']}'] ?? '${c['categoria']}')),
                    Text(
                        saiu > 0
                            ? '${m(num0(c['valor']))} · ${numero(num0(c['valor']) / saiu * 100)}%'
                            : m(num0(c['valor'])),
                        style: const TextStyle(fontFeatures: tabular)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: saiu > 0 ? (num0(c['valor']) / saiu).clamp(0, 1) : 0,
                      minHeight: 6,
                      backgroundColor: t.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    ];
  }

  Widget _linha(Map l, String Function(num) m, bool oculto, TextStyle fraco) {
    final t = Theme.of(context);
    final venda = l['tipo'] == 'venda';
    final categoria = venda ? 'venda' : '${l['categoria']}';
    final nomeCategoria = categoriasDespesa[categoria] ?? categoria;
    final lucro = numOu(l['lucro']);
    final data = lerData(l['data']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _tocar(l),
        leading: CircleAvatar(
          backgroundColor: t.colorScheme.surfaceContainerHighest,
          foregroundColor: venda ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
          child: Icon(_icones[categoria] ?? Icons.receipt_outlined, size: 20),
        ),
        title: Text('${l['descricao'] ?? nomeCategoria}', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          if (data != null) dataCurta(data),
          switch (l['tipo']) {
            'venda' => l['pago'] == true ? 'Venda' : 'Venda · a receber',
            'compra' => 'Compra no Estoque',
            _ => nomeCategoria,
          },
        ].join(' · ')),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${venda ? '+' : '−'} ${m(num0(l['valor']))}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
          if (venda && lucro != null)
            Text('lucro ${m(lucro)}',
                style: fraco.copyWith(color: oculto ? null : corResultado(lucro), fontFeatures: tabular)),
        ]),
      ),
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
    final ok = await salvar(context, 'PUT', '/api/despesas/${d['id'] ?? novoId()}', versaoBase: d['atualizado_em'] as String?, {
      'data': diaIso(_data),
      'categoria': _categoria,
      'valor': lerNumero(_valor.text),
      'descricao': _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _excluir() async {
    if (!await confirmar(context, 'Excluir gasto?', moeda(num0(d['valor'])), sim: 'Excluir') || !mounted) return;
    if (await salvar(context, 'DELETE', '/api/despesas/${d['id']}', {}, feito: 'Gasto excluído') && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.dados == null ? 'Lançar gasto' : 'Editar gasto'), actions: [
          if (widget.dados != null)
            IconButton(tooltip: 'Excluir', onPressed: _excluir, icon: const Icon(Icons.delete_outline, color: vermelho)),
        ]),
        bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
        body: CorpoFormulario(chave: _form, children: [
          CampoDinheiro(_valor, 'Valor', obrigatorio: true),
          CampoComAjuda(
            rotulo: 'Categoria',
            ajuda: _categoria == 'desperdicio'
                ? 'Falha com carretel do Estoque já está no custo: não lance.'
                : 'Carretel e insumo do Estoque já entram sozinhos: não lance.',
            child: SeletorChips<String>(
                opcoes: categoriasDespesa, valor: _categoria, aoMudar: (v) => setState(() => _categoria = v)),
          ),
          CampoTexto(_descricao, 'Descrição', dica: 'Peça que quebrou, cola, conta de luz...'),
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
        ]),
      );
}

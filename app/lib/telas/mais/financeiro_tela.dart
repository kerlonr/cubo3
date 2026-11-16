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

/// Extrato do mês: o que entrou (vendas entregues) e o que saiu (compras do Estoque e gastos lançados).
/// Tocar numa linha abre onde ela se corrige.
class FinanceiroTela extends StatefulWidget {
  const FinanceiroTela({super.key});

  @override
  State<FinanceiroTela> createState() => _FinanceiroTelaState();
}

class _FinanceiroTelaState extends State<FinanceiroTela> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  String _filtro = 'Tudo';

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
    final nome = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    return Scaffold(
      appBar: AppBar(title: const Text('Financeiro'), actions: [
        const BotaoOlho(),
        IconButton(
            tooltip: 'Lançar gasto', icon: const Icon(Icons.add), onPressed: () => abrirTela(context, const DespesaForm())),
      ]),
      body: Column(children: [
        Row(children: [
          IconButton(
              tooltip: 'Mês anterior',
              onPressed: () => setState(() => _mes = DateTime(_mes.year, _mes.month - 1)),
              icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(nome[0].toUpperCase() + nome.substring(1),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
              tooltip: 'Próximo mês',
              onPressed: () => setState(() => _mes = DateTime(_mes.year, _mes.month + 1)),
              icon: const Icon(Icons.chevron_right)),
        ]),
        Expanded(
          child: EstadoTela<Map>(
            key: ValueKey(_mes),
            carregar: () => buscar(context, '/api/extrato',
                query: {'inicio': diaIso(_mes), 'fim': diaIso(DateTime(_mes.year, _mes.month + 1, 0))}),
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
          CartaoValor('Resultado do mês', m(resultado), cor: oculto ? null : corResultado(resultado)),
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
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final f in _filtros.keys)
              ChoiceChip(label: Text(f), selected: _filtro == f, onSelected: (_) => setState(() => _filtro = f)),
          ]),
          const SizedBox(height: 8),
          if (linhas.isEmpty)
            EstadoVazio(
              icone: Icons.receipt_outlined,
              titulo: 'Nada neste mês',
              explicacao: 'Vendas entregues, compras do Estoque e gastos.',
              acao: 'Lançar gasto',
              aoTocar: () => abrirTela(context, const DespesaForm()),
            ),
          for (final l in linhas) _linha(l, m, oculto, fraco),
        ]),
      ),
    );
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

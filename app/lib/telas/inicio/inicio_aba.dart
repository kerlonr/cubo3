import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/cache.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/animacoes.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/logo.dart';
import '../casca.dart';
import '../estoque/estoque_aba.dart';
import '../impressoes/cartao_ao_vivo.dart';

/// Início: impressão em andamento, o que pede atenção (a confirmar, pedidos, filamento acabando), lucro do mês,
/// investimento e gráfico. Orçar fica no "+".
class InicioAba extends StatefulWidget {
  const InicioAba({super.key});

  @override
  State<InicioAba> createState() => _InicioAbaState();
}

class _InicioAbaState extends State<InicioAba> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);

  void _mudarMes(int delta) => setState(() => _mes = DateTime(_mes.year, _mes.month + delta));

  @override
  Widget build(BuildContext context) {
    final fim = DateTime(_mes.year, _mes.month + 1, 0);
    final nomeMes = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    return Scaffold(
      appBar: AppBar(
        title: const LogoCubo3(tamanho: 26, comNome: true),
        actions: [IconButton(tooltip: 'Mais', icon: const Icon(Icons.menu), onPressed: () => abrirMais(context))],
      ),
      body: EstadoTela<Map>(
        key: ValueKey(_mes),
        carregar: () async {
          final painel = await buscar(context, '/api/painel', query: {'inicio': diaIso(_mes), 'fim': diaIso(fim)});
          // Impressoras e pedidos são extra: sem eles o Início ainda abre.
          List impressoras = const [], pedidos = const [];
          try {
            if (context.mounted) impressoras = lista((await buscar(context, '/api/impressoras')).dados);
            if (context.mounted) pedidos = lista((await buscar(context, '/api/pedidos')).dados);
          } catch (_) {}
          return RespostaCache({...mapa(painel.dados), 'impressoras': impressoras, 'pedidos': pedidos}, painel.deCache,
              painel.quando);
        },
        construir: (context, p) => _corpo(p, nomeMes[0].toUpperCase() + nomeMes.substring(1)),
      ),
    );
  }

  Widget? _pedidosAbertos(List pedidos) => _pedidosAbertosDe(context, pedidos);

  /// Filamentos abaixo do mínimo (insumos ficam de fora: não são usados).
  List<Widget> _filamentoAcabando(List baixo) {
    final fil = [for (final e in baixo) if (e['tipo'] == 'filamento') e];
    if (fil.isEmpty) return const [];
    return [
      const Secao('Filamento acabando'),
      Card(
        child: Column(children: [
          for (final e in fil)
            ListTile(
              dense: true,
              title: Text('${e['nome']}'),
              trailing: Text(gramas(num0(e['saldo'])), style: const TextStyle(fontFeatures: tabular)),
              onTap: () => abrirTela(context, const EstoqueAba()),
            ),
        ]),
      ),
    ];
  }

  Widget _corpo(Map p, String nomeMes) {
    final t = Theme.of(context);
    final semMovimento = lista(p['por_mes']).every((m) => num0(m['receita']) == 0 && num0(m['gastos']) == 0);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          for (final i in lista(p['impressoras']))
            if ('${i['moonraker_url'] ?? ''}'.isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.findAncestorStateOfType<CascaState>()?.irPara(1),
                child: Padding(padding: const EdgeInsets.only(bottom: 8), child: CartaoAoVivo(impressora: i, soAtiva: true)),
              ),
          if (num0(p['a_confirmar']) > 0)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.pending_actions, color: amarelo),
                title: Text('A confirmar (${num0(p['a_confirmar']).toInt()})'),
                subtitle: const Text('Impressões que terminaram e esperam os gramas reais'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.findAncestorStateOfType<CascaState>()?.irPara(1),
              ),
            ),
          ?_pedidosAbertos(lista(p['pedidos'])),
          Row(children: [
            IconButton(tooltip: 'Mês anterior', onPressed: () => _mudarMes(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(nomeMes, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(tooltip: 'Próximo mês', onPressed: () => _mudarMes(1), icon: const Icon(Icons.chevron_right)),
          ]),
          Entrada(ordem: 1, child: CartaoLucro(entrou: num0(p['receita']), saiu: num0(p['gastos']))),
          const SizedBox(height: 8),
          Entrada(ordem: 2, child: CartaoInvestimento(investido: num0(p['investido']), recebido: num0(p['recebido']))),
          ..._filamentoAcabando(lista(p['estoque_baixo'])),
          const Secao('Receita × gastos (12 meses)'),
          if (semMovimento)
            Text('Sem vendas nem gastos ainda', style: TextStyle(color: t.colorScheme.onSurfaceVariant))
          else ...[
            Entrada(ordem: 4, child: SizedBox(height: 200, child: GraficoMeses(lista(p['por_mes'])))),
            const SizedBox(height: 8),
            Text('Toque e segure um mês no gráfico para ver os valores.',
                style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }
}

/// "2 produzindo · 1 orçamento", só quando há pedido em aberto; tocar leva para Vendas.
Widget? _pedidosAbertosDe(BuildContext context, List pedidos) {
  int conta(Set<String> s) => pedidos.where((p) => s.contains(p['status'])).length;
  final produzindo = conta({'aprovado', 'produzindo', 'pronto'}), orcamentos = conta({'orcamento'});
  if (produzindo + orcamentos == 0) return null;
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: const Text('Pedidos em aberto'),
      subtitle: Text([
        if (produzindo > 0) '$produzindo produzindo',
        if (orcamentos > 0) '$orcamentos ${orcamentos == 1 ? 'orçamento' : 'orçamentos'}',
      ].join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.findAncestorStateOfType<CascaState>()?.irPara(3),
    ),
  );
}

/// Lucro do mês = o que entrou − o que saiu, com os dois valores embaixo.
class CartaoLucro extends StatelessWidget {
  const CartaoLucro({super.key, required this.entrou, required this.saiu});
  final double entrou, saiu;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lucro = arred2(entrou - saiu);
    final fraco = TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Lucro do mês', style: fraco),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ValorAnimado(lucro,
                chaveTexto: const Key('lucro_mes'),
                estilo: TextStyle(
                    fontSize: 34, fontWeight: FontWeight.w700, color: corResultado(lucro), fontFeatures: tabular, letterSpacing: -1)),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 4, children: [
            Text('Entrou ${moeda(entrou)}', style: fraco),
            Text('Saiu ${moeda(saiu)}', style: fraco),
          ]),
        ]),
      ),
    );
  }
}

/// Tudo que já saiu (filamento, equipamento, despesas) contra tudo que já entrou com vendas.
class CartaoInvestimento extends StatelessWidget {
  const CartaoInvestimento({super.key, required this.investido, required this.recebido});
  final double investido, recebido;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final falta = arred2(investido - recebido);
    final fraco = TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Investimento', style: fraco),
          const SizedBox(height: 4),
          Text(
            investido == 0
                ? 'Nada investido ainda'
                : falta > 0
                    ? 'Faltam ${moeda(falta)} para se pagar'
                    : 'Já se pagou e sobrou ${moeda(-falta)}',
            key: const Key('investimento'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: falta > 0 || investido == 0 ? null : verde),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: investido == 0 ? 0 : (recebido / investido).clamp(0, 1).toDouble()),
              duration: duracaoAnimacao(context, 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) =>
                  LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: t.colorScheme.surfaceContainerHighest),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 4, children: [
            Text('Investido ${moeda(investido)}', style: fraco),
            Text('Voltou ${moeda(recebido)}', style: fraco),
          ]),
        ]),
      ),
    );
  }
}

class GraficoMeses extends StatelessWidget {
  const GraficoMeses(this.meses, {super.key});
  final List<Json> meses;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cinza = t.colorScheme.outline;
    return BarChart(BarChartData(
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        topTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= meses.length) return const SizedBox();
              final mes = int.tryParse('${meses[i]['mes']}'.split('-').last) ?? 1;
              return Text(DateFormat('MMM', 'pt_BR').format(DateTime(2000, mes)).substring(0, 3),
                  style: TextStyle(fontSize: 10, color: t.colorScheme.onSurfaceVariant));
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (g, _, rod, i) =>
              BarTooltipItem('${i == 0 ? 'Receita' : 'Gastos'}\n${moeda(rod.toY)}', const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ),
      barGroups: [
        for (var i = 0; i < meses.length; i++)
          BarChartGroupData(x: i, barsSpace: 2, barRods: [
            BarChartRodData(toY: num0(meses[i]['receita']), color: t.colorScheme.primary, width: 6),
            BarChartRodData(toY: num0(meses[i]['gastos']), color: cinza, width: 6),
          ]),
      ],
    ));
  }
}

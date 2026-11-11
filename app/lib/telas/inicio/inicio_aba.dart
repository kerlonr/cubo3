import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/logo.dart';
import '../casca.dart';
import '../orcar/orcar_tela.dart';

/// Início: lucro do mês, quanto já foi investido e quanto voltou, atalho para orçar e o gráfico.
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
        carregar: () => buscar(context, '/api/painel', query: {'inicio': diaIso(_mes), 'fim': diaIso(fim)}),
        construir: (context, p) => _corpo(p, nomeMes[0].toUpperCase() + nomeMes.substring(1)),
      ),
    );
  }

  Widget _corpo(Map p, String nomeMes) {
    final t = Theme.of(context);
    final semMovimento = lista(p['por_mes']).every((m) => num0(m['receita']) == 0 && num0(m['gastos']) == 0);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          FilledButton.icon(
            onPressed: () => abrirTela(context, const OrcarTela()),
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Orçar peça'),
          ),
          if (num0(p['a_confirmar']) > 0) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.pending_actions, color: amarelo),
                title: Text('A confirmar (${num0(p['a_confirmar']).toInt()})'),
                subtitle: const Text('Impressões que terminaram e esperam os gramas reais'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.findAncestorStateOfType<CascaState>()?.irPara(1),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            IconButton(tooltip: 'Mês anterior', onPressed: () => _mudarMes(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(nomeMes, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(tooltip: 'Próximo mês', onPressed: () => _mudarMes(1), icon: const Icon(Icons.chevron_right)),
          ]),
          CartaoLucro(entrou: num0(p['receita']), saiu: num0(p['gastos'])),
          const SizedBox(height: 8),
          CartaoInvestimento(investido: num0(p['investido']), recebido: num0(p['recebido'])),
          const Secao('Receita × gastos (12 meses)'),
          if (semMovimento)
            Text('Sem vendas nem gastos ainda', style: TextStyle(color: t.colorScheme.onSurfaceVariant))
          else ...[
            SizedBox(height: 200, child: GraficoMeses(lista(p['por_mes']))),
            const SizedBox(height: 8),
            Text('Toque e segure um mês no gráfico para ver os valores.',
                style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }
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
            child: Text(moeda(lucro),
                key: const Key('lucro_mes'),
                softWrap: false,
                style: TextStyle(
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
            child: LinearProgressIndicator(
              value: investido == 0 ? 0 : (recebido / investido).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: t.colorScheme.surfaceContainerHighest,
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

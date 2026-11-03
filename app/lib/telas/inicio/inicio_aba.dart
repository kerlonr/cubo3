import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/cache.dart';
import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/logo.dart';
import '../casca.dart';
import '../impressoes/cartao_ao_vivo.dart';

/// Painel: o que gastamos, vendemos, lucramos e o que falta no estoque.
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
          if (!context.mounted) return painel;
          // Impressoras são extra: sem elas o painel ainda abre.
          List impressoras = const [];
          try {
            impressoras = (await buscar(context, '/api/impressoras')).dados as List;
          } catch (_) {}
          return RespostaCache({...painel.dados as Map, 'impressoras': impressoras}, painel.deCache, painel.quando);
        },
        construir: (context, p) => _corpo(p, nomeMes[0].toUpperCase() + nomeMes.substring(1)),
      ),
    );
  }

  Widget _corpo(Map p, String nomeMes) {
    final t = Theme.of(context);
    final largo = MediaQuery.sizeOf(context).width >= 840;
    final impressoras = [for (final i in lista(p['impressoras'])) if ((i['moonraker_url'] ?? '') != '') i];
    final resultado = num0(p['resultado']), lucro = num0(p['lucro_vendas']);
    final cartoes = [
      CartaoValor('Receita', moeda(num0(p['receita'])), icone: Icons.trending_up),
      CartaoValor('Gastos', moeda(num0(p['gastos'])), icone: Icons.trending_down),
      CartaoValor('Resultado', moeda(resultado), cor: corResultado(resultado), icone: Icons.account_balance_wallet_outlined),
      CartaoValor('Lucro das vendas', moeda(lucro), cor: corResultado(lucro), icone: Icons.sell_outlined),
    ];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
          Row(children: [
            IconButton(onPressed: () => _mudarMes(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(nomeMes, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(onPressed: () => _mudarMes(1), icon: const Icon(Icons.chevron_right)),
          ]),
          GridView.count(
            crossAxisCount: largo ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: largo ? 2 : 1.45,
            children: cartoes,
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
          for (final i in impressoras) Padding(padding: const EdgeInsets.only(top: 8), child: CartaoAoVivo(impressora: i)),
          const Secao('Receita × gastos (12 meses)'),
          SizedBox(height: 200, child: GraficoMeses(lista(p['por_mes']))),
          if (lista(p['estoque_baixo']).isNotEmpty) ...[
            const Secao('Estoque baixo'),
            for (final e in lista(p['estoque_baixo']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${e['nome']}'),
                subtitle: Text(e['tipo'] == 'filamento' ? gramas(num0(e['saldo'])) : numero(num0(e['saldo']))),
                trailing: const ChipRepor(),
                onTap: () => context.findAncestorStateOfType<CascaState>()?.irPara(3),
              ),
          ],
          if (lista(p['mais_vendidos']).isNotEmpty) ...[
            const Secao('Mais vendidos'),
            for (final m in lista(p['mais_vendidos']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m['nome']}'),
                trailing: Text(numero(num0(m['qtd'])), style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600)),
              ),
          ],
          const Secao('Produção no mês'),
          Row(children: [
            Expanded(child: CartaoValor('Horas de impressão', '${numero(num0(p['horas_impressao']))} h')),
            const SizedBox(width: 8),
            Expanded(child: CartaoValor('Filamento', '${numero(num0(p['kg_filamento']))} kg')),
          ]),
          const SizedBox(height: 8),
          Text('Toque e segure um mês no gráfico para ver os valores.',
              style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
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

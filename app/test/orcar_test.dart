import 'package:cubo3/telas/orcar/historico.dart';
import 'package:cubo3/telas/orcar/orcar_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

Ambiente _amb() => Ambiente({
      'GET /api/filamentos': (_) => [
            {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Branco', 'cor_hex': '#FFFFFF', 'preco_kg': 100}
          ],
      'GET /api/empresa/config': (_) =>
          {'eficiencia': 1.1, 'mao_obra_hora': 10, 'kwh': 0.656, 'reserva': 1.3, 'margens': [20, 30, 50]},
    });

String _texto(WidgetTester tester, String chave) => tester.widget<Text>(find.byKey(Key(chave))).data!;

void main() {
  testWidgets('caso da planilha sem rede: só gramas e tempo dão custo 6,32 e preço de R\$ 15 (50% para cima)', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const OrcarTela()));
    await tester.pumpAndSettle();

    amb.online = false;
    await tester.pumpWidget(amb.tela(const SizedBox()));
    await tester.pumpWidget(amb.tela(const OrcarTela()));
    await tester.pumpAndSettle();
    expect(find.text('Digite os gramas e o tempo para ver o preço'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('gramas0')), '33');
    await tester.enterText(find.byKey(const Key('tempo0')), '3h');
    await tester.pumpAndSettle();
    expect(_texto(tester, 'preco'), 'R\$ 15,00');
    expect(_texto(tester, 'lucro'), 'lucro R\$ 8,68 · custo R\$ 6,32');
    for (final p in ['R\$ 10,00', 'exato R\$ 7,90', 'exato R\$ 9,03', 'exato R\$ 12,64']) {
      expect(find.text(p), findsWidgets, reason: p);
    }
  });

  testWidgets('recomenda 50%, deixa tocar em 30% e o histórico guarda a margem escolhida', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const OrcarTela()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gramas0')), '33');
    await tester.enterText(find.byKey(const Key('tempo0')), '3');
    await tester.pumpAndSettle();
    expect(find.text('Preço com 50% de lucro (recomendado)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('margem30')));
    await tester.tap(find.byKey(const Key('margem30')));
    await tester.pumpAndSettle();
    expect(find.text('Preço com 30% de lucro'), findsOneWidget);
    expect(_texto(tester, 'preco'), 'R\$ 10,00');

    await tester.pumpWidget(amb.tela(const OrcarTela(inicial: {
      'itens': [
        {'gramas': '33', 'tempo': '3', 'qtd': 1}
      ],
      'margem': 30,
    })));
    await tester.pumpAndSettle();
    expect(find.text('Preço com 30% de lucro'), findsOneWidget, reason: 'reabre com a margem salva');
  });

  testWidgets('kit: duas unidades dobram o custo; tempo inválido avisa', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const OrcarTela()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gramas0')), '33');
    await tester.enterText(find.byKey(const Key('tempo0')), '3');
    await tester.tap(find.byTooltip('Mais uma'));
    await tester.pumpAndSettle();
    expect(_texto(tester, 'lucro'), endsWith('custo R\$ 12,64'));
    await tester.enterText(find.byKey(const Key('tempo0')), 'três');
    await tester.pumpAndSettle();
    expect(find.text('Use 2h30 ou 2,5'), findsOneWidget);
  });

  testWidgets('reabre um orçamento do histórico com as peças e o preço', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const OrcarTela(inicial: {
      'id': 'o1',
      'itens': [
        {'nome': 'Vaso', 'gramas': '33', 'tempo': '3h', 'qtd': 1}
      ],
      'filamento_id': 'f1',
      'mao_obra': '10',
    })));
    await tester.pumpAndSettle();
    expect(find.text('Vaso'), findsOneWidget);
    expect(_texto(tester, 'preco'), 'R\$ 15,00');
  });

  test('histórico guarda no topo, atualiza pelo id e apaga', () async {
    await _amb().preparar();
    await salvarOrcamento({'id': 'a', 'preco': 10, 'itens': []});
    await salvarOrcamento({'id': 'b', 'preco': 20, 'itens': []});
    await salvarOrcamento({'id': 'a', 'preco': 15, 'itens': []});
    expect([for (final o in await lerHistorico()) (o['id'], o['preco'])], [('a', 15), ('b', 20)]);
    await apagarOrcamento('a');
    expect((await lerHistorico()).map((o) => o['id']), ['b']);
  });

  test('linhas dos itens: sem nome vira "Peça N" e quantidade aparece', () {
    expect(linhasItens([
      {'nome': '', 'qtd': 1},
      {'nome': 'Suporte', 'qtd': 2}
    ]), ['Peça 1', 'Suporte (2 un.)']);
    expect(itemDeArquivo('vaso.gcode.3mf', 23.5, 4230), {'nome': 'vaso', 'gramas': '23,5', 'tempo': '1h11', 'qtd': 1});
  });
}

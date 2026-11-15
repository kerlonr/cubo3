import 'dart:convert';

import 'package:cubo3/dominio/custos.dart';
import 'package:cubo3/telas/catalogo/modelo_form.dart';
import 'package:cubo3/telas/orcar/orcar_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

const _config = {'eficiencia': 1.1, 'mao_obra_hora': 10, 'kwh': 0.656, 'reserva': 1.3, 'margens': [20, 30, 50]};

Ambiente _amb() => Ambiente({
      'GET /api/filamentos': (_) => [
            {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Preto', 'cor_hex': '#000000', 'preco_kg': 100},
            {'id': 'f2', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Vermelho', 'cor_hex': '#E53935', 'preco_kg': 100},
          ],
      'GET /api/empresa/config': (_) => _config,
    })
      ..rotasPrefixo['PUT /api/modelos/'] = (r) => {'id': 'm1'};

Map _corpoPut(Ambiente amb) => jsonDecode(amb.recebidos.lastWhere((r) => r.method == 'PUT').body) as Map;

void main() {
  test('insumo avulso e cadastro que sumiu usam o preço copiado (igual ao servidor)', () {
    Custo custo(List insumos, {List cadastro = const []}) => custoDaReceita({
          'filamentos': [
            {'preco_kg': 100, 'gramas': 33}
          ],
          'horas': 3,
          'mao_obra_min': 10,
          'insumos': insumos,
        }, filamentos: const [], insumos: cadastro, impressoras: const [], config: _config);
    final c = custo([
      {'nome': 'Switch', 'custo_unitario': 1.5, 'qtd': 1},
      {'nome': 'Argola', 'custo_unitario': 0.25, 'qtd': 2},
      {'nome': 'Saquinho', 'custo_unitario': 0.4, 'qtd': 1, 'embalagem': true},
    ]);
    expect([c.insumos, c.embalagem, c.total], [2.0, 0.4, 8.72]);
    final semCadastro = custo([
      {'insumo_id': 'sumiu', 'custo_unitario': 1.5, 'qtd': 1}
    ]);
    expect(semCadastro.insumos, 1.5);
    final cadastroManda = custo([
      {'insumo_id': 'i1', 'custo_unitario': 1.5, 'qtd': 1}
    ], cadastro: [
      {'id': 'i1', 'nome': 'Switch', 'custo_unitario': 2, 'categoria': 'insumo'}
    ]);
    expect(cadastroManda.insumos, 2.0);
  });

  test('6 chaveiros por impressão: gramas e tempo da mesa, custo por unidade igual ao de 1', () {
    Custo custo(Map r) => custoDaReceita(r, filamentos: const [], insumos: const [], impressoras: const [], config: _config);
    final mesa = custo({
      'filamentos': [
        {'preco_kg': 100, 'gramas': 198}
      ],
      'horas': 18,
      'mao_obra_min': 10,
      'pecas_por_impressao': 6,
    });
    expect(mesa.total, 6.32);
  });

  testWidgets('modelo com duas peças de cores diferentes e insumo: custo soma tudo e salva cada peça', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 400, 2600);
    await tester.pumpWidget(amb.tela(const ModeloForm(dados: {
      'id': 'm1',
      'nome': 'Fidget switch',
      'receita': {
        'filamentos': [
          {'filamento_id': 'f1', 'gramas': 20, 'nome': 'Case', 'horas': 2},
          {'filamento_id': 'f2', 'gramas': 13, 'nome': 'Keycap', 'horas': 1},
        ],
        'horas': 3,
        'mao_obra_min': 10,
        'insumos': [
          {'nome': 'Switch', 'custo_unitario': 1.5, 'qtd': 1}
        ],
      }
    })));
    await tester.pumpAndSettle();
    expect(find.text('Custo R\$ 7,82'), findsOneWidget); // 6,32 da planilha + switch
    expect(find.text('Switch'), findsOneWidget);
    await tester.tap(find.byTooltip('Mais').last); // 2 switches
    await tester.pumpAndSettle();
    expect(find.text('Custo R\$ 9,32'), findsOneWidget);

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final receita = _corpoPut(amb)['receita'] as Map;
    expect(receita['horas'], 3.0);
    expect([for (final f in receita['filamentos'] as List) '${f['nome']}|${f['filamento_id']}|${f['horas']}'],
        ['Case|f1|2.0', 'Keycap|f2|1.0']);
    expect((receita['insumos'] as List).single, containsPair('qtd', 2.0));
  });

  testWidgets('receita antiga (tempo só no total) mantém o tempo ao salvar', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 400, 2400);
    await tester.pumpWidget(amb.tela(const ModeloForm(dados: {
      'id': 'm1',
      'nome': 'Chaveiro',
      'receita': {
        'filamentos': [
          {'filamento_id': 'f1', 'gramas': 33}
        ],
        'horas': 3,
        'mao_obra_min': 10
      }
    })));
    await tester.pumpAndSettle();
    expect(find.text('Custo R\$ 6,32'), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect((_corpoPut(amb)['receita'] as Map)['horas'], 3.0);
  });

  testWidgets('orçar: meu preço vale mais que as margens; 2 unidades viram modelo de UMA unidade', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 400, 2600);
    await tester.pumpWidget(amb.tela(const OrcarTela()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gramas0')), '33');
    await tester.enterText(find.byKey(const Key('tempo0')), '3');
    await tester.tap(find.byTooltip('Mais uma'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('meu_preco')), '30,00');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('preco'))).data, 'R\$ 30,00');
    expect(tester.widget<Text>(find.byKey(const Key('lucro'))).data, 'lucro R\$ 17,36 · custo R\$ 12,64');

    await tester.ensureVisible(find.byKey(const Key('para_catalogo')));
    await tester.tap(find.byKey(const Key('para_catalogo')));
    await tester.pumpAndSettle();
    expect(find.text('Novo modelo'), findsOneWidget);
    expect(find.text('Custo R\$ 6,32'), findsOneWidget, reason: 'custo de uma unidade');
    expect(find.text('15,00'), findsOneWidget, reason: 'preço de uma unidade');
  });

  testWidgets('orçar: kit de duas peças diferentes vai para o catálogo como um modelo com o mesmo custo', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 400, 2600);
    await tester.pumpWidget(amb.tela(const OrcarTela(inicial: {
      'itens': [
        {'nome': 'Case', 'gramas': '20', 'tempo': '2', 'qtd': 1},
        {'nome': 'Keycap', 'gramas': '13', 'tempo': '1', 'qtd': 1, 'filamento_id': 'f2'},
      ],
      'filamento_id': 'f1',
      'mao_obra': '5',
    })));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('lucro'))).data, endsWith('custo R\$ 6,32'));
    await tester.ensureVisible(find.byKey(const Key('para_catalogo')));
    await tester.tap(find.byKey(const Key('para_catalogo')));
    await tester.pumpAndSettle();
    expect(find.text('Custo R\$ 6,32'), findsOneWidget, reason: 'mesmo custo do orçamento');
    expect(find.text('Keycap'), findsOneWidget);
  });
}

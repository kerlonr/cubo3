// Revisão do commit 8451bff: receita antiga aberta e salva, custo app × servidor, orçamento → catálogo.
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
          ],
      'GET /api/empresa/config': (_) => _config,
    })
      ..rotasPrefixo['PUT /api/modelos/'] = (r) => {'id': 'm1'};

Map _corpoPut(Ambiente amb) => jsonDecode(amb.recebidos.lastWhere((r) => r.method == 'PUT').body) as Map;

Future<Map> _abrirESalvar(WidgetTester tester, Map receita) async {
  final amb = _amb();
  await amb.preparar();
  await tamanhoTela(tester, 400, 2600);
  await tester.pumpWidget(amb.tela(ModeloForm(dados: {'id': 'm1', 'nome': 'Antigo', 'receita': receita})));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Salvar'));
  await tester.pumpAndSettle();
  if (find.text('Salvar assim').evaluate().isNotEmpty) {
    await tester.tap(find.text('Salvar assim'));
    await tester.pumpAndSettle();
  }
  return _corpoPut(amb)['receita'] as Map;
}

void main() {
  testWidgets('receita antiga: filamento avulso sem preço (2ª peça, sem tempo) some ao abrir e salvar',
      (tester) async {
    final r = await _abrirESalvar(tester, {
      'filamentos': [
        {'filamento_id': 'f1', 'gramas': 33},
        {'filamento_id': null, 'gramas': 12}, // antigo: avulso salvo sem preco_kg
      ],
      'horas': 3,
      'mao_obra_min': 10,
    });
    expect((r['filamentos'] as List).length, 2, reason: 'peça de 12 g foi descartada: ${r['filamentos']}');
  });

  testWidgets('receita antiga: tempo com fração de minuto muda só de abrir e salvar', (tester) async {
    final r = await _abrirESalvar(tester, {
      'filamentos': [
        {'filamento_id': 'f1', 'gramas': 33}
      ],
      'horas': 3.17,
      'mao_obra_min': 10,
    });
    expect(r['horas'], 3.17);
  });

  test('filamento excluído: o app carrega os excluídos para o custo e dá 6,32 como o servidor', () {
    expect(caminhosCusto['filamentos'], contains('incluir_excluidos=true'));
    expect(caminhosCusto['insumos'], contains('incluir_excluidos=true'));
    final c = custoDaReceita({
      'filamentos': [
        {'filamento_id': 'excluido', 'gramas': 33}
      ],
      'horas': 3,
      'mao_obra_min': 10,
    }, filamentos: const [
      {'id': 'excluido', 'preco_kg': 100, 'excluido': true}
    ], insumos: const [], impressoras: const [], config: _config);
    expect(c.total, 6.32, reason: 'servidor dá 6,32 (test_filamento_excluido_servidor_conta_preco)');
  });

  testWidgets('orçar: kit com 10 de cada peça vai para o catálogo com o mesmo custo', (tester) async {
    final amb = _amb();
    await amb.preparar();
    await tamanhoTela(tester, 400, 2600);
    await tester.pumpWidget(amb.tela(const OrcarTela(inicial: {
      'itens': [
        {'nome': 'Case', 'gramas': '33,04', 'tempo': '3', 'qtd': 10},
        {'nome': 'Keycap', 'gramas': '5', 'tempo': '0,5', 'qtd': 10},
      ],
    })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('meu_preco')), '100,00');
    await tester.pumpAndSettle();
    final textoOrcar = tester.widget<Text>(find.byKey(const Key('lucro'))).data!;
    final custoOrcar = textoOrcar.split('custo ').last;
    await tester.ensureVisible(find.byKey(const Key('para_catalogo')));
    await tester.tap(find.byKey(const Key('para_catalogo')));
    await tester.pumpAndSettle();
    expect(find.text('Custo $custoOrcar'), findsOneWidget,
        reason: 'orçar: $custoOrcar; catálogo: ${find.textContaining('Custo R').evaluate().map((e) => (e.widget as Text).data).toList()}');
  });
}

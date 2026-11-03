import 'dart:convert';

import 'package:cubo3/telas/impressoes/confirmar_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

Map<String, Object?> carretel(String id, String cor) => {
      'id': id,
      'filamento_id': 'f-$id',
      'saldo_g': 800,
      'arquivado': false,
      'excluido': false,
      'filamento': {'id': 'f-$id', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': id, 'cor_hex': cor, 'excluido': false},
    };

Map<String, Object?> impressao({required Map estimativa, String? modeloId}) => {
      'id': 'i1',
      'arquivo': 'vaso.gcode',
      'duracao_s': 4000,
      'status': 'a_confirmar',
      'modelo_id': modeloId,
      'miniatura_url': null,
      'estimativa': estimativa,
    };

const umaCor = {
  'gramas_total': 125.33,
  'filamentos': [
    {'tipo': 'PLA', 'marca': 'Voolt', 'cor': '#FFFFFF', 'gramas': 125.33}
  ]
};

const duasCores = {
  'gramas_total': 1.71,
  'filamentos': [
    {'tipo': 'PLA', 'marca': null, 'cor': '#FFFFFF', 'gramas': null},
    {'tipo': 'PLA', 'marca': null, 'cor': '#000000', 'gramas': null},
  ]
};

Ambiente ambiente() => Ambiente({
      'GET /api/estoque': (_) => {
            'carreteis': [carretel('preto', '#000000'), carretel('branco', '#FFFFFF')],
            'filamentos': [],
            'insumos': [],
            'pecas': []
          },
      'GET /api/modelos': (_) => [
            {'id': 'm1', 'nome': 'Vaso', 'excluido': false}
          ],
    });

Future<void> abrir(WidgetTester tester, Ambiente amb, Map imp) async {
  await amb.preparar();
  await tamanhoTela(tester, 500, 1600);
  await tester.pumpWidget(amb.tela(ConfirmarTela(impressao: Map<String, dynamic>.from(imp))));
  await tester.pumpAndSettle();
}

void main() {
  test('estimativa: uma cor usa o total; várias cores dividem sem perder centavo', () {
    expect(dividirEstimativa(umaCor).gramas, [125.33]);
    expect(dividirEstimativa(umaCor).aviso, isFalse);
    final d = dividirEstimativa(duasCores);
    expect(d.gramas, [0.86, 0.85]);
    expect(d.aviso, isTrue);
  });

  testWidgets('uma cor pré-preenche 125,33 e escolhe o carretel da cor', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb, impressao(estimativa: umaCor));
    expect(find.text('125,33'), findsOneWidget);
  });

  testWidgets('duas cores pré-preenchem 0,86 + 0,85 e avisam para conferir', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb, impressao(estimativa: duasCores));
    expect(find.text('0,86'), findsOneWidget);
    expect(find.text('0,85'), findsOneWidget);
    expect(find.textContaining('confira'), findsOneWidget);
  });

  testWidgets('venda sem modelo pede o modelo e não envia', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb, impressao(estimativa: umaCor));
    await tester.tap(find.text('Venda'));
    await tester.pump();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('Escolha o modelo'), findsOneWidget);
    expect(amb.ultimo('POST /api/impressoes/i1/confirmar'), isNull);
  });

  testWidgets('confirmar manda finalidade e consumo por carretel', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb, impressao(estimativa: umaCor, modeloId: 'm1'));
    await tester.tap(find.text('Venda'));
    await tester.pump();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    final corpo = amb.corpo('POST /api/impressoes/i1/confirmar');
    expect(corpo['finalidade'], 'venda');
    expect(corpo['modelo_id'], 'm1');
    expect(corpo['pecas_boas'], 1);
    expect(corpo['consumos'], [
      {'carretel_id': 'branco', 'gramas': 125.33}
    ]);
    expect(jsonEncode(corpo['perdas']), '[]');
  });

  testWidgets('descartar pede confirmação', (tester) async {
    final amb = ambiente();
    await abrir(tester, amb, impressao(estimativa: umaCor));
    await tester.tap(find.text('Não era para registrar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('POST /api/impressoes/i1/descartar'), isNull);
    await tester.tap(find.text('Não era para registrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('POST /api/impressoes/i1/descartar'), isNotNull);
  });
}

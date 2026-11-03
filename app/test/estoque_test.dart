import 'dart:convert';

import 'package:cubo3/telas/estoque/acoes_estoque.dart';
import 'package:cubo3/telas/estoque/carretel_form.dart';
import 'package:cubo3/telas/estoque/estoque_aba.dart';
import 'package:cubo3/widgets/seletores.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

final uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

Map<String, Object?> carretel(String id, String material, String cor, {bool arquivado = false, double saldo = 500}) => {
      'id': id,
      'filamento_id': 'f-$id',
      'saldo_g': saldo,
      'arquivado': arquivado,
      'excluido': false,
      'aberto': true,
      'local': null,
      'filamento': {'id': 'f-$id', 'marca': 'Voolt', 'material': material, 'cor_nome': cor, 'cor_hex': cor, 'excluido': false},
    };

void main() {
  testWidgets('novo carretel gera PUT com filamento, peso, preço e data AAAA-MM-DD', (tester) async {
    final amb = Ambiente({
      'GET /api/filamentos': (_) => [
            {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Branco', 'cor_hex': '#FFFFFF', 'preco_kg': 100}
          ],
    });
    await amb.preparar();
    await tester.pumpWidget(amb.tela(const CarretelForm()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('preco')), '8990');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final put = amb.recebidos.lastWhere((r) => r.method == 'PUT' && r.url.path.startsWith('/api/carreteis/'));
    expect(uuidV4.hasMatch(put.url.pathSegments.last), isTrue);
    final corpo = jsonDecode(put.body) as Map;
    expect(corpo['filamento_id'], 'f1');
    expect(corpo['peso_inicial_g'], 1000);
    expect(corpo['preco_pago'], 89.9);
    expect(corpo['data_compra'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  testWidgets('cada pesagem manda um movimento_id novo', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tester.pumpWidget(amb.tela(const SizedBox()));
    await enviarPesagem(amb.fila, 'c1', 900);
    await enviarPesagem(amb.fila, 'c1', 880);
    final ids = amb.recebidos
        .where((r) => r.url.path == '/api/carreteis/c1/pesagem')
        .map((r) => (jsonDecode(r.body) as Map)['movimento_id'] as String)
        .toList();
    expect(ids, hasLength(2));
    expect(ids.every(uuidV4.hasMatch), isTrue);
    expect(ids.toSet(), hasLength(2));
    expect(jsonDecode(amb.ultimo('POST /api/carreteis/c1/pesagem')!.body)['peso_balanca_g'], 880);
  });

  test('SeletorCarretel não lista arquivado e põe primeiro a cor pedida', () {
    final lista = [
      carretel('preto', 'PLA', '#000000'),
      carretel('arq', 'PLA', '#FFFFFF', arquivado: true),
      carretel('branco', 'PLA', '#ffffff'),
      carretel('petg', 'PETG', '#FFFFFF'),
    ];
    final ordem = ordenarCarreteis(lista, material: 'PLA', cor: '#FFFFFF').map((c) => c['id']).toList();
    expect(ordem, ['branco', 'petg', 'preto']);
  });

  testWidgets('filamento com estoque baixo mostra "Repor"', (tester) async {
    final amb = Ambiente({
      'GET /api/estoque': (_) => {
            'carreteis': [],
            'filamentos': [
              {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Branco', 'cor_hex': '#FFFFFF', 'total_g': 120, 'baixo': true},
              {'id': 'f2', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Preto', 'cor_hex': '#000000', 'total_g': 900, 'baixo': false},
            ],
            'insumos': [],
            'pecas': [],
          },
    });
    await amb.preparar();
    await tester.pumpWidget(amb.tela(const EstoqueAba()));
    await tester.pumpAndSettle();
    expect(find.text('Voolt PLA Branco'), findsOneWidget);
    expect(find.text('Repor'), findsOneWidget);
    expect(find.text('120 g'), findsOneWidget);
  });
}

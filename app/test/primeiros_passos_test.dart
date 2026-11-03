import 'package:cubo3/telas/inicio/inicio_aba.dart';
import 'package:cubo3/telas/mais/impressoras_tela.dart';
import 'package:cubo3/telas/vendas/clientes_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

const passos = [
  'Cadastrar impressora',
  'Cadastrar filamento',
  'Registrar um carretel',
  'Criar um modelo',
  'Fazer a primeira venda',
];

Ambiente completa() => Ambiente({
      'GET /api/impressoras': (_) => [
            {'id': 'i1', 'nome': 'Ender'}
          ],
      'GET /api/estoque': (_) => {
            'filamentos': [
              {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Branco', 'cor_hex': '#FFFFFF', 'total_g': 900}
            ],
            'carreteis': [
              {'id': 'c1', 'filamento_id': 'f1', 'saldo_g': 900}
            ],
            'insumos': [],
            'pecas': [],
          },
      'GET /api/modelos': (_) => [
            {'id': 'm1', 'nome': 'Vaso'}
          ],
      'GET /api/pedidos': (_) => [
            {'id': 'p1', 'status': 'entregue'}
          ],
    });

void main() {
  testWidgets('empresa vazia mostra os 5 passos e o primeiro abre o cadastro de impressora', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 2400);
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    expect(find.text('Primeiros passos'), findsOneWidget);
    for (final p in passos) {
      expect(find.text(p), findsOneWidget, reason: p);
    }
    expect(find.text('Sem vendas nem gastos ainda'), findsOneWidget, reason: 'sem gráfico vazio ocupando espaço');
    await tester.tap(find.text('Cadastrar impressora'));
    await tester.pumpAndSettle();
    expect(find.byType(ImpressoraForm), findsOneWidget);
  });

  testWidgets('com tudo cadastrado o cartão some e não volta a buscar as listas', (tester) async {
    final amb = completa();
    await amb.preparar();
    await tamanhoTela(tester, 400, 2400);
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    expect(find.text('Primeiros passos'), findsNothing);
    expect(amb.ultimo('GET /api/pedidos'), isNotNull);

    amb.recebidos.clear();
    await tester.pumpWidget(amb.tela(const SizedBox()));
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    expect(find.text('Primeiros passos'), findsNothing);
    expect(amb.ultimo('GET /api/pedidos'), isNull, reason: 'concluído fica guardado no aparelho');
  });

  testWidgets('Início tem as ações rápidas', (tester) async {
    final amb = completa();
    await amb.preparar();
    await tamanhoTela(tester, 400, 2400);
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    for (final a in ['Vender', 'Lançar impressão', 'Novo carretel', 'Orçar']) {
      expect(find.text(a), findsOneWidget, reason: a);
    }
  });

  testWidgets('lista de clientes vazia explica e oferece "Cadastrar cliente"', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 1200);
    await tester.pumpWidget(amb.tela(const ClientesTela()));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum cliente ainda'), findsOneWidget);
    expect(find.textContaining('histórico'), findsOneWidget);
    await tester.tap(find.text('Cadastrar cliente'));
    await tester.pumpAndSettle();
    expect(find.byType(ClienteForm), findsOneWidget);
  });
}

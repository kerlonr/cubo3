import 'package:cubo3/api/sessao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

void main() {
  testWidgets('login inválido mostra o detail do servidor', (tester) async {
    final amb = Ambiente({'POST /api/auth/login': (_) => json({'detail': 'E-mail ou senha incorretos'}, 401)});
    await amb.preparar(logado: false);
    await tester.pumpWidget(amb.app());
    await tester.enterText(find.byKey(const Key('email')), 'k@x.com');
    await tester.enterText(find.byKey(const Key('senha')), 'errada123');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha incorretos'), findsOneWidget);
  });

  testWidgets('login ok com uma empresa abre a casca com as 5 abas', (tester) async {
    final amb = Ambiente({'POST /api/auth/login': (_) => {'acesso': 'A', 'refresh': 'R', 'trocar_senha': false}});
    await amb.preparar(logado: false);
    await tamanhoTela(tester, 400);
    await tester.pumpWidget(amb.app());
    await tester.enterText(find.byKey(const Key('email')), 'k@x.com');
    await tester.enterText(find.byKey(const Key('senha')), 'certa1234');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(amb.sessao.estado, EstadoSessao.pronta);
    final barra = find.byType(NavigationBar);
    expect(barra, findsOneWidget);
    for (final aba in ['Início', 'Impressões', 'Catálogo', 'Estoque', 'Vendas']) {
      expect(find.descendant(of: barra, matching: find.text(aba)), findsOneWidget);
    }
  });

  testWidgets('tela larga usa trilho lateral; estreita usa barra inferior', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 1200);
    await tester.pumpWidget(amb.app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tamanhoTela(tester, 400);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('"+" mostra as 4 ações rápidas', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400);
    await tester.pumpWidget(amb.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    for (final acao in ['Venda rápida', 'Lançar impressão', 'Novo carretel', 'Orçar peça']) {
      expect(find.text(acao), findsOneWidget);
    }
  });
}

import 'package:cubo3/telas/casca.dart';
import 'package:cubo3/main.dart';
import 'package:cubo3/api/sessao.dart';
import 'package:cubo3/widgets/adaptativo.dart';
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

  testWidgets('login ok com uma empresa abre a casca com as 4 abas', (tester) async {
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
    for (final aba in ['Início', 'Impressora', 'Catálogo', 'Vendas']) {
      expect(find.descendant(of: barra, matching: find.text(aba)), findsOneWidget);
    }
    expect(find.descendant(of: barra, matching: find.text('Estoque')), findsNothing);
  });

  testWidgets('médio (600–839) e expandido usam trilho lateral; compacto (< 600) usa barra inferior', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 1200);
    await tester.pumpWidget(amb.app());
    await tester.pumpAndSettle();
    for (final (largura, trilho) in [(1200.0, true), (840.0, true), (600.0, true), (599.0, false), (400.0, false)]) {
      await tamanhoTela(tester, largura);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), trilho ? findsOneWidget : findsNothing, reason: '$largura');
      expect(find.byType(NavigationBar), trilho ? findsNothing : findsOneWidget, reason: '$largura');
    }
  });

  test('classes de largura do Material 3', () {
    expect([for (final l in [320.0, 599.9, 600.0, 839.9, 840.0, 1280.0]) ClasseLargura.daLargura(l)], [
      ClasseLargura.compacto,
      ClasseLargura.compacto,
      ClasseLargura.medio,
      ClasseLargura.medio,
      ClasseLargura.expandido,
      ClasseLargura.expandido,
    ]);
  });

  testWidgets('"+" junta as ações do dia a dia, gira ao abrir e leva para a tela certa', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 1200);
    await tester.pumpWidget(amb.app());
    await tester.pumpAndSettle();
    double giro() => tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;
    expect(giro(), 0);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    for (final (_, acao) in acoesRapidas) {
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(acao)), findsOneWidget, reason: acao);
    }
    expect(giro(), 0.125, reason: '"+" vira "×" enquanto a folha está aberta');
    await tester.tap(find.text('Venda rápida'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Venda rápida'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(giro(), 0, reason: 'folha fechada, o botão volta ao "+"');
  });

  testWidgets('aba Impressora mostra a impressora e só liga a câmera quando está na frente', (tester) async {
    final amb = Ambiente({
      'GET /api/impressoras': (_) => [
            {'id': 'i1', 'nome': 'Ender', 'moonraker_url': 'http://192.168.1.110:7125'}
          ],
      'GET /api/impressoras/i1/ao-vivo': (_) => {'estado': 'printing', 'arquivo': 'vaso.gcode', 'progresso': 0.4},
      'POST /api/impressoras/i1/camera/link': (_) => json({'detail': 'Sem câmera'}, 404),
    });
    await amb.preparar();
    await tamanhoTela(tester, 400, 1600);
    await tester.pumpWidget(amb.app());
    await tester.pumpAndSettle();
    expect(amb.ultimo('POST /api/impressoras/i1/camera/link'), isNull, reason: 'aba escondida não abre vídeo');
    await tester.tap(find.text('Impressora'));
    await tester.pumpAndSettle();
    expect(amb.ultimo('POST /api/impressoras/i1/camera/link'), isNotNull);
    expect(find.text('Sem câmera'), findsOneWidget);
    expect(find.text('Parada de emergência'), findsOneWidget);
  });

  testWidgets('tocar na notificação de progresso abre a aba Impressora', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400);
    await tester.pumpWidget(amb.app());
    await tester.pumpAndSettle();
    abrirNotificacao('impressora');
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
    expect(abaPedida.value, isNull);
  });
}

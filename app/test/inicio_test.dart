import 'package:cubo3/telas/vendas/clientes_tela.dart';
import 'package:cubo3/tema.dart';
import 'package:cubo3/telas/inicio/inicio_aba.dart';
import 'package:cubo3/telas/mais/empresa_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

Map<String, Object?> painel({required double resultado}) => {
      'receita': 100,
      'gastos': 100 - resultado,
      'resultado': resultado,
      'lucro_vendas': 30,
      'por_mes': [
        for (var m = 1; m <= 12; m++) {'mes': '2026-${m.toString().padLeft(2, '0')}', 'receita': m * 10.0, 'gastos': 5.0}
      ],
      'mais_vendidos': [
        {'modelo_id': 'm1', 'nome': 'Vaso', 'qtd': 4}
      ],
      'a_confirmar': 2,
      'estoque_baixo': [
        {'tipo': 'filamento', 'id': 'f1', 'nome': 'Voolt PLA Branco', 'saldo': 120}
      ],
      'horas_impressao': 12.5,
      'kg_filamento': 0.8,
    };

void main() {
  testWidgets('lucro do mês negativo em vermelho; investimento diz quanto falta para se pagar', (tester) async {
    final amb = Ambiente({'GET /api/painel': (_) => {...painel(resultado: -42.5), 'investido': 1700, 'recebido': 200}});
    await amb.preparar();
    await tamanhoTela(tester, 400, 2000);
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mostrar valores'));
    await tester.pumpAndSettle();
    final lucro = tester.widget<Text>(find.byKey(const Key('lucro_mes')));
    expect(lucro.data, '-R\$ 42,50');
    expect(lucro.style!.color, vermelho);
    expect(find.text('Faltam R\$ 1.500,00 para se pagar'), findsOneWidget);
    expect(find.text('A confirmar (2)'), findsOneWidget);
    expect(find.text('Orçar peça'), findsNothing, reason: 'orçar fica no "+"');
    expect(find.text('Voolt PLA Branco'), findsOneWidget, reason: 'filamento acabando');
    final q = amb.ultimo('GET /api/painel')!.url.queryParameters;
    expect(q['inicio'], endsWith('-01'));
  });

  testWidgets('impressão em andamento e pedidos em aberto aparecem; impressora parada não', (tester) async {
    var estado = 'printing';
    final amb = Ambiente({
      'GET /api/painel': (_) => painel(resultado: 10),
      'GET /api/impressoras': (_) => [
            {'id': 'i1', 'nome': 'Ender', 'moonraker_url': 'http://192.168.1.110:7125'}
          ],
      'GET /api/impressoras/i1/ao-vivo': (_) => {'estado': estado, 'arquivo': 'vaso.gcode', 'progresso': 0.4, 'restante_s': 3600},
      'GET /api/pedidos': (_) => [
            {'id': 'p1', 'status': 'produzindo'},
            {'id': 'p2', 'status': 'aprovado'},
            {'id': 'p3', 'status': 'orcamento'},
            {'id': 'p4', 'status': 'entregue'},
          ],
    });
    await amb.preparar();
    await tamanhoTela(tester, 360, 2000);
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    expect(find.text('vaso.gcode'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('2 produzindo · 1 orçamento'), findsOneWidget);

    estado = 'standby';
    await tester.pumpWidget(amb.tela(const SizedBox()));
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    expect(find.text('Ender'), findsNothing);
  });

  testWidgets('valores começam escondidos; o olho mostra e a escolha fica lembrada', (tester) async {
    final amb = Ambiente({'GET /api/painel': (_) => {...painel(resultado: 10), 'investido': 100, 'recebido': 50}});
    await amb.preparar();
    await tamanhoTela(tester, 400, 2000);
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('lucro_mes'))).data, 'R\$ ••••');
    expect(find.text('Faltam R\$ •••• para se pagar'), findsOneWidget);
    await tester.tap(find.byTooltip('Mostrar valores'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('lucro_mes'))).data, 'R\$ 10,00');
    await tester.pumpWidget(amb.tela(const SizedBox()));
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Esconder valores'), findsOneWidget, reason: 'lembra a escolha');
  });

  testWidgets('investimento já pago mostra o que sobrou', (tester) async {
    final amb = Ambiente({'GET /api/painel': (_) => {...painel(resultado: 10), 'investido': 100, 'recebido': 130.5}});
    await amb.preparar();
    await tamanhoTela(tester, 400, 2000);
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mostrar valores'));
    await tester.pumpAndSettle();
    expect(find.text('Já se pagou e sobrou R\$ 30,50'), findsOneWidget);
  });

  testWidgets('membro não vê "Adicionar usuário"; dono vê', (tester) async {
    for (final (papel, esperado) in [('membro', findsNothing), ('dono', findsOneWidget)]) {
      final amb = Ambiente({
        'GET /api/empresa/membros': (_) => [
              {'id': 'u', 'nome': 'Kerlon', 'email': 'k@x.com', 'papel': 'dono'}
            ],
      });
      await amb.preparar(papel: papel);
      await tamanhoTela(tester, 500, 2000);
      await tester.pumpWidget(amb.tela(const EmpresaTela()));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar usuário'), esperado, reason: papel);
    }
  });

  testWidgets('tocar em "Pedidos em aberto" abre Vendas já filtrando os em andamento', (tester) async {
    final amb = Ambiente({
      'GET /api/pedidos': (_) => [
            {'id': 'p1', 'status': 'produzindo', 'itens': []},
            {'id': 'p2', 'status': 'entregue', 'itens': []},
          ],
    });
    await amb.preparar();
    await tamanhoTela(tester, 400, 1600);
    await tester.pumpWidget(amb.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pedidos em aberto'));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 3);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Em andamento')).selected, isTrue);
    expect(find.text('1 pedido'), findsOneWidget); // só o produzindo; o entregue fica fora
  });

  testWidgets('clientes agrupados pela letra, com telefone formatado e WhatsApp', (tester) async {
    final amb = Ambiente({
      'GET /api/clientes': (_) => [
            {'id': 'c1', 'nome': 'Ágata Lima', 'telefone': '54999998888'},
            {'id': 'c2', 'nome': 'Bruno', 'email': 'b@x.com'},
            {'id': 'c3', 'nome': 'Ana'},
          ],
    });
    await amb.preparar();
    await tamanhoTela(tester, 360, 1400);
    await tester.pumpWidget(amb.tela(const ClientesTela()));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNWidgets(2), reason: 'cabeçalho da letra + avatar da Ana');
    expect(find.text('B'), findsWidgets);
    expect(find.text('(54) 99999-8888'), findsOneWidget);
    expect(find.text('ÁL'), findsOneWidget, reason: 'iniciais no avatar');
    expect(find.byTooltip('WhatsApp'), findsOneWidget, reason: 'só quem tem telefone');
    expect(find.text('Sem contato'), findsOneWidget);
  });
}

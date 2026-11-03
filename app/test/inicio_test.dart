import 'package:cubo3/tema.dart';
import 'package:cubo3/telas/inicio/inicio_aba.dart';
import 'package:cubo3/telas/mais/calculadora_tela.dart';
import 'package:cubo3/telas/mais/empresa_tela.dart';
import 'package:cubo3/widgets/cartoes.dart';
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
  testWidgets('resultado negativo do painel aparece em vermelho; estoque baixo pede reposição', (tester) async {
    final amb = Ambiente({'GET /api/painel': (_) => painel(resultado: -42.5)});
    await amb.preparar();
    await tamanhoTela(tester, 500, 2400);
    await tester.pumpWidget(amb.tela(const InicioAba()));
    await tester.pumpAndSettle();
    final cartao = tester.widget<CartaoValor>(find.widgetWithText(CartaoValor, 'Resultado'));
    expect(cartao.cor, vermelho);
    expect(cartao.valor, '-R\$ 42,50');
    expect(find.text('Repor'), findsOneWidget);
    expect(find.text('A confirmar (2)'), findsOneWidget);
    final q = amb.ultimo('GET /api/painel')!.url.queryParameters;
    expect(q['inicio'], endsWith('-01'));
  });

  testWidgets('calculadora sem rede usa o cache: 6,32 e 7,90 / 9,03 / 12,64; canal inviável', (tester) async {
    final amb = Ambiente({
      'GET /api/filamentos': (_) => [
            {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Branco', 'cor_hex': '#FFFFFF', 'preco_kg': 100}
          ],
      'GET /api/empresa/config': (_) =>
          {'eficiencia': 1.1, 'mao_obra_hora': 10, 'kwh': 0.656, 'reserva': 1.3, 'margens': [20, 30, 50]},
      'GET /api/canais': (_) => [
            {'id': 'c1', 'nome': 'Direto', 'taxa_pct': 0, 'taxa_fixa': 0},
            {'id': 'c2', 'nome': 'Caro', 'taxa_pct': 80, 'taxa_fixa': 0},
          ],
    });
    await amb.preparar();
    await tamanhoTela(tester, 500, 2400);
    await tester.pumpWidget(amb.tela(const CalculadoraTela()));
    await tester.pumpAndSettle();

    amb.online = false;
    await tester.pumpWidget(amb.tela(const SizedBox()));
    await tester.pumpWidget(amb.tela(const CalculadoraTela()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sem conexão'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('gramas0')), '33');
    await tester.enterText(find.byKey(const Key('horas')), '3');
    await tester.enterText(find.byKey(const Key('mao_obra')), '10');
    await tester.pumpAndSettle();
    expect(find.text('R\$ 6,32'), findsWidgets);
    for (final p in ['R\$ 7,90', 'R\$ 9,03', 'R\$ 12,64']) {
      expect(find.text(p), findsWidgets);
    }
    expect(find.text('inviável'), findsOneWidget);
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
}

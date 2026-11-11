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
    final lucro = tester.widget<Text>(find.byKey(const Key('lucro_mes')));
    expect(lucro.data, '-R\$ 42,50');
    expect(lucro.style!.color, vermelho);
    expect(find.text('Faltam R\$ 1.500,00 para se pagar'), findsOneWidget);
    expect(find.text('A confirmar (2)'), findsOneWidget);
    expect(find.text('Orçar peça'), findsOneWidget);
    final q = amb.ultimo('GET /api/painel')!.url.queryParameters;
    expect(q['inicio'], endsWith('-01'));
  });

  testWidgets('investimento já pago mostra o que sobrou', (tester) async {
    final amb = Ambiente({'GET /api/painel': (_) => {...painel(resultado: 10), 'investido': 100, 'recebido': 130.5}});
    await amb.preparar();
    await tamanhoTela(tester, 400, 2000);
    await tester.pumpWidget(amb.tela(const InicioAba()));
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
}

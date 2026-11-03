import 'package:cubo3/api/api.dart';
import 'package:cubo3/telas/catalogo/arquivos.dart';
import 'package:cubo3/telas/catalogo/catalogo_aba.dart';
import 'package:cubo3/telas/catalogo/modelo_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

void main() {
  test('arquivo acima de 95 MB e extensão estranha são recusados antes de enviar', () async {
    final amb = Ambiente({});
    await amb.preparar();
    await expectLater(
      enviarArquivoModelo(amb.api, 'm1', nome: 'vaso.stl', tamanho: 150 * 1024 * 1024, bytes: const Stream.empty()),
      throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', 'Arquivo maior que 95 MB')),
    );
    await expectLater(
      enviarArquivoModelo(amb.api, 'm1', nome: 'virus.exe', tamanho: 10, bytes: const Stream.empty()),
      throwsA(isA<ErroApi>().having((e) => e.mensagem, 'mensagem', 'Tipo de arquivo não aceito')),
    );
    expect(amb.recebidos, isEmpty);
    expect(validarArquivo('Peça.3MF', 1000), isNull);
  });

  testWidgets('catálogo pede mais vendidos por padrão', (tester) async {
    final amb = Ambiente({
      'GET /api/modelos': (_) => [
            {
              'id': 'm1',
              'nome': 'Vaso',
              'preco_venda': 30,
              'lucro_unitario': 20,
              'vendidos': 3,
              'capa_url': null,
              'categoria': 'Casa',
              'tags': [],
              'custo': {'total': 10},
            }
          ],
    });
    await amb.preparar();
    await tester.pumpWidget(amb.tela(const CatalogoAba()));
    await tester.pumpAndSettle();
    expect(amb.ultimo('GET /api/modelos')!.url.queryParameters['ordem'], 'mais_vendidos');
    expect(find.text('Vaso'), findsOneWidget);
    expect(find.text('R\$ 30,00'), findsOneWidget);
  });

  testWidgets('custo ao vivo no formulário com a receita da planilha', (tester) async {
    final amb = Ambiente({
      'GET /api/filamentos': (_) => [
            {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Branco', 'cor_hex': '#FFFFFF', 'preco_kg': 100}
          ],
      'GET /api/empresa/config': (_) =>
          {'eficiencia': 1.1, 'mao_obra_hora': 10, 'kwh': 0.656, 'reserva': 1.3, 'margens': [20, 30, 50]},
    });
    await amb.preparar();
    await tamanhoTela(tester, 500, 2000);
    await tester.pumpWidget(amb.tela(const ModeloForm()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nome')), 'Vaso');
    await tester.tap(find.text('Receita e custo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar filamento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gramas0')), '33');
    await tester.enterText(find.byKey(const Key('horas')), '3');
    await tester.enterText(find.byKey(const Key('mao_obra')), '10');
    await tester.pumpAndSettle();
    expect(find.text('Custo R\$ 6,32'), findsOneWidget);
  });
}

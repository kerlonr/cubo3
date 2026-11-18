import 'dart:convert';

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
    // Receita à vista (não mais escondida) e a primeira linha já vem com o filamento cadastrado.
    await tester.enterText(find.byKey(const Key('gramas0')), '33');
    await tester.enterText(find.byKey(const Key('horas0')), '3');
    await tester.enterText(find.byKey(const Key('mao_obra')), '10');
    await tester.pumpAndSettle();
    expect(find.text('Custo R\$ 6,32'), findsOneWidget);
  });

  Ambiente ambienteModelo() => Ambiente({
        'GET /api/filamentos': (_) => [
              {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Branco', 'cor_hex': '#FFFFFF', 'preco_kg': 100}
            ],
        'GET /api/empresa/config': (_) =>
            {'eficiencia': 1.1, 'mao_obra_hora': 10, 'kwh': 0.656, 'reserva': 1.3, 'margens': [20, 30, 50]},
      })
        ..rotasPrefixo['PUT /api/modelos/'] = (r) => {'id': 'm1'};

  testWidgets('filamento avulso vai para o servidor com o preço (antes o material virava R\$ 0)', (tester) async {
    final amb = ambienteModelo();
    await amb.preparar();
    await tamanhoTela(tester, 500, 2000);
    await tester.pumpWidget(amb.tela(const ModeloForm(dados: {
      'nome': 'Porta Pilha',
      'receita': {
        'filamentos': [
          {'filamento_id': null, 'preco_kg': 100, 'gramas': 33}
        ],
        'horas': 3,
        'mao_obra_min': 10
      }
    })));
    await tester.pumpAndSettle();
    expect(find.text('Custo R\$ 6,32'), findsOneWidget);
    expect(find.byKey(const Key('preco_kg0')), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final put = amb.recebidos.lastWhere((r) => r.method == 'PUT');
    final fil = ((jsonDecode(put.body) as Map)['receita'] as Map)['filamentos'] as List;
    expect(fil.single, {'filamento_id': null, 'preco_kg': 100.0, 'gramas': 33.0, 'horas': 3.0});
  });

  testWidgets('tempo "3h11" vira 3,18 h; receita sem filamento pede confirmação', (tester) async {
    final amb = ambienteModelo();
    await amb.preparar();
    await tamanhoTela(tester, 500, 2000);
    await tester.pumpWidget(amb.tela(const ModeloForm()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nome')), 'Chaveiro');
    await tester.enterText(find.byKey(const Key('horas0')), '3h11');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Receita incompleta'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(amb.recebidos.where((r) => r.method == 'PUT'), isEmpty);
    await tester.enterText(find.byKey(const Key('gramas0')), '12');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final receita = (jsonDecode(amb.recebidos.lastWhere((r) => r.method == 'PUT').body) as Map)['receita'] as Map;
    expect((receita['horas'] as num).toStringAsFixed(2), '3.18');
  });

  testWidgets('modelo sem filamento aparece com "falta receita" no lugar do lucro', (tester) async {
    final amb = Ambiente({
      'GET /api/modelos': (_) => [
            {
              'id': 'm1',
              'nome': 'Chaveiro',
              'preco_venda': 10,
              'lucro_unitario': 10,
              'vendidos': 6,
              'capa_url': null,
              'tags': [],
              'receita': {'filamentos': [], 'horas': 0},
            }
          ],
    });
    await amb.preparar();
    await tester.pumpWidget(amb.tela(const CatalogoAba()));
    await tester.pumpAndSettle();
    expect(find.text('falta receita'), findsOneWidget);
    expect(find.text('lucro R\$ 10,00'), findsNothing);
  });

  testWidgets('filtro só por categoria: "Todos" volta a lista inteira e tags não viram filtro', (tester) async {
    Map<String, Object?> m(String id, String nome, String? cat) =>
        {'id': id, 'nome': nome, 'preco_venda': 10, 'capa_url': null, 'categoria': cat, 'tags': ['velha']};
    final amb = Ambiente({
      'GET /api/modelos': (_) => [m('a', 'Fidget', 'Chaveiro'), m('b', 'Porta Pilha', 'Case'), m('c', 'Placa', 'Chaveiro')],
    });
    await amb.preparar();
    await tamanhoTela(tester, 500, 1400);
    await tester.pumpWidget(amb.tela(const CatalogoAba()));
    await tester.pumpAndSettle();
    expect(find.text('#velha'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Chaveiro'));
    await tester.pumpAndSettle();
    expect(find.text('Porta Pilha'), findsNothing);
    expect(find.text('Placa'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Todos'));
    await tester.pumpAndSettle();
    expect(find.text('Porta Pilha'), findsOneWidget);
  });

  testWidgets('formulário sugere as categorias já usadas e mantém as tags antigas ao salvar', (tester) async {
    final amb = ambienteModelo()
      ..rotas['GET /api/modelos'] = (_) => [
            {'id': 'x', 'nome': 'A', 'categoria': 'Chaveiro'},
            {'id': 'y', 'nome': 'B', 'categoria': ' Case '},
          ];
    await amb.preparar();
    await tamanhoTela(tester, 500, 2000);
    await tester.pumpWidget(amb.tela(const ModeloForm(dados: {
      'id': 'm1',
      'nome': 'Fidget',
      'tags': ['antiga'],
      'receita': {
        'filamentos': [
          {'filamento_id': 'f1', 'gramas': 33}
        ],
        'horas': 3
      }
    })));
    await tester.pumpAndSettle();
    expect(find.text('Tags'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Chaveiro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final corpo = amb.corpo('PUT /api/modelos/m1');
    expect(corpo['categoria'], 'Chaveiro');
    expect(corpo['tags'], ['antiga']);
    expect(categoriasDe([{'categoria': 'Case'}, {'categoria': ' Case '}, {'categoria': ''}, {}]), ['Case']);
  });
}

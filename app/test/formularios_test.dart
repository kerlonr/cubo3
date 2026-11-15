import 'dart:convert';

import 'package:cubo3/api/fila.dart';
import 'package:cubo3/telas/estoque/carretel_form.dart';
import 'package:cubo3/telas/estoque/filamento_form.dart';
import 'package:cubo3/telas/mais/configuracoes_tela.dart';
import 'package:cubo3/telas/mais/empresa_tela.dart';
import 'package:cubo3/telas/mais/impressoras_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

Map put(Ambiente amb, String prefixo) =>
    jsonDecode(amb.recebidos.lastWhere((r) => r.method == 'PUT' && r.url.path.startsWith(prefixo)).body) as Map;

/// Abre o formulário por cima de outra tela (ele fecha sozinho ao salvar).
Future<void> abrir(WidgetTester tester, Ambiente amb, Widget form) async {
  await tester.pumpWidget(amb.tela(Builder(
      builder: (c) => TextButton(
          onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => form)), child: const Text('abrir')))));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('filamento só com cor e preço salva como PLA', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 1600);
    await abrir(tester, amb, const FilamentoForm());
    await tester.tap(find.byTooltip('Branco'));
    await tester.enterText(find.byKey(const Key('preco_kg')), '10000');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final corpo = put(amb, '/api/filamentos/');
    expect(corpo['material'], 'PLA');
    expect(corpo['cor_hex'], '#FFFFFF');
    expect(corpo['cor_nome'], 'Branco');
    expect(corpo['preco_kg'], 100);
    expect(corpo['marca'], isNotEmpty, reason: 'o servidor exige marca');
  });

  testWidgets('novo carretel abre com o último filamento usado', (tester) async {
    final amb = Ambiente({
      'GET /api/filamentos': (_) => [
            {'id': 'f1', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Branco', 'cor_hex': '#FFFFFF', 'preco_kg': 100},
            {'id': 'f2', 'marca': 'Voolt', 'material': 'PLA', 'cor_nome': 'Preto', 'cor_hex': '#000000', 'preco_kg': 100},
          ],
    });
    await amb.preparar();
    await tamanhoTela(tester, 400, 1600);
    await abrir(tester, amb, const CarretelForm());
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voolt PLA Preto').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('preco')), '8990');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(put(amb, '/api/carreteis/')['filamento_id'], 'f2');
    expect(put(amb, '/api/carreteis/')['peso_inicial_g'], 1000, reason: '1 kg vem marcado');

    await abrir(tester, amb, const CarretelForm());
    expect(find.text('Voolt PLA Preto'), findsOneWidget);
    await tester.tap(find.text('500 g'));
    await tester.enterText(find.byKey(const Key('preco')), '5000');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(put(amb, '/api/carreteis/')['filamento_id'], 'f2');
    expect(put(amb, '/api/carreteis/')['peso_inicial_g'], 500);
  });

  testWidgets('custos da empresa mostram o exemplo da planilha: R\$ 6,32 com os padrões', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 1600);
    await tester.pumpWidget(amb.tela(const ConfigEmpresaForm(dados: {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('R\$ 6,32'), findsOneWidget);
  });

  testWidgets('canal 20 % + R\$ 4 mostra quanto você recebe numa venda de R\$ 100', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 1600);
    await tester.pumpWidget(amb.tela(const CanalForm()));
    await tester.enterText(find.byKey(const Key('taxa_pct')), '20');
    await tester.enterText(find.byKey(const Key('taxa_fixa')), '400');
    await tester.pumpAndSettle();
    expect(find.textContaining('você recebe R\$ 76,00'), findsOneWidget);
  });

  testWidgets('"Testar conexão" salva a impressora e mostra o estado do Klipper', (tester) async {
    final amb = Ambiente({});
    amb.rotasPrefixo['GET /api/impressoras/'] = (_) => {'estado': 'standby'};
    await amb.preparar();
    await tamanhoTela(tester, 400, 1600);
    await tester.pumpWidget(amb.tela(const ImpressoraForm()));
    await tester.enterText(find.byKey(const Key('nome')), 'Ender');
    await tester.enterText(find.byKey(const Key('url')), 'http://192.168.1.110:7125');
    await tester.pump();
    await tester.tap(find.text('Testar conexão'));
    await tester.pumpAndSettle();
    final corpo = put(amb, '/api/impressoras/');
    expect(corpo['moonraker_url'], 'http://192.168.1.110:7125');
    expect(find.textContaining('Parada'), findsOneWidget);
  });

  testWidgets('Configurações em seções que explicam cada uma', (tester) async {
    final amb = Ambiente({});
    await amb.preparar();
    await tamanhoTela(tester, 400, 2400);
    await tester.pumpWidget(amb.tela(const ConfiguracoesTela()));
    await tester.pumpAndSettle();
    for (final s in ['Empresa', 'Custos', 'Canais de venda', 'Impressoras', 'Notificações', 'Conta', 'Avançado']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
  });

  testWidgets('Configurações: erro da fila tem "Tentar de novo", que devolve a operação para a fila', (tester) async {
    final amb = Ambiente({'PUT /api/clientes/c1': (_) => json({'detail': 'Cliente foi alterado por outra pessoa.'}, 409)});
    await amb.preparar();
    amb.online = false;
    await amb.fila.enviarOuGuardar(Operacao.nova('PUT', '/api/clientes/c1', {'nome': 'Ana'}));
    amb.online = true;
    await amb.fila.esvaziar();
    expect(amb.fila.erros, hasLength(1));
    amb.rotas['PUT /api/clientes/c1'] = (_) => {'id': 'c1'};
    await tamanhoTela(tester, 400, 2400);
    await tester.pumpWidget(amb.tela(const ConfiguracoesTela()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(amb.fila.erros, isEmpty);
    expect(amb.fila.pendentes, 0);
    expect(find.text('Cliente foi alterado por outra pessoa.'), findsNothing);
  });
}

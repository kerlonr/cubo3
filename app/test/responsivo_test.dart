// Nenhuma tela principal pode estourar (RenderFlex overflow) em largura nenhuma, com nomes longos e valores grandes.
// Capturas para revisão visual: flutter test test/responsivo_test.dart --update-goldens (não são comparadas no CI).
import 'dart:io';

import 'package:cubo3/api/fila.dart';
import 'package:cubo3/telas/casca.dart';
import 'package:cubo3/telas/catalogo/modelo_form.dart';
import 'package:cubo3/telas/catalogo/modelo_tela.dart';
import 'package:cubo3/telas/estoque/carretel_form.dart';
import 'package:cubo3/telas/estoque/filamento_form.dart';
import 'package:cubo3/telas/impressoes/confirmar_tela.dart';
import 'package:cubo3/telas/mais/configuracoes_tela.dart';
import 'package:cubo3/telas/mais/empresa_tela.dart';
import 'package:cubo3/telas/mais/impressoras_tela.dart';
import 'package:cubo3/telas/vendas/venda_rapida_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

const longo = 'Suporte articulado para fone de ouvido gamer com organizador de cabos e base antiderrapante';
const cliente = 'Maria Aparecida dos Santos Albuquerque Figueiredo de Oliveira';
const arquivo = 'suporte_articulado_fone_gamer_organizador_cabos_v12_final_0.2mm_PLA_3h45m.gcode';
const grande = 123456.78;

const impressoras = [
  {'id': 'i1', 'nome': 'Ender 3 V3 SE da oficina do fundo, bancada 2', 'moonraker_url': 'http://192.168.1.110:7125'},
  {'id': 'i2', 'nome': 'Bambu Lab A1 mini emprestada do Thales', 'moonraker_url': 'http://192.168.1.111:7125'},
];

final aoVivo = {
  'estado': 'printing',
  'arquivo': arquivo,
  'progresso': 0.42,
  'restante_s': 456789,
  'bico': 215.3,
  'bico_alvo': 215,
  'mesa': 60.1,
  'mesa_alvo': 60,
  'posicao': [123.456, 234.567, 345.678],
  'eixos_home': 'xy',
  'velocidade_pct': 300,
  'fluxo_pct': 150,
  'ventoinha_pct': 100,
  'z_offset': -0.125,
  'mensagem': 'Camada 123 de 456 — trocar o filamento para o Azul Petróleo Metalizado na próxima camada',
};

Map<String, Object?> filamento(String id) => {
      'id': id,
      'marca': 'Voolt3D Premium Importado',
      'material': 'PLA Silk',
      'cor_nome': 'Azul Petróleo Metalizado Brilhante',
      'cor_hex': '#1E3A5F',
      'preco_kg': 1234.56,
      'total_g': 123456.7,
      'baixo': true,
      'excluido': false,
    };

Map<String, Object?> modelo(String id) => {
      'id': id,
      'nome': '$longo $id',
      'preco_venda': grande,
      'lucro_unitario': -12345.67,
      'vendidos': 12345,
      'estoque': -1234,
      'capa_url': null,
      'categoria': 'Acessórios para escritório e setup gamer',
      'tags': ['presente-de-natal-corporativo', 'mais-vendido-da-loja'],
      'descricao': longo,
      'excluido': false,
      'custo': {'material': grande, 'mao_obra': grande, 'maquina': grande, 'insumos': grande, 'embalagem': grande, 'total': 617283.9},
      'links': [
        {'titulo': '', 'url': 'https://www.printables.com/model/123456-$arquivo'}
      ],
      'arquivos': [
        {'id': 'a1', 'nome_original': arquivo, 'tipo': 'gcode', 'tamanho': 98765432}
      ],
    };

Map<String, Object?> pedido(String id, String status) => {
      'id': id,
      'status': status,
      'pago': true,
      'data': '2026-11-03',
      'entregue_em': '2026-11-03T12:00:00Z',
      'receita': grande,
      'lucro': -12345.67,
      'cliente': {'id': 'k1', 'nome': cliente},
      'itens': [
        {'id': 'it$id', 'modelo_id': 'm1', 'descricao': longo, 'quantidade': 999, 'preco_unitario': grande},
      ],
    };

final estimativa = {
  'gramas_total': 12345.67,
  'filamentos': [
    {'tipo': 'PLA', 'marca': 'Voolt3D Premium Importado', 'cor': '#1E3A5F', 'gramas': null},
    {'tipo': 'PETG', 'marca': 'Voolt3D Premium Importado', 'cor': '#FFFFFF', 'gramas': null},
  ],
};

final impressao = {
  'id': 'p1',
  'impressora_id': 'i1',
  'arquivo': arquivo,
  'duracao_s': 456789,
  'fim': '2026-11-03T12:00:00Z',
  'status': 'a_confirmar',
  'modelo_id': 'm1',
  'miniatura_url': null,
  'estimativa': estimativa,
};

Ambiente cheio() => Ambiente({
      'GET /api/painel': (_) => {
            'receita': grande,
            'gastos': grande,
            'resultado': -grande,
            'lucro_vendas': grande,
            'por_mes': [
              for (var m = 1; m <= 12; m++) {'mes': '2026-${m.toString().padLeft(2, '0')}', 'receita': grande, 'gastos': grande / 2}
            ],
            'mais_vendidos': [
              {'modelo_id': 'm1', 'nome': longo, 'qtd': 123456}
            ],
            'a_confirmar': 123,
            'estoque_baixo': [
              {'tipo': 'filamento', 'id': 'f1', 'nome': 'Voolt3D Premium Importado PLA Silk Azul Petróleo Metalizado', 'saldo': 123456.7}
            ],
            'horas_impressao': 12345.5,
            'kg_filamento': 1234.56,
          },
      'GET /api/impressoras': (_) => impressoras,
      'GET /api/impressoras/i1/ao-vivo': (_) => aoVivo,
      'GET /api/impressoras/i2/ao-vivo': (_) => {...aoVivo, 'estado': 'standby'},
      'GET /api/impressoras/i1/arquivos': (_) => [
            for (var i = 0; i < 4; i++)
              {
                'nome': '${i}_$arquivo',
                'tamanho': 98765432,
                'modificado': '2026-11-03T12:00:00+00:00',
                'tempo_estimado_s': 456789,
                'gramas': 12345.67,
                'miniatura': i.isEven ? '.thumbs/a-300x300.png' : null,
              }
          ],
      'GET /api/impressoras/i1/macros': (_) => [
            for (final m in ['CANCEL_PRINT', 'PAUSE', 'RESUME', 'SET_PAUSE_NEXT_LAYER', 'SET_PAUSE_AT_LAYER_COM_NOME_MUITO_LONGO_DEMAIS'])
              {'nome': m}
          ],
      'GET /api/impressoras/i1/console': (_) => {
            'linhas': [
              for (var i = 0; i < 6; i++)
                {'hora': '2026-11-03T12:0$i:00+00:00', 'texto': i.isEven ? '// $longo' : 'ok T:215.3 /215.0 B:60.1 /60.0'}
            ]
          },
      'POST /api/impressoras/i1/camera/link': (_) => json({'detail': 'Sem câmera'}, 404),
      'POST /api/impressoras/i2/camera/link': (_) => json({'detail': 'Sem câmera'}, 404),
      'GET /api/impressoes': (_) => [
            for (final s in ['a_confirmar', 'confirmada', 'descartada', 'a_confirmar']) {...impressao, 'status': s}
          ],
      'GET /api/modelos': (_) => [for (var i = 1; i <= 6; i++) modelo('m$i')],
      'GET /api/modelos/m1': (_) => modelo('m1'),
      'GET /api/filamentos': (_) => [filamento('f1'), filamento('f2')],
      'GET /api/estoque': (_) => {
            'filamentos': [filamento('f1'), filamento('f2')],
            'carreteis': [
              {
                'id': 'c1',
                'filamento_id': 'f1',
                'saldo_g': 123456.7,
                'peso_inicial_g': 123456.7,
                'arquivado': false,
                'excluido': false,
                'aberto': true,
                'local': 'Prateleira de cima do armário da oficina',
                'filamento': filamento('f1'),
              }
            ],
            'insumos': [
              {'id': 's1', 'nome': 'Ímã de neodímio 10 × 3 mm para suportes magnéticos', 'categoria': 'insumo', 'saldo': 123456, 'baixo': true}
            ],
            'pecas': [
              {'modelo_id': 'm1', 'saldo': -1234}
            ],
          },
      'GET /api/pedidos': (_) => [for (final s in ['entregue', 'orcamento', 'produzindo', 'entregue']) pedido(s, s)],
      'GET /api/canais': (_) => [
            {'id': 'c1', 'nome': 'Direto', 'taxa_pct': 0, 'taxa_fixa': 0},
            {'id': 'c2', 'nome': 'Shopee com frete grátis e cupom', 'taxa_pct': 20, 'taxa_fixa': 4},
          ],
      'GET /api/clientes': (_) => [
            {'id': 'k1', 'nome': cliente}
          ],
      'GET /api/empresa/config': (_) =>
          {'eficiencia': 1.1, 'mao_obra_hora': 10, 'kwh': 0.656, 'reserva': 1.3, 'margens': [20, 30, 50]},
    });

/// Abas abrem dentro da casca (com a navegação); o resto, sozinho.
const abas = {
  'inicio': 0,
  'inicio_vazio': 0,
  'impressora': 1,
  'impressora_controle': 1,
  'impressora_arquivos': 1,
  'impressora_macros': 1,
  'impressora_console': 1,
  'impressora_historico': 1,
  'catalogo': 2,
  'estoque': 3,
  'vendas': 4,
};
final telas = <String, Widget Function()>{
  'modelo': () => const ModeloTela(id: 'm1'),
  'venda_rapida': () => const VendaRapidaTela(itensIniciais: [
        {'descricao': longo, 'preco_unitario': grande, 'modelo_id': 'm1'}
      ]),
  'confirmar': () => ConfirmarTela(impressao: Map<String, dynamic>.from(impressao)),
  'configuracoes': () => const ConfiguracoesTela(),
  'filamento_form': () => const FilamentoForm(),
  'carretel_form': () => const CarretelForm(),
  'modelo_form': () => ModeloForm(dados: modelo('m1')),
  'impressora_form': () => const ImpressoraForm(),
  'custos_form': () => const ConfigEmpresaForm(dados: {}),
  'canal_form': () => const CanalForm(dados: {'id': 'c2', 'nome': 'Shopee com frete grátis e cupom', 'taxa_pct': 20, 'taxa_fixa': 4}),
};

const larguras = [320.0, 360.0, 412.0, 600.0, 840.0, 1280.0];

/// Inter e os ícones de verdade: a medida do texto é a do aparelho e a captura fica legível.
Future<void> carregarFontes() async {
  Future<void> carregar(String familia, List<String> arquivos) async {
    final f = FontLoader(familia);
    for (final a in arquivos) {
      f.addFont(File(a).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await f.load();
  }

  await carregar('Inter', [for (final p in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fontes/Inter-$p.ttf']);
  final raiz = Platform.environment['FLUTTER_ROOT'];
  final icones = File('$raiz/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (raiz != null && icones.existsSync()) await carregar('MaterialIcons', [icones.path]);
}

void main() {
  setUpAll(carregarFontes);

  for (final nome in [...abas.keys, ...telas.keys]) {
    for (final largura in larguras) {
      for (final brilho in Brightness.values) {
        final tema = brilho == Brightness.dark ? 'escuro' : 'claro';
        testWidgets('$nome em $largura dp ($tema) não estoura', (tester) async {
          // O teste troca sombra por contorno preto; a captura mostra a sombra de verdade.
          if (autoUpdateGoldenFiles) debugDisableShadows = false;
          final amb = nome == 'inicio_vazio' ? Ambiente({}) : cheio(); // empresa nova: primeiros passos
          await amb.preparar();
          if (nome == 'configuracoes') {
            amb.online = false;
            await amb.fila.enviarOuGuardar(Operacao.nova('PUT', '/api/impressoes/p1/confirmar-com-um-caminho-longo', {}));
            amb.online = true;
          }
          await tamanhoTela(tester, largura, largura < 600 ? 1600 : 1000);
          tester.platformDispatcher.platformBrightnessTestValue = brilho;
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
          if (abas.containsKey(nome)) {
            await tester.pumpWidget(amb.app());
            await tester.pumpAndSettle();
            tester.state<CascaState>(find.byType(Casca)).irPara(abas[nome]!);
            if (nome.startsWith('impressora_')) {
              await tester.pumpAndSettle();
              final rotulo = {'controle': 'Controle', 'arquivos': 'Arquivos', 'macros': 'Macros', 'console': 'Console'};
              final secao = find.textContaining(rotulo[nome.substring(11)] ?? 'Histórico').first;
              await tester.ensureVisible(secao);
              await tester.pumpAndSettle();
              await tester.tap(secao);
            }
          } else {
            await tester.pumpWidget(amb.tela(telas[nome]!(), brilho: brilho));
          }
          await tester.pumpAndSettle();
          // Com --dart-define=DETALHE=true o erro não é capturado e o relatório mostra o widget culpado.
          if (!const bool.fromEnvironment('DETALHE')) expect(tester.takeException(), isNull);
          if (autoUpdateGoldenFiles && brilho == Brightness.light && (largura == 360 || largura == 1280)) {
            await expectLater(find.byType(MaterialApp), matchesGoldenFile('capturas/${nome}_${largura.toInt()}.png'));
          }
          debugDisableShadows = true;
        });
      }
    }
  }
}

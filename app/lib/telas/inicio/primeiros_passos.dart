import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../widgets/adaptativo.dart';
import '../../widgets/estado_tela.dart';
import '../casca.dart';
import '../catalogo/modelo_form.dart';
import '../estoque/carretel_form.dart';
import '../estoque/filamento_form.dart';
import '../impressoes/confirmar_tela.dart';
import '../mais/calculadora_tela.dart';
import '../mais/impressoras_tela.dart';
import '../vendas/venda_rapida_tela.dart';

/// Na ordem em que um depende do outro: o carretel é de um filamento, a venda é de um modelo...
final _passos = <(String, Widget Function())>[
  ('Cadastrar impressora', () => const ImpressoraForm()),
  ('Cadastrar filamento', () => const FilamentoForm()),
  ('Registrar um carretel', () => const CarretelForm()),
  ('Criar um modelo', () => const ModeloForm()),
  ('Fazer a primeira venda', () => const VendaRapidaTela()),
];

/// Quais passos já foram feitos, pelas listas (e cache) de sempre. null = todos feitos: fica guardado
/// no aparelho e as listas não são mais buscadas só para isso.
Future<List<bool>?> passosFeitos(BuildContext context, {required bool temImpressora}) async {
  final chave = 'primeiros_passos_ok:${context.read<ApiCliente>().empresaId}';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(chave) == true || !context.mounted) return null;
  final d = (await buscarVarios(context, {'estoque': '/api/estoque', 'modelos': '/api/modelos', 'pedidos': '/api/pedidos'}))
      .dados as Map;
  final estoque = mapa(d['estoque']);
  final feitos = [
    temImpressora,
    lista(estoque['filamentos']).isNotEmpty,
    lista(estoque['carreteis']).isNotEmpty,
    lista(d['modelos']).isNotEmpty,
    lista(d['pedidos']).isNotEmpty,
  ];
  if (!feitos.every((f) => f)) return feitos;
  await prefs.setBool(chave, true);
  return null;
}

class CartaoPrimeirosPassos extends StatelessWidget {
  const CartaoPrimeirosPassos({super.key, required this.feitos});
  final List<bool> feitos;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Primeiros passos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${feitos.where((f) => f).length} de ${feitos.length}',
                  style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
            ),
          ]),
          Text('Toque em cada passo para cadastrar. Este cartão some quando tudo estiver pronto.',
              style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
          for (var i = 0; i < _passos.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(feitos[i] ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: feitos[i] ? t.colorScheme.primary : t.colorScheme.outline),
              title: Text(_passos[i].$1,
                  style: feitos[i]
                      ? TextStyle(color: t.colorScheme.onSurfaceVariant, decoration: TextDecoration.lineThrough)
                      : null),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => abrirTela(context, _passos[i].$2()),
            ),
        ]),
      ),
    );
  }
}

/// Botões grandes do Início (os mesmos do "+").
class AcoesRapidas extends StatelessWidget {
  const AcoesRapidas({super.key, required this.colunas});
  final int colunas;

  @override
  Widget build(BuildContext context) {
    final acoes = <(String, IconData, Widget Function())>[
      ('Vender', Icons.point_of_sale, () => const VendaRapidaTela()),
      ('Lançar impressão', Icons.print, () => const ConfirmarTela()),
      ('Novo carretel', Icons.circle_outlined, () => const CarretelForm()),
      ('Orçar', Icons.calculate_outlined, () => const CalculadoraTela()),
    ];
    return GradeCartoes(colunas: colunas, children: [
      for (final (nome, icone, tela) in acoes)
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () => abrirTela(context, tela()),
          icon: Icon(icone),
          label: Text(nome, textAlign: TextAlign.center),
        ),
    ]);
  }
}

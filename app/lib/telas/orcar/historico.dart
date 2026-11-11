import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/estado_tela.dart';
import 'orcar_tela.dart';

// shortcut: o histórico fica só neste aparelho (não sincroniza celular × navegador); passar para o servidor
// quando outra pessoa precisar ver os mesmos orçamentos.
const _chave = 'orcamentos_v1';
const _limite = 50;

Future<List<Json>> lerHistorico() async {
  final prefs = await SharedPreferences.getInstance();
  try {
    return [for (final o in jsonDecode(prefs.getString(_chave) ?? '[]') as List) Map<String, dynamic>.from(o as Map)];
  } catch (_) {
    return []; // histórico ilegível não pode travar o orçamento
  }
}

Future<void> _gravar(List<Json> l) async =>
    (await SharedPreferences.getInstance()).setString(_chave, jsonEncode(l.take(_limite).toList()));

/// Guarda (ou atualiza, pelo id) no topo do histórico.
Future<void> salvarOrcamento(Json o) async {
  final l = await lerHistorico();
  l.removeWhere((x) => x['id'] == o['id']);
  await _gravar([o, ...l]);
}

Future<void> apagarOrcamento(String id) async => _gravar((await lerHistorico())..removeWhere((x) => x['id'] == id));

/// ["Vaso", "Suporte (2 un.)"]; peça sem nome vira "Peça N".
List<String> linhasItens(List itens) => [
      for (final (i, it) in itens.indexed)
        '${(it['nome'] as String? ?? '').isEmpty ? 'Peça ${i + 1}' : it['nome']}${num0(it['qtd']) > 1 ? ' (${num0(it['qtd']).toInt()} un.)' : ''}'
    ];

String resumoItens(List itens) => linhasItens(itens).join(', ');

/// Orçamentos já feitos neste aparelho. Tocar reabre; arrastar para o lado apaga.
class HistoricoOrcamentosTela extends StatefulWidget {
  const HistoricoOrcamentosTela({super.key});

  @override
  State<HistoricoOrcamentosTela> createState() => _HistoricoOrcamentosTelaState();
}

class _HistoricoOrcamentosTelaState extends State<HistoricoOrcamentosTela> {
  List<Json>? _lista;

  @override
  void initState() {
    super.initState();
    lerHistorico().then((l) => mounted ? setState(() => _lista = l) : null);
  }

  @override
  Widget build(BuildContext context) {
    final l = _lista;
    return Scaffold(
      appBar: AppBar(title: const Text('Orçamentos feitos')),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : l.isEmpty
              ? const EstadoVazio(
                  icone: Icons.history,
                  titulo: 'Nenhum orçamento ainda',
                  explicacao: 'Quando você enviar um orçamento por texto ou imagem, ele aparece aqui.')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: l.length,
                  separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                  itemBuilder: (context, i) {
                    final o = l[i];
                    return Dismissible(
                      key: ValueKey(o['id']),
                      background: Container(
                          color: vermelho, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline, color: Colors.white)),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) {
                        apagarOrcamento('${o['id']}');
                        setState(() => l.removeAt(i));
                      },
                      child: ListTile(
                        title: Text(resumoItens(lista(o['itens'])), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(lerData(o['quando']) == null ? '' : dataHora(lerData(o['quando'])!)),
                        trailing: Text(moeda(num0(o['preco'])),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, fontFeatures: tabular)),
                        onTap: () => Navigator.pushReplacement(
                            context, MaterialPageRoute(builder: (_) => OrcarTela(inicial: o))),
                      ),
                    );
                  },
                ),
    );
  }
}

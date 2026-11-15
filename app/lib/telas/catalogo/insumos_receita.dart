import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';

/// Insumo que vai junto com a peça (switch, argola, ímã, saquinho): do cadastro ou avulso.
/// Guarda nome e preço copiados, para o custo continuar certo sem internet ou se o cadastro sumir.
class LinhaInsumo {
  LinhaInsumo({this.id, this.nome = '', this.custo = 0, this.qtd = 1, this.embalagem = false});

  factory LinhaInsumo.deJson(Map j) => LinhaInsumo(
        id: j['insumo_id'] as String?,
        nome: '${j['nome'] ?? ''}',
        custo: num0(j['custo_unitario']),
        qtd: j['qtd'] == null ? 1 : num0(j['qtd']),
        embalagem: j['embalagem'] == true,
      );

  String? id;
  String nome;
  double custo, qtd;
  bool embalagem;

  double get total => custo * qtd;

  /// O cadastro manda no nome e no preço (é o que o servidor usa).
  void sincronizar(List cadastro) {
    for (final c in cadastro) {
      if (c is Map && c['id'] == id && id != null) {
        nome = '${c['nome']}';
        custo = num0(c['custo_unitario']);
        embalagem = c['categoria'] == 'embalagem';
      }
    }
  }

  Json get json => {'insumo_id': id, 'nome': nome, 'custo_unitario': custo, 'qtd': qtd, 'embalagem': embalagem};
}

/// Lista de insumos com quantidade, preço de cada e botão para adicionar (do estoque, novo ou avulso).
class EditorInsumos extends StatelessWidget {
  const EditorInsumos({super.key, required this.linhas, required this.cadastro, required this.aoMudar});

  final List<LinhaInsumo> linhas;
  final List cadastro;
  final VoidCallback aoMudar;

  Future<void> _adicionar(BuildContext context) async {
    final ja = {for (final l in linhas) l.id};
    final disponiveis = [for (final c in lista(cadastro)) if (c['excluido'] != true && !ja.contains(c['id'])) c];
    final escolha = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Novo insumo'),
              subtitle: const Text('Ex.: switch, argola de chaveiro, ímã'),
              onTap: () => Navigator.pop(c, 'novo'),
            ),
            if (disponiveis.isNotEmpty) const Divider(),
            for (final i in disponiveis)
              ListTile(
                leading: Icon(i['categoria'] == 'embalagem' ? Icons.redeem_outlined : Icons.inventory_2_outlined),
                title: Text('${i['nome']}'),
                trailing: Text('${moeda(num0(i['custo_unitario']))} / ${i['unidade'] ?? 'un'}',
                    style: const TextStyle(fontFeatures: tabular)),
                onTap: () => Navigator.pop(c, i),
              ),
          ]),
        ),
      ),
    );
    if (!context.mounted || escolha == null) return;
    final LinhaInsumo? nova;
    if (escolha is Map) {
      nova = LinhaInsumo(id: '${escolha['id']}')..sincronizar([escolha]);
    } else {
      nova = await editarInsumo(context, null);
    }
    if (nova == null) return;
    linhas.add(nova);
    aoMudar();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fraco = TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant, fontFeatures: tabular);
    for (final l in linhas) {
      l.sincronizar(cadastro);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, l) in linhas.indexed)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            // Do cadastro: preço e nome mudam no Estoque; avulso: edita aqui.
            onTap: l.id != null
                ? null
                : () async {
                    final editado = await editarInsumo(context, l);
                    if (editado != null) aoMudar();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
              child: Row(children: [
                Icon(l.embalagem ? Icons.redeem_outlined : Icons.inventory_2_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.nome.isEmpty ? 'Insumo' : l.nome,
                        key: Key('insumo$i'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${moeda(l.custo)} cada${l.id == null ? ' · avulso' : ''}', style: fraco),
                  ]),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Menos',
                  onPressed: l.qtd - 1 > 0
                      ? () {
                          l.qtd -= 1;
                          aoMudar();
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(numero(l.qtd), key: Key('insumo_qtd$i'), style: const TextStyle(fontFeatures: tabular)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Mais',
                  onPressed: () {
                    l.qtd += 1;
                    aoMudar();
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
                SizedBox(
                  width: 64,
                  child: Text(moeda(l.total), textAlign: TextAlign.right, style: const TextStyle(fontFeatures: tabular)),
                ),
                IconButton(
                  tooltip: 'Tirar',
                  onPressed: () {
                    linhas.removeAt(i);
                    aoMudar();
                  },
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('adicionar_insumo'),
          onPressed: () => _adicionar(context),
          icon: const Icon(Icons.add),
          label: const Text('Adicionar insumo'),
        ),
      ),
    ]);
  }
}

/// Novo insumo (ou edição de um avulso): nome, preço de cada e se é embalagem.
/// "Guardar no estoque" cria o cadastro (pela fila, funciona sem internet) para reusar em outros modelos.
Future<LinhaInsumo?> editarInsumo(BuildContext context, LinhaInsumo? atual) async {
  final nome = TextEditingController(text: atual?.nome);
  final custo = ctrlDinheiro(atual?.custo);
  var embalagem = atual?.embalagem ?? false;
  var guardar = atual == null;
  final chave = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, atualizar) => AlertDialog(
        title: Text(atual == null ? 'Novo insumo' : 'Editar insumo'),
        content: Form(
          key: chave,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CampoTexto(nome, 'Nome', key: const Key('insumo_nome'), obrigatorio: true, dica: 'Switch, argola...'),
              CampoDinheiro(custo, 'Preço de cada', key: const Key('insumo_custo')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('É embalagem'),
                value: embalagem,
                onChanged: (v) => atualizar(() => embalagem = v),
              ),
              if (atual == null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Guardar no estoque'),
                  subtitle: const Text('Para reusar em outros modelos'),
                  value: guardar,
                  onChanged: (v) => atualizar(() => guardar = v),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                if (chave.currentState!.validate()) Navigator.pop(c, true);
              },
              child: const Text('Pronto')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  final linha = atual ?? LinhaInsumo();
  linha
    ..nome = nome.text.trim().length > 80 ? nome.text.trim().substring(0, 80) : nome.text.trim()
    ..custo = lerNumero(custo.text) ?? 0
    ..embalagem = embalagem;
  if (guardar) {
    final id = novoId();
    final salvo = await salvar(context, 'PUT', '/api/insumos/$id', {
      'nome': linha.nome,
      'custo_unitario': linha.custo,
      'categoria': embalagem ? 'embalagem' : 'insumo',
      'unidade': 'un',
    }, feito: 'Insumo guardado no estoque');
    if (salvo) linha.id = id;
  }
  return linha;
}

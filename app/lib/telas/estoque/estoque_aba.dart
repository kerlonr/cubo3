import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../../widgets/seletores.dart';
import 'acoes_estoque.dart';
import 'carretel_form.dart';
import 'filamento_form.dart';
import 'insumo_form.dart';

/// Aba Estoque: Filamentos (por filamento, com carretéis), Insumos e Peças prontas.
class EstoqueAba extends StatefulWidget {
  const EstoqueAba({super.key});

  @override
  State<EstoqueAba> createState() => _EstoqueAbaState();
}

class _EstoqueAbaState extends State<EstoqueAba> {
  int _segmento = 0;
  int _versao = 0;

  void _recarregar() => setState(() => _versao++);

  Future<void> _abrir(Widget tela) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => tela));
    if (ok == true) _recarregar();
  }

  Future<void> _seRecarrega(Future<bool> acao) async {
    if (await acao) _recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estoque'), actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.add),
          tooltip: 'Cadastrar',
          onSelected: (i) => _abrir(const [CarretelForm(), FilamentoForm(), InsumoForm()][i]),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text('Novo carretel')),
            PopupMenuItem(value: 1, child: Text('Novo filamento')),
            PopupMenuItem(value: 2, child: Text('Novo insumo')),
          ],
        ),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          // Sem o ✓ do selecionado: com ele "Filamentos" quebrava em duas linhas no celular.
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final (i, r) in const ['Filamentos', 'Insumos', 'Peças'].indexed)
                ButtonSegment(value: i, label: Text(r, maxLines: 1, softWrap: false, overflow: TextOverflow.fade)),
            ],
            selected: {_segmento},
            onSelectionChanged: (s) => setState(() => _segmento = s.first),
          ),
        ),
        Expanded(
          child: EstadoTela<Map>(
            key: ValueKey(_versao),
            carregar: () => buscar(context, '/api/estoque'),
            construir: (context, e) => switch (_segmento) {
              0 => _filamentos(e),
              1 => _insumos(e),
              _ => _PecasLista(pecas: lista(e['pecas'])),
            },
          ),
        ),
      ]),
    );
  }

  Widget _lista(List<Widget> itens, EstadoVazio vazio) => itens.isEmpty
      ? ListView(children: [vazio])
      : Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              itemCount: itens.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => itens[i],
            ),
          ),
        );

  Widget _filamentos(Map e) {
    final carreteis = lista(e['carreteis']);
    return _lista([
      for (final f in lista(e['filamentos']))
        Card(
          child: ListTile(
            leading: BolinhaCor(corHex(f['cor_hex']), tamanho: 26),
            title: Text(nomeFilamento(f)),
            subtitle: Text('${carreteis.where((c) => c['filamento_id'] == f['id']).length} carretel(éis)'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (f['baixo'] == true) ...[const ChipRepor(), const SizedBox(width: 8)],
              Text(gramas(num0(f['total_g'])), style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600)),
            ]),
            onTap: () => _abrir(CarreteisTela(filamento: f)),
          ),
        ),
    ],
        EstadoVazio(
          icone: Icons.palette_outlined,
          titulo: 'Nenhum filamento ainda',
          explicacao: 'Filamento é o tipo que você compra (marca, material e cor) com o preço por kg. '
              'Depois registre cada carretel para o estoque descontar os gramas sozinho.',
          acao: 'Cadastrar filamento',
          aoTocar: () => _abrir(const FilamentoForm()),
        ));
  }

  Widget _insumos(Map e) => _lista([
        for (final i in lista(e['insumos']))
          Card(
            child: ListTile(
              title: Text(i['nome'] as String),
              subtitle: Text(i['categoria'] == 'embalagem' ? 'Embalagem' : 'Insumo'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (i['baixo'] == true) ...[const ChipRepor(), const SizedBox(width: 8)],
                Text(numero(num0(i['saldo'])), style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600)),
              ]),
              onTap: () => showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (c) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                      leading: const Icon(Icons.shopping_cart_outlined),
                      title: const Text('Registrar compra'),
                      onTap: () {
                        Navigator.pop(c);
                        _seRecarrega(comprarInsumo(context, i));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Ajustar estoque'),
                      onTap: () {
                        Navigator.pop(c);
                        _seRecarrega(ajustar(context, 'insumo', i['id'] as String));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Editar'),
                      onTap: () async {
                        Navigator.pop(c);
                        try {
                          final dados = mapa((await buscar(context, '/api/insumos/${i['id']}')).dados);
                          if (mounted) _abrir(InsumoForm(dados: dados));
                        } catch (erro) {
                          if (mounted) avisarErro(context, erro);
                        }
                      },
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ],
          EstadoVazio(
            icone: Icons.inventory_2_outlined,
            titulo: 'Nenhum insumo',
            explicacao: 'Insumos são ímãs, parafusos, caixas e etiquetas que vão junto com a peça e entram no custo.',
            acao: 'Cadastrar insumo',
            aoTocar: () => _abrir(const InsumoForm()),
          ));
}

class _PecasLista extends StatelessWidget {
  const _PecasLista({required this.pecas});
  final List<Json> pecas;

  @override
  Widget build(BuildContext context) {
    return EstadoTela<List>(
      carregar: () => buscar(context, '/api/modelos', query: {'incluir_excluidos': 'true'}),
      construir: (context, modelos) {
        final nomes = {for (final m in lista(modelos)) m['id']: m};
        final itens = [for (final p in pecas) if (num0(p['saldo']) != 0) p];
        if (itens.isEmpty) {
          return ListView(children: const [
            EstadoVazio(
              icone: Icons.view_in_ar_outlined,
              titulo: 'Nenhuma peça pronta',
              explicacao: 'Ao confirmar uma impressão com a finalidade "Estoque", as peças entram aqui e saem quando '
                  'você vende.',
            ),
          ]);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
          for (final p in itens)
            Card(
              child: ListTile(
                title: Text(_nomeModelo(nomes[p['modelo_id']])),
                trailing: Text(numero(num0(p['saldo'])),
                    style: TextStyle(
                        fontFeatures: tabular,
                        fontWeight: FontWeight.w600,
                        color: num0(p['saldo']) < 0 ? vermelho : null)),
                onLongPress: () => ajustar(context, 'peca', p['modelo_id'] as String),
              ),
            ),
        ]);
      },
    );
  }

  String _nomeModelo(Json? m) =>
      m == null ? 'Modelo' : (m['excluido'] == true ? '${m['nome']} (excluído)' : m['nome'] as String);
}

/// Carretéis de um filamento: saldo, local, aberto; pesar, ajustar, abrir/arquivar.
class CarreteisTela extends StatefulWidget {
  const CarreteisTela({super.key, required this.filamento});
  final Json filamento;

  @override
  State<CarreteisTela> createState() => _CarreteisTelaState();
}

class _CarreteisTelaState extends State<CarreteisTela> {
  int _versao = 0;
  bool _mudou = false;

  void _recarregar(bool ok) {
    if (!ok) return;
    _mudou = true;
    setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filamento;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (pop, _) {
        if (!pop) Navigator.pop(context, _mudou);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(nomeFilamento(f)), actions: [
          IconButton(
            tooltip: 'Editar filamento',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              try {
                final dados = mapa((await buscar(context, '/api/filamentos/${f['id']}')).dados);
                if (!context.mounted) return;
                _recarregar(await Navigator.push<bool>(
                        context, MaterialPageRoute(builder: (_) => FilamentoForm(dados: dados))) ==
                    true);
              } catch (e) {
                if (context.mounted) avisarErro(context, e);
              }
            },
          ),
          IconButton(
            tooltip: 'Novo carretel',
            icon: const Icon(Icons.add),
            onPressed: () async => _recarregar(await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => CarretelForm(filamentoId: f['id'] as String))) ==
                true),
          ),
        ]),
        body: EstadoTela<Map>(
          key: ValueKey(_versao),
          carregar: () => buscar(context, '/api/estoque'),
          construir: (context, e) {
            final carreteis = [for (final c in lista(e['carreteis'])) if (c['filamento_id'] == f['id']) c];
            if (carreteis.isEmpty) {
              return ListView(children: [
                EstadoVazio(
                  icone: Icons.circle_outlined,
                  titulo: 'Nenhum carretel ativo',
                  explicacao: 'Registre cada carretel que comprar: o app desconta os gramas de cada impressão e avisa '
                      'quando estiver acabando.',
                  acao: 'Registrar carretel',
                  aoTocar: () async => _recarregar(await Navigator.push<bool>(context,
                          MaterialPageRoute(builder: (_) => CarretelForm(filamentoId: f['id'] as String))) ==
                      true),
                ),
              ]);
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final c in carreteis)
                Card(
                  child: ListTile(
                    title: Text(gramas(num0(c['saldo_g'])),
                        style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600, fontSize: 18)),
                    subtitle: Text([
                      'de ${gramas(num0(c['peso_inicial_g']))}',
                      if (c['local'] != null) '${c['local']}',
                      c['aberto'] == true ? 'aberto' : 'fechado',
                      'R\$/kg ${moeda(num0(c['preco_kg_real'])).replaceFirst('R\$ ', '')}',
                    ].join(' · ')),
                    trailing: PopupMenuButton<String>(
                      onSelected: (acao) async {
                        final id = c['id'] as String;
                        switch (acao) {
                          case 'pesar':
                            _recarregar(await pesarCarretel(context, c));
                          case 'ajustar':
                            _recarregar(await ajustar(context, 'carretel', id, sufixo: 'g'));
                          case 'aberto':
                            _recarregar(await salvar(context, 'PUT', '/api/carreteis/$id', {'aberto': c['aberto'] != true},
                                versaoBase: c['atualizado_em'] as String?));
                          case 'arquivar':
                            if (await confirmar(context, 'Arquivar carretel?', 'Ele sai do estoque e dos seletores.',
                                    sim: 'Arquivar') &&
                                context.mounted) {
                              _recarregar(await salvar(context, 'PUT', '/api/carreteis/$id', {'arquivado': true},
                                versaoBase: c['atualizado_em'] as String?));
                            }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'pesar', child: Text('Pesar na balança')),
                        const PopupMenuItem(value: 'ajustar', child: Text('Ajustar saldo')),
                        PopupMenuItem(value: 'aberto', child: Text(c['aberto'] == true ? 'Marcar fechado' : 'Marcar aberto')),
                        const PopupMenuItem(value: 'arquivar', child: Text('Arquivar (acabou)')),
                      ],
                    ),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

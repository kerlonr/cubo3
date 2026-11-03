import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/controle.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../tema.dart';
import '../../widgets/estado_tela.dart';
import '../impressoes/confirmar_tela.dart';
import '../mais/impressoras_tela.dart';
import 'controle.dart';
import 'historico.dart';
import 'painel.dart';

/// Aba Impressora (estilo Mobileraker): Painel, Controle (só dono), Arquivos, Macros, Console e Histórico.
/// Com mais de uma impressora com Klipper, escolhe no topo. Parada de emergência sempre no alto (dono).
class ImpressoraAba extends StatefulWidget {
  const ImpressoraAba({super.key, this.aoContar, this.ativa = true});

  /// false enquanto outra aba está na frente (a câmera só liga com a aba visível).
  final bool ativa;

  /// Avisa a casca quantas estão a confirmar (selo no ícone da aba).
  final ValueChanged<int>? aoContar;

  @override
  State<ImpressoraAba> createState() => ImpressoraAbaState();
}

class ImpressoraAbaState extends State<ImpressoraAba> {
  int _versao = 0;
  String? _impressora;
  Json? _atual;

  void recarregar() => setState(() => _versao++);

  Future<void> _abrir(Widget tela) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    recarregar();
  }

  Future<void> _emergencia(Json imp) async {
    if (!await confirmar(
        context,
        'Parada de emergência?',
        'Desliga motores e aquecedores na hora e interrompe a impressão. Depois use "Reiniciar firmware" '
            '(em Controle) antes de usar a impressora de novo.',
        sim: 'Parar agora',
        nao: 'Voltar',
        cor: vermelho)) {
      return;
    }
    if (!mounted) return;
    try {
      await comandar(context.read<ApiCliente>(), '${imp['id']}', 'emergencia');
      if (mounted) avisar(context, 'Parada de emergência enviada');
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dono = context.watch<Sessao>().dono;
    return Scaffold(
      appBar: AppBar(title: const Text('Impressora'), actions: [
        if (dono && _atual != null)
          IconButton(
            tooltip: 'Parada de emergência',
            color: vermelho,
            icon: const Icon(Icons.dangerous_outlined),
            onPressed: () => _emergencia(_atual!),
          ),
        IconButton(tooltip: 'Impressoras', icon: const Icon(Icons.settings_outlined), onPressed: () => _abrir(const ImpressorasTela())),
        IconButton(tooltip: 'Lançar impressão', icon: const Icon(Icons.add), onPressed: () => _abrir(const ConfirmarTela())),
      ]),
      body: EstadoTela<Map>(
        key: ValueKey(_versao),
        carregar: () async {
          final r = await buscarVarios(context, {'impressoes': '/api/impressoes', 'impressoras': '/api/impressoras'});
          final n = lista((r.dados as Map)['impressoes']).where((i) => i['status'] == 'a_confirmar').length;
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.aoContar?.call(n));
          return r;
        },
        construir: (context, d) => _corpo(d, dono),
      ),
    );
  }

  Widget _corpo(Map d, bool dono) {
    final impressoras = [for (final i in lista(d['impressoras'])) if ((i['moonraker_url'] ?? '') != '') i];
    final impressoes = lista(d['impressoes']);
    final aConfirmar = impressoes.where((i) => i['status'] == 'a_confirmar').length;
    final atual = impressoras.where((i) => i['id'] == _impressora).firstOrNull ?? impressoras.firstOrNull;
    if (atual?['id'] != _atual?['id']) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _atual = atual); // botão de emergência no AppBar
      });
    }
    if (atual == null) {
      // Sem Klipper: só o histórico, com o convite para cadastrar.
      return HistoricoImpressoes(
        impressoes: impressoes,
        abrir: _abrir,
        topo: EstadoVazio(
          icone: Icons.print_outlined,
          titulo: lista(d['impressoras']).isEmpty ? 'Nenhuma impressora' : 'Nenhuma impressora com Klipper',
          explicacao: 'Cadastre o endereço do Klipper (Moonraker) da impressora para ver aqui a câmera, o progresso, '
              'os controles, os arquivos e o console.',
          acao: 'Configurar impressora',
          aoTocar: () => _abrir(const ImpressorasTela()),
        ),
      );
    }
    final id = '${atual['id']}';
    final secoes = <(String, IconData, Widget Function(BuildContext))>[
      (
        'Painel',
        Icons.speed,
        (c) => PainelSecao(
            impressora: atual,
            aConfirmar: aConfirmar,
            comCamera: widget.ativa,
            verHistorico: () => DefaultTabController.of(c).animateTo(dono ? 2 : 1)),
      ),
      if (dono) ('Controle', Icons.open_with, (_) => ControleImpressora(key: ValueKey('c$id'), impressora: atual)),
      (
        aConfirmar > 0 ? 'Histórico ($aConfirmar)' : 'Histórico',
        Icons.history,
        (_) => HistoricoImpressoes(impressoes: impressoes, abrir: _abrir, impressora: atual),
      ),
    ];
    return DefaultTabController(
      key: ValueKey('${secoes.length}'),
      length: secoes.length,
      child: Column(children: [
        if (impressoras.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(children: [
              for (final i in impressoras)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text('${i['nome']}', overflow: TextOverflow.ellipsis),
                    ),
                    selected: i == atual,
                    onSelected: (_) => setState(() => _impressora = i['id'] as String),
                  ),
                ),
            ]),
          ),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final s in secoes) Tab(icon: Icon(s.$2, size: 20), text: s.$1, height: 56)],
        ),
        Expanded(
          child: TabBarView(
            // Sem arrastar de lado: no Controle o gesto seria confundido com os botões e controles deslizantes.
            physics: const NeverScrollableScrollPhysics(),
            children: [for (final s in secoes) Builder(builder: s.$3)],
          ),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';

import '../api/modelos.dart';
import '../util/formatos.dart';
import 'cartoes.dart';

/// "Voolt PLA Branco" a partir do resumo de filamento do servidor.
String nomeFilamento(Map? f) {
  if (f == null) return 'Filamento';
  final nome = [f['marca'], f['material'], f['cor_nome']].where((p) => p != null && '$p'.isNotEmpty).join(' ');
  return f['excluido'] == true ? '$nome (excluído)' : nome;
}

/// Cadastros que ainda podem ser escolhidos (a lista do custo inclui os excluídos).
List<Json> ativos(Object? l) => [for (final f in lista(l)) if (f['excluido'] != true) f];

/// Escolha de filamento mostrando a cor (bolinha) e o preço por kg; [comAvulso] acrescenta "Preço avulso" (null).
class SeletorFilamento extends StatelessWidget {
  const SeletorFilamento({
    super.key,
    required this.filamentos,
    required this.valor,
    required this.aoMudar,
    this.rotulo = 'Filamento',
    this.comAvulso = true,
  });

  final List filamentos;
  final String? valor;
  final ValueChanged<String?> aoMudar;
  final String rotulo;
  final bool comAvulso;

  @override
  Widget build(BuildContext context) {
    final ativos = [for (final f in filamentos) if (f is Map && f['excluido'] != true) f];
    final fraco = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return DropdownButtonFormField<String?>(
      key: ValueKey('$rotulo$valor'),
      initialValue: ativos.any((f) => f['id'] == valor) ? valor : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: rotulo),
      items: [
        for (final f in ativos)
          DropdownMenuItem<String?>(
            value: f['id'] as String,
            child: Row(children: [
              BolinhaCor(corHex(f['cor_hex']), tamanho: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(nomeFilamento(f), overflow: TextOverflow.ellipsis)),
              if (f['preco_kg'] != null) Text('${moeda(num0(f['preco_kg']))}/kg', style: fraco),
            ]),
          ),
        if (comAvulso)
          const DropdownMenuItem<String?>(
            value: null,
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Preço avulso')),
            ]),
          ),
      ],
      onChanged: aoMudar,
    );
  }
}

/// Carretéis que podem ser usados agora (sem excluídos/arquivados), com os que combinam
/// com a cor (peso 2) e o material (peso 1) pedidos primeiro.
List<Json> ordenarCarreteis(List<Json> carreteis, {String? material, String? cor}) {
  final ativos = [
    for (final c in carreteis)
      if (c['excluido'] != true && c['arquivado'] != true) c
  ];
  int pontos(Json c) {
    final f = mapa(c['filamento']);
    var p = 0;
    if (cor != null && '${f['cor_hex']}'.toLowerCase() == cor.toLowerCase()) p += 2;
    if (material != null && '${f['material']}'.toLowerCase() == material.toLowerCase()) p += 1;
    return p;
  }

  final indices = List.generate(ativos.length, (i) => i)
    ..sort((a, b) {
      final d = pontos(ativos[b]) - pontos(ativos[a]);
      return d != 0 ? d : a - b; // empate: mantém a ordem do servidor
    });
  return [for (final i in indices) ativos[i]];
}

class SeletorCarretel extends StatelessWidget {
  const SeletorCarretel({
    super.key,
    required this.carreteis,
    required this.valor,
    required this.aoMudar,
    this.filtroMaterial,
    this.filtroCor,
    this.rotulo = 'Carretel',
  });

  final List<Json> carreteis;
  final String? valor;
  final ValueChanged<String?> aoMudar;
  final String? filtroMaterial;
  final String? filtroCor;
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final lista = ordenarCarreteis(carreteis, material: filtroMaterial, cor: filtroCor);
    return DropdownButtonFormField<String>(
      initialValue: lista.any((c) => c['id'] == valor) ? valor : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: rotulo),
      hint: Text(lista.isEmpty ? 'Nenhum carretel no estoque' : 'Escolha o carretel'),
      items: [
        for (final c in lista)
          DropdownMenuItem(
            value: c['id'] as String,
            child: Row(children: [
              BolinhaCor(corHex(mapa(c['filamento'])['cor_hex']), tamanho: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${nomeFilamento(mapa(c['filamento']))} · ${gramas(num0(c['saldo_g']))}',
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
      ],
      onChanged: aoMudar,
    );
  }
}

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

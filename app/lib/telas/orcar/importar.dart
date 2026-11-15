import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api/modelos.dart';
import '../../dominio/orcamento.dart';
import '../../util/formatos.dart';
import '../../widgets/estado_tela.dart';
import '../impressora/arquivos.dart' show resumoArquivo;

/// Item vindo de um arquivo fatiado (do aparelho ou da impressora): {nome, gramas, tempo, qtd}.
Json itemDeArquivo(String nomeArquivo, num? gramasLidos, num? segundos) => {
      'nome': nomeArquivo.replaceAll(RegExp(r'(\.gcode)?(\.3mf)?$|\.gcode$', caseSensitive: false), ''),
      'gramas': gramasLidos == null ? '' : paraCampo(gramasLidos.toDouble()),
      'tempo': segundos == null ? '' : duracao(segundos),
      'qtd': 1,
    };

/// Escolhe um G-code/3MF fatiado no aparelho e lê gramas e tempo. null se cancelou ou não tinha dados (avisa).
Future<Json?> itemDoAparelho(BuildContext context) async {
  final escolhidos = await FilePicker.pickFiles();
  if (escolhidos.isEmpty || !context.mounted) return null;
  final f = escolhidos.first;
  final lido = lerArquivoFatiado(f.name, await f.readAsBytes());
  if (!context.mounted) return null;
  if (!lido.temDados) {
    avisar(context, 'Esse arquivo não tem gramas nem tempo. No Bambu Studio, fatie e exporte o G-code ou o 3MF fatiado.');
    return null;
  }
  return itemDeArquivo(f.name, lido.gramas, lido.segundos);
}

/// Lista os arquivos da impressora (metadados do Moonraker) e devolve o escolhido como item.
Future<Json?> itemDaImpressora(BuildContext context, Map impressora) async {
  final arquivo = await showModalBottomSheet<Json>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SizedBox(
      height: MediaQuery.sizeOf(c).height * 0.7,
      child: EstadoTela<List>(
        carregar: () => buscar(c, '/api/impressoras/${impressora['id']}/arquivos'),
        vazio: (l) => l.isEmpty,
        estadoVazio: const EstadoVazio(
            icone: Icons.folder_off_outlined,
            titulo: 'Nenhum arquivo na impressora',
            explicacao: 'Envie o G-code fatiado para a impressora e tente de novo.'),
        construir: (c, l) => ListView(children: [
          for (final a in lista(l))
            ListTile(
              title: Text('${a['nome']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(resumoArquivo(a)),
              onTap: () => Navigator.pop(c, a),
            ),
        ]),
      ),
    ),
  );
  if (arquivo == null) return null;
  return itemDeArquivo('${arquivo['nome']}', arquivo['gramas'] as num?, arquivo['tempo_estimado_s'] as num?);
}

/// Impressoras com Klipper (as que têm arquivos para listar).
List<Json> impressorasComKlipper(List impressoras) => [
      for (final i in lista(impressoras))
        if (i['excluido'] != true && '${i['moonraker_url'] ?? ''}'.isNotEmpty) i
    ];

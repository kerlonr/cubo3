import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../api/api.dart';

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

/// Arquivos fatiados anexados a um modelo (G-code ou 3MF), de onde dá para ler gramas e tempo.
List<Json> fatiadosDoModelo(Map modelo) =>
    [for (final a in lista(modelo['arquivos'])) if (a['tipo'] == 'gcode' || a['tipo'] == '3mf') a];

/// Escolhe um arquivo já anexado ao modelo, baixa e lê gramas e tempo (sem pedir o arquivo de novo).
Future<Json?> itemDosArquivosDoModelo(BuildContext context, List<Json> arquivos) async {
  final a = arquivos.length == 1
      ? arquivos.single
      : await showModalBottomSheet<Json>(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
              for (final a in arquivos)
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text('${a['nome_original']}', overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(c, a),
                ),
            ]),
          ),
        );
  if (a == null || !context.mounted) return null;
  final api = context.read<ApiCliente>();
  try {
    final link = mapa(await api.post('/api/arquivos/${a['id']}/link'));
    final r = await http.get(api.url('${link['url']}'));
    if (r.statusCode != 200) throw ErroApi(r.statusCode, 'Não deu para baixar ${a['nome_original']}');
    final lido = lerArquivoFatiado('${a['nome_original']}', r.bodyBytes);
    if (!context.mounted) return null;
    if (!lido.temDados) {
      avisar(context, '${a['nome_original']} não tem gramas nem tempo (precisa ser o arquivo já fatiado).');
      return null;
    }
    return itemDeArquivo('${a['nome_original']}', lido.gramas, lido.segundos);
  } catch (e) {
    if (context.mounted) avisarErro(context, e);
    return null;
  }
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

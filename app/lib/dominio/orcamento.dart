/// Regras do orçamento rápido: arredondamento de 5 em 5, soma do kit e leitura de arquivo fatiado.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../util/formatos.dart';
import 'custos.dart';

/// Lucro que o Kerlon quer sempre: 50% do preço.
const margemAlvo = 50.0;

/// Múltiplo de 5 mais próximo, nunca abaixo de R$ 5.
double arredondar5(num v) => math.max(5, (v / 5).round() * 5).toDouble();

/// Múltiplo de 5 logo acima (não perde margem). O 1e-9 evita subir um valor que já é múltiplo.
double arredondar5Cima(num v) => math.max(5, (v / 5 - 1e-9).ceil() * 5).toDouble();

class PrecoSugerido {
  const PrecoSugerido(this.margem, this.custo, this.exato, this.preco);
  final double margem, custo, exato, preco;
  double get lucro => arred2(preco - custo);
  double get lucroPct => preco <= 0 ? 0 : lucro / preco * 100;
}

/// O preço grande da tela: margem de 50%, arredondado para cima.
PrecoSugerido precoDestaque(double custo) {
  final exato = precoComMargem(custo, margemAlvo);
  return PrecoSugerido(margemAlvo, custo, exato, arredondar5Cima(exato));
}

/// As margens do cadastro da empresa, cada uma no múltiplo de 5 mais próximo.
List<PrecoSugerido> precosPorMargem(double custo, List<double> margens) => [
      for (final m in margens)
        PrecoSugerido(m, custo, precoComMargem(custo, m), arredondar5(precoComMargem(custo, m))),
    ];

/// Custo do kit: cada peça vezes a quantidade, mais embalagem/envio uma vez só.
Custo somarCustos(List<(Custo, int)> itens, {double extra = 0}) {
  double s(double Function(Custo) f) => itens.fold(0.0, (t, i) => t + f(i.$1) * i.$2);
  return Custo(arred2(s((c) => c.material)), arred2(s((c) => c.maoObra)), arred2(s((c) => c.maquina)),
      arred2(s((c) => c.insumos)), arred2(s((c) => c.embalagem) + extra), arred2(s((c) => c.total) + extra));
}

/// "3", "2,5", "2h30", "2:15", "1h 45m", "45min" → horas.
double? lerHoras(String texto) {
  final t = texto.trim().toLowerCase().replaceAll(',', '.');
  final min = RegExp(r'^(\d+(?:\.\d+)?)\s*min$').firstMatch(t);
  if (min != null) return double.parse(min[1]!) / 60;
  final hm = RegExp(r'^(\d+)\s*(?:h|:)\s*(\d+)?\s*(?:m|min)?$').firstMatch(t);
  if (hm != null) return int.parse(hm[1]!) + int.parse(hm[2] ?? '0') / 60;
  final h = RegExp(r'^(\d+(?:\.\d+)?)\s*h?$').firstMatch(t);
  return h == null ? null : double.parse(h[1]!);
}

/// Gramas e tempo lidos de um arquivo já fatiado. null quando o arquivo não informa.
class Fatiado {
  const Fatiado(this.gramas, this.segundos);
  final double? gramas, segundos;
  bool get temDados => gramas != null || segundos != null;
}

/// "1d 2h 3m 4s" → segundos.
double? _duracao(String s) {
  var total = 0.0;
  var achou = false;
  for (final m in RegExp(r'(\d+(?:\.\d+)?)\s*([dhms])').allMatches(s)) {
    achou = true;
    total += double.parse(m[1]!) * const {'d': 86400, 'h': 3600, 'm': 60, 's': 1}[m[2]]!;
  }
  return achou ? total : null;
}

/// Bambu Studio e Orca põem os dados no cabeçalho; PrusaSlicer no fim; Cura só o tempo (`;TIME:`).
Fatiado lerGcode(String g) {
  double? gramas;
  final peso = RegExp(r'^;\s*(?:total filament weight \[g\]\s*:|total filament used \[g\]\s*=|filament used \[g\]\s*=)\s*([\d., ]+)$',
          multiLine: true, caseSensitive: false)
      .firstMatch(g);
  if (peso != null) {
    final partes = peso[1]!.split(',').map((p) => double.tryParse(p.trim())).whereType<double>();
    if (partes.isNotEmpty) gramas = arred2(partes.reduce((a, b) => a + b));
  }
  double? segundos;
  final tempo = RegExp(r'^;.*?(?:total estimated time:|estimated printing time \(normal mode\)\s*=)\s*([0-9dhms ]+)',
          multiLine: true, caseSensitive: false)
      .firstMatch(g);
  if (tempo != null) segundos = _duracao(tempo[1]!);
  final cura = RegExp(r'^;TIME:(\d+)', multiLine: true).firstMatch(g);
  segundos ??= cura == null ? null : double.parse(cura[1]!);
  return Fatiado(gramas, segundos);
}

Fatiado _ler3mf(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final info = zip.findFile('Metadata/slice_info.config');
  if (info != null) {
    final xml = utf8.decode(info.content, allowMalformed: true);
    double soma(String chave) => RegExp('key="$chave"\\s+value="([\\d.]+)"')
        .allMatches(xml)
        .fold(0.0, (t, m) => t + double.parse(m[1]!));
    final g = soma('weight'), s = soma('prediction');
    if (g > 0 || s > 0) return Fatiado(g > 0 ? arred2(g) : null, s > 0 ? s : null);
  }
  for (final f in zip.files) {
    if (f.name.toLowerCase().endsWith('.gcode')) return lerGcode(utf8.decode(f.content, allowMalformed: true));
  }
  return const Fatiado(null, null);
}

/// .gcode ou .3mf (.gcode.3mf) fatiado. Do G-code só lê o começo e o fim: é onde os fatiadores escrevem.
Fatiado lerArquivoFatiado(String nome, Uint8List bytes) {
  try {
    if (nome.toLowerCase().endsWith('.3mf')) return _ler3mf(bytes);
    const pedaco = 256 * 1024;
    final texto = bytes.length <= 2 * pedaco
        ? utf8.decode(bytes, allowMalformed: true)
        : '${utf8.decode(bytes.sublist(0, pedaco), allowMalformed: true)}\n'
            '${utf8.decode(bytes.sublist(bytes.length - pedaco), allowMalformed: true)}';
    return lerGcode(texto);
  } catch (_) {
    return const Fatiado(null, null); // arquivo corrompido ou que não é zip: o app avisa que não achou os dados
  }
}

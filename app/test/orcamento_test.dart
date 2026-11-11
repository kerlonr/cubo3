import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cubo3/dominio/custos.dart';
import 'package:cubo3/dominio/orcamento.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arredonda ao múltiplo de 5 mais próximo, nunca abaixo de R\$ 5', () {
    expect([7.9, 9.03, 12.4, 12.5, 41, 43, 0.5].map(arredondar5), [10, 10, 10, 15, 40, 45, 5]);
  });

  test('preço em destaque garante 50% de lucro subindo até o múltiplo de 5', () {
    final p = precoDestaque(6.32); // 12,64 exato
    expect(p.exato, 12.64);
    expect(p.preco, 15);
    expect(p.lucro, 8.68);
    expect(p.lucroPct, greaterThanOrEqualTo(50));
    expect(precoDestaque(10).preco, 20, reason: 'exato 20 não sobe');
  });

  test('preços pelas margens do cadastro usam o mais próximo', () {
    expect(precosPorMargem(6.32, [20, 30, 50]).map((p) => p.preco), [10, 10, 15]);
  });

  test('soma o custo do kit por quantidade e põe envio na embalagem', () {
    const a = Custo(1, 2, 3, 0, 0, 6);
    const b = Custo(0.5, 0, 1, 0, 0.5, 2);
    final c = somarCustos([(a, 2), (b, 1)], extra: 4);
    expect([c.material, c.maoObra, c.maquina, c.embalagem, c.total], [2.5, 4, 7, 4.5, 18]);
  });

  test('lê o tempo digitado de vários jeitos', () {
    expect(lerHoras('3'), 3);
    expect(lerHoras('2,5'), 2.5);
    expect(lerHoras('2h30'), 2.5);
    expect(lerHoras('2:15'), 2.25);
    expect(lerHoras('1h 45m'), 1.75);
    expect(lerHoras('45min'), 0.75);
    expect(lerHoras(''), isNull);
    expect(lerHoras('abc'), isNull);
  });

  test('G-code do Bambu Studio / Orca: peso e tempo total no cabeçalho', () {
    const g = '; HEADER_BLOCK_START\n; BambuStudio 02.00.00.00\n; model printing time: 1h 2m 3s; total estimated time: 1h 10m 30s\n'
        '; total layer number: 120\n; total filament weight [g] : 23.45\n; HEADER_BLOCK_END\nG28\n';
    final f = lerArquivoFatiado('peca.gcode', Uint8List.fromList(utf8.encode(g)));
    expect(f.gramas, 23.45);
    expect(f.segundos, 4230);
  });

  test('G-code do PrusaSlicer (dados no fim) e do Cura (só tempo)', () {
    final prusa = 'G28\n${'G1 X1\n' * 120000}; filament used [g] = 10.5, 2.0\n; estimated printing time (normal mode) = 1d 2h 3m 4s\n';
    final f = lerArquivoFatiado('p.gcode', Uint8List.fromList(utf8.encode(prusa)));
    expect(f.gramas, 12.5);
    expect(f.segundos, 93784);
    final cura = lerArquivoFatiado('c.gcode', Uint8List.fromList(utf8.encode(';FLAVOR:Marlin\n;TIME:3600\n;Filament used: 1.2m\n')));
    expect(cura.gramas, isNull);
    expect(cura.segundos, 3600);
  });

  test('3MF fatiado soma peso e tempo de todas as placas; 3MF sem fatiar não tem dados', () {
    const info = '<config><plate><metadata key="index" value="1"/><metadata key="prediction" value="3600"/>'
        '<metadata key="weight" value="20.10"/></plate><plate><metadata key="prediction" value="1800"/>'
        '<metadata key="weight" value="5.00"/></plate></config>';
    final zip = Archive()..addFile(ArchiveFile.string('Metadata/slice_info.config', info));
    final f = lerArquivoFatiado('kit.gcode.3mf', Uint8List.fromList(ZipEncoder().encode(zip)));
    expect(f.gramas, 25.1);
    expect(f.segundos, 5400);

    final cru = Archive()..addFile(ArchiveFile.string('3D/3dmodel.model', '<model/>'));
    final vazio = lerArquivoFatiado('modelo.3mf', Uint8List.fromList(ZipEncoder().encode(cru)));
    expect(vazio.temDados, isFalse);
  });

  test('arquivo que não é zip nem texto não quebra', () {
    expect(lerArquivoFatiado('x.3mf', Uint8List.fromList([1, 2, 3])).temDados, isFalse);
  });
}

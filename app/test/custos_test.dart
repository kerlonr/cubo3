import 'package:cubo3/dominio/custos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const emp = ParamEmpresa();
  const imp = ParamImpressora();

  test('custo por hora da impressora da planilha', () {
    expect(custoHoraImpressora(imp, emp).toStringAsFixed(4), '0.3414');
  });

  test('peça da planilha: 33 g de PLA a R\$ 100/kg, 3 h, 10 min', () {
    final c = calcularCusto(Receita([const ItemFilamento(33, 100)], 3, 10), imp, emp);
    expect([c.material, c.maoObra, c.maquina, c.total], [3.63, 1.67, 1.02, 6.32]);
    expect([for (final m in [20, 30, 50]) precoComMargem(c.total, m)], [7.90, 9.03, 12.64]);
  });

  test('sem eficiência, com insumos, embalagem e envio', () {
    final c = calcularCusto(
        Receita([const ItemFilamento(33, 100)], 0, 0,
            insumos: [const ItemCusto(4, 0.5)],
            embalagem: [const ItemCusto(1, 1.2)],
            custoEnvio: 5,
            aplicarEficiencia: false),
        imp,
        emp);
    expect([c.material, c.insumos, c.embalagem, c.total], [3.30, 2.00, 6.20, 11.50]);
  });

  test('canal de venda e lucro', () {
    expect(precoComCanal(6.32, 30, 20, 4), 20.64);
    expect(lucroVenda(12.64, 6.32, 20, 4), -0.21);
    expect(precoComCanal(1, 60, 40, 0), isNull);
  });

  test('parâmetros vêm do JSON do servidor', () {
    final e = ParamEmpresa.fromJson({'eficiencia': 1, 'mao_obra_hora': 20, 'kwh': 1, 'reserva': 1, 'margens': [10.0]});
    expect(e.maoObraHora, 20);
    expect(e.margens, [10]);
    final i = ParamImpressora.fromJson({'preco': 2000, 'potencia_w': 300.0});
    expect(i.preco, 2000);
    expect(i.potenciaW, 300);
    expect(i.vidaAnos, 3);
  });
}

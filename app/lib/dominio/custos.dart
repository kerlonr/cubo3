/// Cálculo de custo e preço — espelho de `server/app/custos.py` para orçar sem internet.
/// Percentuais em 0–100. Arredonda só os valores de saída.
library;

import '../util/formatos.dart';

double _n(Object? v, double padrao) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? padrao : padrao);

class ParamEmpresa {
  const ParamEmpresa({
    this.eficiencia = 1.1,
    this.maoObraHora = 10,
    this.kwh = 0.656,
    this.reserva = 1.3,
    this.margens = const [20, 30, 50],
  });

  factory ParamEmpresa.fromJson(Map j) => ParamEmpresa(
        eficiencia: _n(j['eficiencia'], 1.1),
        maoObraHora: _n(j['mao_obra_hora'], 10),
        kwh: _n(j['kwh'], 0.656),
        reserva: _n(j['reserva'], 1.3),
        margens: [for (final m in (j['margens'] as List? ?? const [20, 30, 50])) _n(m, 0)],
      );

  final double eficiencia, maoObraHora, kwh, reserva;
  final List<double> margens;

  /// A margem do meio é a usada na tabela por canal (igual ao servidor).
  double get margemMeio => margens[margens.length ~/ 2];
}

class ParamImpressora {
  const ParamImpressora({
    this.preco = 1660,
    this.adicionais = 0,
    this.manutencaoPctAno = 10,
    this.vidaAnos = 3,
    this.usoPct = 50,
    this.potenciaW = 150,
  });

  factory ParamImpressora.fromJson(Map j) => ParamImpressora(
        preco: _n(j['preco'], 1660),
        adicionais: _n(j['adicionais'], 0),
        manutencaoPctAno: _n(j['manutencao_pct_ano'], 10),
        vidaAnos: _n(j['vida_anos'], 3),
        usoPct: _n(j['uso_pct'], 50),
        potenciaW: _n(j['potencia_w'], 150),
      );

  final double preco, adicionais, manutencaoPctAno, vidaAnos, usoPct, potenciaW;
}

class ItemFilamento {
  const ItemFilamento(this.gramas, this.precoKg);
  final double gramas, precoKg;
}

class ItemCusto {
  const ItemCusto(this.qtd, this.custoUnitario);
  final double qtd, custoUnitario;
}

class Receita {
  const Receita(this.filamentos, this.horas, this.maoObraMin,
      {this.insumos = const [], this.embalagem = const [], this.custoEnvio = 0, this.aplicarEficiencia = true});

  final List<ItemFilamento> filamentos;
  final double horas, maoObraMin;
  final List<ItemCusto> insumos, embalagem;
  final double custoEnvio;
  final bool aplicarEficiencia;
}

class Custo {
  const Custo(this.material, this.maoObra, this.maquina, this.insumos, this.embalagem, this.total);
  final double material, maoObra, maquina, insumos, embalagem, total;
}

double custoHoraImpressora(ParamImpressora imp, ParamEmpresa emp) {
  final custoVida = imp.preco + imp.adicionais + imp.preco * imp.manutencaoPctAno / 100 * imp.vidaAnos;
  final horasAno = 8760 * imp.usoPct / 100;
  final capital = custoVida / (horasAno * imp.vidaAnos);
  final energia = imp.potenciaW / 1000 * emp.kwh;
  return (capital + energia) * emp.reserva;
}

double _soma(List<ItemCusto> itens) => itens.fold(0.0, (s, i) => s + i.qtd * i.custoUnitario);

Custo calcularCusto(Receita r, ParamImpressora imp, ParamEmpresa emp) {
  final fator = r.aplicarEficiencia ? emp.eficiencia : 1.0;
  final material = r.filamentos.fold(0.0, (s, f) => s + f.gramas / 1000 * f.precoKg) * fator;
  final maoObra = r.maoObraMin / 60 * emp.maoObraHora;
  final maquina = r.horas * custoHoraImpressora(imp, emp);
  final insumos = _soma(r.insumos);
  final embalagem = _soma(r.embalagem) + r.custoEnvio;
  final total = material + maoObra + maquina + insumos + embalagem;
  return Custo(arred2(material), arred2(maoObra), arred2(maquina), arred2(insumos), arred2(embalagem), arred2(total));
}

/// Custo de uma receita no formato do servidor (`modelo.receita` / calculadora), com os cadastros
/// em JSON. Mesmas regras de `server/app/catalogo/custo.py`: preço do filamento cadastrado
/// (ou `preco_kg` avulso), insumo de categoria "embalagem" vai para embalagem, impressora
/// escolhida ou a primeira cadastrada.
Custo custoDaReceita(
  Map receita, {
  required List filamentos,
  required List insumos,
  required List impressoras,
  required Map config,
  String? impressoraId,
}) {
  Map? achar(List l, Object? id) {
    for (final e in l) {
      if (e is Map && e['id'] == id && id != null) return e;
    }
    return null;
  }

  final fils = <ItemFilamento>[];
  for (final f in (receita['filamentos'] as List? ?? const [])) {
    final cad = achar(filamentos, f['filamento_id']);
    fils.add(ItemFilamento(_n(f['gramas'], 0), cad != null ? _n(cad['preco_kg'], 0) : _n(f['preco_kg'], 0)));
  }
  final ins = <ItemCusto>[], emb = <ItemCusto>[];
  for (final i in (receita['insumos'] as List? ?? const [])) {
    final cad = achar(insumos, i['insumo_id']);
    final custo = cad != null ? _n(cad['custo_unitario'], 0) : _n(i['custo_unitario'], 0);
    final embalagem = cad != null ? cad['categoria'] == 'embalagem' : i['embalagem'] == true;
    if (cad == null && i['insumo_id'] != null) continue; // insumo excluído: o servidor também ignora
    (embalagem ? emb : ins).add(ItemCusto(_n(i['qtd'], 0), custo));
  }
  final ativas = [for (final i in impressoras) if (i is Map && i['excluido'] != true) i];
  final imp = achar(impressoras, impressoraId) ?? (ativas.isEmpty ? null : ativas.first);
  return calcularCusto(
    Receita(fils, _n(receita['horas'], 0), _n(receita['mao_obra_min'], 0),
        insumos: ins, embalagem: emb, custoEnvio: _n(receita['custo_envio'], 0)),
    imp == null ? const ParamImpressora() : ParamImpressora.fromJson(imp),
    ParamEmpresa.fromJson(config),
  );
}

double precoComMargem(double custo, num margemPct) => arred2(custo / (1 - margemPct / 100));

/// null quando margem + taxa chegam a 100% ou mais (preço inviável).
double? precoComCanal(double custo, num margemPct, num taxaPct, num taxaFixa) {
  final divisor = 1 - margemPct / 100 - taxaPct / 100;
  if (divisor <= 0) return null;
  return arred2((custo + taxaFixa) / divisor);
}

double lucroVenda(double preco, double custo, num taxaPct, num taxaFixa) =>
    arred2(preco - custo - preco * taxaPct / 100 - taxaFixa);

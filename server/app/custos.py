"""Cálculo de custo e preço, fiel à planilha "Preço Impressao 3D".

Percentuais em 0–100. Arredonda só os valores de saída.
"""

from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal

D = Decimal
CENTAVO = D("0.01")


def r2(v: Decimal) -> Decimal:
    return D(v).quantize(CENTAVO, rounding=ROUND_HALF_UP)


@dataclass(frozen=True)
class ParamEmpresa:
    eficiencia: Decimal = D("1.1")
    mao_obra_hora: Decimal = D("10")
    kwh: Decimal = D("0.656")
    reserva: Decimal = D("1.3")
    margens: tuple = (20, 30, 50)


@dataclass(frozen=True)
class ParamImpressora:
    preco: Decimal = D("1660")
    adicionais: Decimal = D("0")
    manutencao_pct_ano: Decimal = D("10")
    vida_anos: Decimal = D("3")
    uso_pct: Decimal = D("50")
    potencia_w: Decimal = D("150")


@dataclass
class ItemFilamento:
    gramas: Decimal
    preco_kg: Decimal


@dataclass
class ItemCusto:
    qtd: Decimal
    custo_unitario: Decimal


@dataclass
class Receita:
    filamentos: list[ItemFilamento]
    horas: Decimal
    mao_obra_min: Decimal
    insumos: list[ItemCusto] = field(default_factory=list)
    embalagem: list[ItemCusto] = field(default_factory=list)
    custo_envio: Decimal = D("0")
    aplicar_eficiencia: bool = True
    rendimento: Decimal = D("1")  # peças por impressão: gramas e horas são da mesa inteira


@dataclass
class Custo:
    material: Decimal
    mao_obra: Decimal
    maquina: Decimal
    insumos: Decimal
    embalagem: Decimal
    total: Decimal


def custo_hora_impressora(imp: ParamImpressora, emp: ParamEmpresa) -> Decimal:
    preco, vida = D(imp.preco), D(imp.vida_anos)
    custo_vida = preco + D(imp.adicionais) + preco * D(imp.manutencao_pct_ano) / 100 * vida
    horas_ano = D(8760) * D(imp.uso_pct) / 100
    capital = custo_vida / (horas_ano * vida)
    energia = D(imp.potencia_w) / 1000 * D(emp.kwh)
    return (capital + energia) * D(emp.reserva)


def _soma(itens: list[ItemCusto]) -> Decimal:
    return sum((D(i.qtd) * D(i.custo_unitario) for i in itens), D(0))


def calcular_custo(r: Receita, imp: ParamImpressora, emp: ParamEmpresa) -> Custo:
    fator = D(emp.eficiencia) if r.aplicar_eficiencia else D(1)
    rendimento = max(D(r.rendimento), D(1))
    material = sum((D(f.gramas) / 1000 * D(f.preco_kg) for f in r.filamentos), D(0)) * fator / rendimento
    mao_obra = D(r.mao_obra_min) / 60 * D(emp.mao_obra_hora)
    maquina = D(r.horas) * custo_hora_impressora(imp, emp) / rendimento
    insumos = _soma(r.insumos)
    embalagem = _soma(r.embalagem) + D(r.custo_envio)
    total = material + mao_obra + maquina + insumos + embalagem
    return Custo(r2(material), r2(mao_obra), r2(maquina), r2(insumos), r2(embalagem), r2(total))


def preco_com_margem(custo: Decimal, margem_pct) -> Decimal:
    return r2(D(custo) / (1 - D(margem_pct) / 100))


def preco_com_canal(custo: Decimal, margem_pct, taxa_pct, taxa_fixa) -> Decimal:
    divisor = 1 - D(margem_pct) / 100 - D(taxa_pct) / 100
    if divisor <= 0:
        raise ValueError("Margem + taxa do canal chegam a 100% ou mais")
    return r2((D(custo) + D(taxa_fixa)) / divisor)


def lucro_venda(preco: Decimal, custo: Decimal, taxa_pct, taxa_fixa) -> Decimal:
    preco = D(preco)
    return r2(preco - D(custo) - preco * D(taxa_pct) / 100 - D(taxa_fixa))

from decimal import Decimal as D

import pytest

from app.custos import (ItemCusto, ItemFilamento, ParamEmpresa, ParamImpressora, Receita, calcular_custo,
                        custo_hora_impressora, lucro_venda, preco_com_canal, preco_com_margem)


def test_custo_hora_planilha():
    h = custo_hora_impressora(ParamImpressora(), ParamEmpresa())
    assert h.quantize(D("0.0001")) == D("0.3414")


def test_peca_da_planilha():
    r = Receita([ItemFilamento(D(33), D(100))], horas=D(3), mao_obra_min=D(10))
    c = calcular_custo(r, ParamImpressora(), ParamEmpresa())
    assert (c.material, c.mao_obra, c.maquina, c.total) == (D("3.63"), D("1.67"), D("1.02"), D("6.32"))
    assert [preco_com_margem(c.total, m) for m in (20, 30, 50)] == [D("7.90"), D("9.03"), D("12.64")]


def test_sem_eficiencia_e_extras():
    r = Receita([ItemFilamento(D(33), D(100))], horas=D(0), mao_obra_min=D(0),
                insumos=[ItemCusto(D(4), D("0.50"))], embalagem=[ItemCusto(D(1), D("1.20"))],
                custo_envio=D(5), aplicar_eficiencia=False)
    c = calcular_custo(r, ParamImpressora(), ParamEmpresa())
    assert (c.material, c.insumos, c.embalagem, c.total) == (D("3.30"), D("2.00"), D("6.20"), D("11.50"))


def test_canal_e_lucro():
    assert preco_com_canal(D("6.32"), 30, 20, D(4)) == D("20.64")
    assert lucro_venda(D("12.64"), D("6.32"), 20, D(4)) == D("-0.21")
    with pytest.raises(ValueError):
        preco_com_canal(D(1), 60, 40, D(0))

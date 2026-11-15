from datetime import date, datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.catalogo.modelos import Modelo
from app.custos import r2
from app.estoque.modelos import Movimento
from app.financeiro.modelos import Despesa
from app.impressoes.modelos import Impressao
from app.vendas.modelos import Pedido, PedidoItem

D = Decimal


def _limites(inicio: date, fim: date, tz: ZoneInfo) -> tuple[datetime, datetime]:
    return datetime.combine(inicio, time.min, tz), datetime.combine(fim + timedelta(days=1), time.min, tz)


def _mes(d: date) -> str:
    return f"{d.year:04d}-{d.month:02d}"


def _menos_meses(d: date, n: int) -> date:
    total = d.year * 12 + d.month - 1 - n
    return date(total // 12, total % 12 + 1, 1)


def _entradas_saidas(db: Session, empresa_id, inicio: date, fim: date, tz: ZoneInfo):
    """Lista de (data local, receita, gasto) no intervalo."""
    a, b = _limites(inicio, fim, tz)
    linhas = []
    for quando, receita in db.execute(select(Pedido.entregue_em, Pedido.receita).where(
            Pedido.empresa_id == empresa_id, Pedido.status == "entregue", Pedido.excluido.is_(False),
            Pedido.entregue_em >= a, Pedido.entregue_em < b)):
        linhas.append((quando.astimezone(tz).date(), D(receita), D(0)))
    for quando, valor in db.execute(select(Movimento.data, Movimento.valor).where(
            Movimento.empresa_id == empresa_id, Movimento.tipo == "compra", Movimento.valor.is_not(None),
            Movimento.excluido.is_(False), Movimento.data >= a, Movimento.data < b)):
        linhas.append((quando.astimezone(tz).date(), D(0), D(valor)))
    for dia, valor in db.execute(select(Despesa.data, Despesa.valor).where(
            Despesa.empresa_id == empresa_id, Despesa.excluido.is_(False), Despesa.data >= inicio, Despesa.data <= fim)):
        linhas.append((dia, D(0), D(valor)))
    return linhas


def calcular(db: Session, empresa_id, inicio: date, fim: date, fuso: str) -> dict:
    tz = ZoneInfo(fuso)
    a, b = _limites(inicio, fim, tz)
    linhas = _entradas_saidas(db, empresa_id, inicio, fim, tz)
    receita = sum((r for _, r, _ in linhas), D(0))
    gastos = sum((g for _, _, g in linhas), D(0))
    lucro = db.scalar(select(func.sum(Pedido.lucro)).where(
        Pedido.empresa_id == empresa_id, Pedido.status == "entregue", Pedido.excluido.is_(False),
        Pedido.entregue_em >= a, Pedido.entregue_em < b)) or 0

    # Desde sempre até o fim do período: quanto já foi investido e quanto voltou.
    tudo = _entradas_saidas(db, empresa_id, date(2000, 1, 1), fim, tz)
    investido = sum((g for _, _, g in tudo), D(0))
    recebido = sum((r for _, r, _ in tudo), D(0))

    ano_inicio = _menos_meses(fim, 11)
    por_mes = {_mes(_menos_meses(fim, n)): [D(0), D(0)] for n in range(11, -1, -1)}
    for dia, r, g in _entradas_saidas(db, empresa_id, ano_inicio, fim, tz):
        por_mes[_mes(dia)][0] += r
        por_mes[_mes(dia)][1] += g

    top = db.execute(
        select(PedidoItem.modelo_id, Modelo.nome, func.sum(PedidoItem.quantidade).label("qtd"))
        .join(Pedido, Pedido.id == PedidoItem.pedido_id).join(Modelo, Modelo.id == PedidoItem.modelo_id)
        .where(Pedido.empresa_id == empresa_id, Pedido.status == "entregue", Pedido.excluido.is_(False),
               Pedido.entregue_em >= a, Pedido.entregue_em < b)
        .group_by(PedidoItem.modelo_id, Modelo.nome).order_by(func.sum(PedidoItem.quantidade).desc()).limit(5)).all()
    segundos = db.scalar(select(func.sum(Impressao.duracao_s)).where(
        Impressao.empresa_id == empresa_id, Impressao.status == "confirmada", Impressao.excluido.is_(False),
        Impressao.fim >= a, Impressao.fim < b)) or 0
    gramas = db.scalar(select(func.sum(Movimento.quantidade)).where(
        Movimento.empresa_id == empresa_id, Movimento.item_tipo == "carretel", Movimento.excluido.is_(False),
        Movimento.tipo.in_(("consumo", "perda")), Movimento.data >= a, Movimento.data < b)) or 0
    a_confirmar = db.scalar(select(func.count()).select_from(Impressao).where(
        Impressao.empresa_id == empresa_id, Impressao.status == "a_confirmar", Impressao.excluido.is_(False)))

    return {
        "inicio": inicio.isoformat(), "fim": fim.isoformat(),
        "receita": float(r2(receita)), "gastos": float(r2(gastos)), "resultado": float(r2(receita - gastos)),
        "lucro_vendas": float(r2(D(lucro))),
        "investido": float(r2(investido)), "recebido": float(r2(recebido)),
        "por_mes": [{"mes": m, "receita": float(r2(r)), "gastos": float(r2(g))} for m, (r, g) in por_mes.items()],
        "mais_vendidos": [{"modelo_id": str(i), "nome": n, "qtd": float(q)} for i, n, q in top],
        "a_confirmar": a_confirmar,
        "horas_impressao": round(segundos / 3600, 2),
        "kg_filamento": float(abs(D(gramas)) / 1000),
    }


def extrato(db: Session, empresa_id, inicio: date, fim: date, fuso: str) -> dict:
    """Linhas de dinheiro do período: vendas entregues (entrada), compras do estoque e despesas (saída).
    Mesmas regras de `_entradas_saidas`, com o que cada linha é para o app abrir e corrigir."""
    from app.estoque.modelos import Carretel, Filamento, Insumo
    from app.vendas.modelos import Cliente

    tz = ZoneInfo(fuso)
    a, b = _limites(inicio, fim, tz)
    linhas = []
    for p in db.scalars(select(Pedido).where(
            Pedido.empresa_id == empresa_id, Pedido.status == "entregue", Pedido.excluido.is_(False),
            Pedido.entregue_em >= a, Pedido.entregue_em < b)):
        cl = db.get(Cliente, p.cliente_id) if p.cliente_id else None
        nomes = []
        for i in db.scalars(select(PedidoItem).where(PedidoItem.pedido_id == p.id).order_by(PedidoItem.criado_em)):
            m = db.get(Modelo, i.modelo_id) if i.modelo_id else None
            nomes.append(m.nome if m else i.descricao)
        resumo = (nomes[0] + (f" +{len(nomes) - 1}" if len(nomes) > 1 else "")) if nomes else "Venda"
        linhas.append({"tipo": "venda", "id": str(p.id), "data": p.entregue_em.astimezone(tz).date().isoformat(),
                       "descricao": f"{resumo} · {cl.nome}" if cl else resumo, "valor": float(r2(D(p.receita or 0))),
                       "lucro": float(r2(D(p.lucro or 0))), "pago": p.pago})
    for m in db.scalars(select(Movimento).where(
            Movimento.empresa_id == empresa_id, Movimento.tipo == "compra", Movimento.valor.is_not(None),
            Movimento.excluido.is_(False), Movimento.data >= a, Movimento.data < b)):
        if m.item_tipo == "carretel":
            car = db.get(Carretel, m.item_id)
            f = db.get(Filamento, car.filamento_id) if car else None
            nome = " ".join(x for x in (f.marca, f.material, f.cor_nome) if x) if f else "Filamento"
            descricao, categoria = f"Carretel {nome} · {D(m.quantidade).normalize():f} g", "filamento"
        else:
            ins = db.get(Insumo, m.item_id) if m.item_tipo == "insumo" else None
            descricao = f"{ins.nome if ins else 'Insumo'} · {D(m.quantidade).normalize():f} un"
            categoria = "embalagem" if ins and ins.categoria == "embalagem" else "insumo"
        linhas.append({"tipo": "compra", "id": str(m.id), "data": m.data.astimezone(tz).date().isoformat(),
                       "descricao": descricao, "valor": float(r2(D(m.valor))), "categoria": categoria,
                       "item_tipo": m.item_tipo, "item_id": str(m.item_id)})
    for d in db.scalars(select(Despesa).where(
            Despesa.empresa_id == empresa_id, Despesa.excluido.is_(False), Despesa.data >= inicio, Despesa.data <= fim)):
        linhas.append({"tipo": "despesa", "id": str(d.id), "data": d.data.isoformat(), "descricao": d.descricao,
                       "valor": float(r2(D(d.valor))), "categoria": d.categoria})
    linhas.sort(key=lambda l: l["data"], reverse=True)

    # Filamento perdido em falhas (informativo: o dinheiro já saiu na compra do carretel).
    perdas_g, perdas_valor = D(0), D(0)
    for q, car in db.execute(select(Movimento.quantidade, Carretel).join(Carretel, Carretel.id == Movimento.item_id).where(
            Movimento.empresa_id == empresa_id, Movimento.item_tipo == "carretel", Movimento.tipo == "perda",
            Movimento.excluido.is_(False), Movimento.data >= a, Movimento.data < b)):
        perdas_g += abs(D(q))
        perdas_valor += abs(D(q)) * car.preco_kg_real / 1000
    entrou = sum((D(str(l["valor"])) for l in linhas if l["tipo"] == "venda"), D(0))
    saiu = sum((D(str(l["valor"])) for l in linhas if l["tipo"] != "venda"), D(0))
    lucro = sum((D(str(l["lucro"])) for l in linhas if l["tipo"] == "venda"), D(0))
    return {"inicio": inicio.isoformat(), "fim": fim.isoformat(), "entrou": float(r2(entrou)), "saiu": float(r2(saiu)),
            "resultado": float(r2(entrou - saiu)), "lucro_vendas": float(r2(lucro)),
            "perdas_g": float(r2(perdas_g)), "perdas_valor": float(r2(perdas_valor)), "linhas": linhas}

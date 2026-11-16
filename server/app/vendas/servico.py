import uuid
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Literal

from fastapi import HTTPException
from pydantic import BaseModel, Field
from app.custos import TETO
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx
from app.catalogo.custo import custo_do_modelo
from app.catalogo.modelos import Modelo
from app.crud import faltando, obter
from app.custos import r2
from app.db import Data, agora
from app.empresa.modelos import CanalVenda
from app.estoque.modelos import Movimento
from app.estoque.servico import custo_medio_peca, id_derivado, lancar, saldo
from app.vendas.modelos import Cliente, Pedido, PedidoItem, PedidoPagamento

D = Decimal
Status = Literal["orcamento", "aprovado", "produzindo", "pronto", "entregue", "cancelado"]
FECHADOS = {"entregue", "cancelado"}


class ItemEntrada(BaseModel):
    id: uuid.UUID
    modelo_id: uuid.UUID | None = None
    descricao: str = Field(min_length=1, max_length=160)
    quantidade: Decimal = Field(gt=0, le=TETO)
    preco_unitario: Decimal = Field(ge=0, le=TETO)


class PedidoEntrada(BaseModel):
    cliente_id: uuid.UUID | None = None
    canal_id: uuid.UUID | None = None
    status: Status | None = None
    desconto: Decimal | None = Field(None, ge=0, le=TETO)
    frete_cobrado: Decimal | None = Field(None, ge=0, le=TETO)
    custo_envio: Decimal | None = Field(None, ge=0, le=TETO)
    pago: bool | None = None
    forma_pagamento: str | None = Field(None, max_length=30)
    obs: str | None = Field(None, max_length=2000)
    data: Data | None = None
    entregue_em: Data | None = None  # o app manda o momento real da entrega (fila offline)
    itens: list[ItemEntrada] | None = None


def _itens(db: Session, p: Pedido) -> list[PedidoItem]:
    return list(db.scalars(select(PedidoItem).where(PedidoItem.pedido_id == p.id).order_by(PedidoItem.criado_em)))


def _assinatura(itens, com_preco: bool = True) -> set:
    return {(str(i.id), str(i.modelo_id), D(i.quantidade).normalize()) + ((D(i.preco_unitario).normalize(),) if com_preco else ())
            for i in itens}


def _custo_item(db: Session, empresa_id, modelo_id) -> Decimal:
    if modelo_id is None:
        return D(0)
    medio = custo_medio_peca(db, empresa_id, modelo_id)
    if medio is not None:
        return medio
    # Sem produção: custo do catálogo sem o envio médio da receita (o pedido desconta o próprio envio).
    m = db.get(Modelo, modelo_id)
    return custo_do_modelo(db, empresa_id, m).total - D(str((m.receita or {}).get("custo_envio") or 0))


def _entregar(db: Session, c: Ctx, p: Pedido, quando: datetime | None,
              taxas: tuple | None = None, custos: dict | None = None) -> list[str]:
    """Congela taxas e custos e baixa o estoque. Numa correção de venda entregue, [taxas] e [custos]
    (por id de item) mantêm o que já estava congelado; item novo pega o custo de agora."""
    if taxas is None:
        canal = db.get(CanalVenda, p.canal_id) if p.canal_id else None
        taxas = (canal.taxa_pct, canal.taxa_fixa) if canal else (D(0), D(0))
    p.taxa_pct, p.taxa_fixa = taxas
    p.entregue_em = quando or agora()
    avisos = []
    for it in _itens(db, p):
        modelo_antes, congelado = (custos or {}).get(str(it.id), (None, None))
        mesmo = congelado is not None and modelo_antes == it.modelo_id  # trocou o modelo: custo do novo
        it.custo_unitario = congelado if mesmo else _custo_item(db, c.empresa_id, it.modelo_id)
        if it.modelo_id:
            # pedido reaberto ou corrigido: a mesma baixa volta, atualizada
            lancar(db, c, id=id_derivado(it.id, "venda"), item_tipo="peca", item_id=it.modelo_id, tipo="venda",
                   quantidade=-D(it.quantidade), valor=it.custo_unitario * D(it.quantidade), pedido_id=p.id,
                   data=p.entregue_em, reativar=True)
            s = saldo(db, c.empresa_id, "peca", it.modelo_id)
            if s < 0:
                avisos.append(f"Estoque de {db.get(Modelo, it.modelo_id).nome} ficou em {s.normalize()}")
    _recalcular(db, p)
    return avisos


def _recalcular(db: Session, p: Pedido) -> None:
    """Valores congelados da entrega a partir dos itens (custo de cada item e taxas do canal já fixados)."""
    itens = _itens(db, p)
    bruto = sum((D(i.quantidade) * D(i.preco_unitario) for i in itens), D(0))
    custo_itens = sum((D(i.quantidade) * D(i.custo_unitario or 0) for i in itens), D(0))
    receita = bruto - D(p.desconto or 0) + D(p.frete_cobrado or 0)
    taxas = bruto * D(p.taxa_pct or 0) / 100 + D(p.taxa_fixa or 0)
    p.bruto, p.receita, p.custo_itens, p.taxas = r2(bruto), r2(receita), r2(custo_itens), r2(taxas)
    p.lucro = r2(receita - custo_itens - taxas - D(p.custo_envio or 0))


def _desfazer_entrega(db: Session, p: Pedido) -> None:
    """Volta o pedido para antes da entrega (ou do cancelamento): as baixas e os estornos do pedido saem
    (o estoque fica como se ele nunca tivesse sido entregue) e os valores congelados saem."""
    for m in db.scalars(select(Movimento).where(Movimento.pedido_id == p.id, Movimento.excluido.is_(False))):
        m.excluido = True
    p.bruto = p.receita = p.custo_itens = p.taxas = p.lucro = p.taxa_pct = p.taxa_fixa = None
    p.entregue_em = None
    db.flush()


def total_pedido(db: Session, p: Pedido) -> Decimal:
    if p.receita is not None:
        return D(p.receita)
    bruto = sum((D(i.quantidade) * D(i.preco_unitario) for i in _itens(db, p)), D(0))
    return bruto - D(p.desconto or 0) + D(p.frete_cobrado or 0)


def pagamentos(db: Session, p: Pedido) -> list[PedidoPagamento]:
    return list(db.scalars(select(PedidoPagamento).where(PedidoPagamento.pedido_id == p.id,
                                                         PedidoPagamento.excluido.is_(False))
                           .order_by(PedidoPagamento.data, PedidoPagamento.criado_em)))


def recebido(db: Session, p: Pedido) -> Decimal:
    """Soma das parcelas; pedido antigo marcado como pago sem parcelas conta como pago inteiro."""
    pags = pagamentos(db, p)
    if pags:
        return sum((D(x.valor) for x in pags), D(0))
    return total_pedido(db, p) if p.pago else D(0)


def converter_pago_antigo(db: Session, p: Pedido, valor: Decimal) -> None:
    """Pedido marcado como pago antes de existirem parcelas: o que foi pago vira uma parcela, para não
    sumir ao lançar outra parcela nem crescer junto se o preço for corrigido depois."""
    if not p.pago or pagamentos(db, p) or valor <= 0:
        return
    db.add(PedidoPagamento(id=id_derivado(p.id, "pago-antigo"), empresa_id=p.empresa_id, pedido_id=p.id,
                           valor=r2(valor), forma=p.forma_pagamento, obs="Pago antes das parcelas",
                           data=p.entregue_em or p.data or agora()))
    db.flush()


def atualizar_pago(db: Session, p: Pedido) -> None:
    """Com parcelas lançadas, "pago" sai delas (quitou = pago); sem parcelas, vale o que foi marcado."""
    pags = pagamentos(db, p)
    if not pags:
        return
    p.pago = sum((D(x.valor) for x in pags), D(0)) >= total_pedido(db, p) - D("0.005")
    p.forma_pagamento = pags[-1].forma or p.forma_pagamento
    db.flush()


def _estornar(db: Session, c: Ctx, p: Pedido) -> None:
    for it in _itens(db, p):
        if it.modelo_id:
            lancar(db, c, id=id_derivado(it.id, "estorno"), item_tipo="peca", item_id=it.modelo_id, tipo="ajuste",
                   quantidade=D(it.quantidade), pedido_id=p.id, reativar=True)


def mudar_status(db: Session, c: Ctx, p: Pedido, status: str, quando: datetime | None = None) -> list[str]:
    if status == p.status:
        return []
    if p.status == "cancelado" or (p.status == "entregue" and status != "cancelado"):
        _desfazer_entrega(db, p)  # reabrir: cancelou sem querer, errou a entrega ou vai refazer
    avisos = _entregar(db, c, p, quando) if status == "entregue" else []
    if status == "cancelado" and p.status == "entregue":
        _estornar(db, c, p)
    p.status = status
    db.flush()
    return avisos


def salvar_pedido(db: Session, c: Ctx, id: uuid.UUID, dados: PedidoEntrada) -> tuple[Pedido, list[str]]:
    p = db.get(Pedido, id)
    if p is not None and (p.empresa_id != c.empresa_id or p.excluido):
        raise HTTPException(404, "Pedido não encontrado")
    if dados.cliente_id:
        obter(db, c, Cliente, dados.cliente_id, "Cliente")
    if dados.canal_id:
        obter(db, c, CanalVenda, dados.canal_id, "Canal")
    if dados.itens is not None and len({it.id for it in dados.itens}) != len(dados.itens):
        raise HTTPException(422, "Item repetido no pedido")
    for it in dados.itens or []:
        if it.modelo_id:
            obter(db, c, Modelo, it.modelo_id, "Modelo")
        dono_item = db.get(PedidoItem, it.id)
        if dono_item is not None and dono_item.pedido_id != id:
            raise HTTPException(409, "Item pertence a outro pedido")

    campos = dados.model_dump(exclude_unset=True, exclude={"status", "itens", "entregue_em"})
    avisos_correcao: list[str] = []
    total_antes = total_pedido(db, p) if p is not None and p.pago and not pagamentos(db, p) else None
    if p is None:
        p = Pedido(id=id, empresa_id=c.empresa_id, status="orcamento")
        db.add(p)
    elif p.status == "cancelado":
        if dados.itens is not None and _assinatura(dados.itens) != _assinatura(_itens(db, p)):
            raise HTTPException(409, "Não dá para mudar os itens de um pedido cancelado")
        campos = {k: v for k, v in campos.items() if k in ("pago", "forma_pagamento", "cliente_id", "obs")}
    elif p.status == "entregue":
        # Entregue: tudo pode ser corrigido. Item ou quantidade mudou → desfaz a baixa e baixa de novo, com
        # a mesma data e as mesmas taxas; itens que já existiam mantêm o custo congelado.
        atuais = {str(i.id): i for i in _itens(db, p)}
        mudou_itens = dados.itens is not None and _assinatura(dados.itens, False) != _assinatura(atuais.values(), False)
        mudou_canal = "canal_id" in campos and campos["canal_id"] != p.canal_id
        for k, v in campos.items():
            setattr(p, k, v)
        if dados.entregue_em is not None and dados.entregue_em != p.entregue_em:  # data da venda corrigida
            p.entregue_em = dados.entregue_em
            for m in db.scalars(select(Movimento).where(Movimento.pedido_id == p.id, Movimento.tipo == "venda",
                                                        Movimento.excluido.is_(False))):
                m.data = dados.entregue_em
        if mudou_canal:  # venda lançada no canal errado: as taxas passam a ser as do canal certo
            canal = db.get(CanalVenda, p.canal_id) if p.canal_id else None
            p.taxa_pct, p.taxa_fixa = (canal.taxa_pct, canal.taxa_fixa) if canal else (D(0), D(0))
        campos = {}
        db.flush()
        if mudou_itens:
            custos = {k: (i.modelo_id, i.custo_unitario) for k, i in atuais.items()}
            quando, taxas = p.entregue_em, (p.taxa_pct, p.taxa_fixa)
            _desfazer_entrega(db, p)
            for velho in atuais.values():
                db.delete(velho)
            db.flush()
            for it in dados.itens:
                db.add(PedidoItem(empresa_id=c.empresa_id, pedido_id=id, **it.model_dump()))
            db.flush()
            avisos_correcao = _entregar(db, c, p, quando, taxas, custos)
        elif dados.itens is not None:
            for it in dados.itens:
                atuais[str(it.id)].preco_unitario = it.preco_unitario
        db.flush()
        _recalcular(db, p)
    for k, v in campos.items():
        setattr(p, k, v)
    if dados.itens is not None and p.status not in FECHADOS:
        for velho in _itens(db, p):
            db.delete(velho)
        db.flush()
        for it in dados.itens:
            db.add(PedidoItem(empresa_id=c.empresa_id, pedido_id=id, **it.model_dump()))
    if falta := faltando(p):
        raise HTTPException(422, f"Campos obrigatórios: {', '.join(falta)}")
    db.flush()
    bruto = sum((D(i.quantidade) * D(i.preco_unitario) for i in _itens(db, p)), D(0))
    if D(p.desconto or 0) > bruto + D(p.frete_cobrado or 0):
        raise HTTPException(422, "Desconto maior que o total do pedido")
    avisos = mudar_status(db, c, p, dados.status, dados.entregue_em) if dados.status else []
    if total_antes is not None and total_pedido(db, p) != total_antes:
        converter_pago_antigo(db, p, total_antes)
    atualizar_pago(db, p)
    if pagamentos(db, p) and (sobra := recebido(db, p) - total_pedido(db, p)) > D("0.005"):
        avisos.append(f"Já recebeu R$ {r2(recebido(db, p)):.2f} e o total ficou R$ {r2(total_pedido(db, p)):.2f}: "
                      f"sobram R$ {r2(sobra):.2f} (devolva ou corrija as parcelas)".replace(".", ","))
    return p, avisos_correcao + avisos


def ja_aplicado(db: Session, p: Pedido, dados: PedidoEntrada) -> bool:
    """A mesma edição já está gravada (a resposta se perdeu e a fila reenviou)."""
    campos = dados.model_dump(exclude_unset=True, exclude={"itens", "entregue_em"})
    if any(getattr(p, k) != v for k, v in campos.items()):
        return False
    return dados.itens is None or _assinatura(dados.itens) == _assinatura(_itens(db, p))


def vendidos_por_modelo(db: Session, empresa_id, periodo_dias: int | None = None) -> dict[uuid.UUID, tuple[Decimal, Decimal]]:
    """modelo_id → (quantidade vendida, lucro bruto dos itens) em pedidos entregues."""
    q = (select(PedidoItem.modelo_id, func.sum(PedidoItem.quantidade),
                func.sum((PedidoItem.preco_unitario - func.coalesce(PedidoItem.custo_unitario, 0)) * PedidoItem.quantidade))
         .join(Pedido, Pedido.id == PedidoItem.pedido_id)
         .where(Pedido.empresa_id == empresa_id, Pedido.status == "entregue", Pedido.excluido.is_(False),
                PedidoItem.modelo_id.is_not(None)))
    if periodo_dias:
        q = q.where(Pedido.entregue_em >= agora() - timedelta(days=periodo_dias))
    return {m: (D(q_), D(l)) for m, q_, l in db.execute(q.group_by(PedidoItem.modelo_id)).all()}

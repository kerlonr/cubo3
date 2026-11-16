import uuid
from datetime import date, datetime, time
from decimal import Decimal
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx
from app.config import config
from app.crud import obter
from app.estoque.modelos import Carretel, Insumo, Movimento

# Tipo de item → modelo que ele referencia. O catálogo registra "peca" → Modelo.
ITENS: dict[str, type] = {"carretel": Carretel, "insumo": Insumo}
POSITIVOS = {"compra", "producao"}
NEGATIVOS = {"consumo", "perda", "venda"}
TIPOS = POSITIVOS | NEGATIVOS | {"ajuste"}


def id_derivado(base: uuid.UUID, chave: str) -> uuid.UUID:
    return uuid.uuid5(base, chave)


def meio_dia_local(d: date) -> datetime:
    return datetime.combine(d, time(12), tzinfo=ZoneInfo(config().fuso))


def lancar(db: Session, c: Ctx, *, id: uuid.UUID, item_tipo: str, item_id: uuid.UUID, tipo: str,
           quantidade, valor=None, impressao_id=None, pedido_id=None, data: datetime | None = None,
           reativar: bool = False) -> Movimento:
    """Mesmo id = mesmo lançamento (reenvio não duplica). [reativar]: um lançamento desfeito pela origem
    (impressão reaberta, pedido reaberto) volta com os valores novos. O manual apagado nunca volta."""
    existente = db.get(Movimento, id)
    if existente is not None:
        if existente.empresa_id != c.empresa_id:
            raise HTTPException(404, "Movimento não encontrado")
        if not (reativar and existente.excluido):
            return existente
    if item_tipo not in ITENS or tipo not in TIPOS:
        raise HTTPException(422, "Tipo de item ou de movimento inválido")
    q = Decimal(quantidade)
    if (tipo in POSITIVOS and q <= 0) or (tipo in NEGATIVOS and q >= 0) or q == 0:
        raise HTTPException(422, f"Quantidade com sinal errado para '{tipo}'")
    obter(db, c, ITENS[item_tipo], item_id, "Item")
    if existente is not None:  # reativar
        existente.excluido, existente.item_tipo, existente.item_id, existente.tipo = False, item_tipo, item_id, tipo
        existente.quantidade, existente.valor, existente.impressao_id, existente.pedido_id = q, valor, impressao_id, pedido_id
        existente.data = data or datetime.now(ZoneInfo("UTC"))
        db.flush()
        return existente
    m = Movimento(id=id, empresa_id=c.empresa_id, item_tipo=item_tipo, item_id=item_id, tipo=tipo, quantidade=q,
                  valor=valor, impressao_id=impressao_id, pedido_id=pedido_id, usuario_id=c.usuario.id,
                  data=data or datetime.now(ZoneInfo("UTC")))
    db.add(m)
    db.flush()
    return m


def _base(empresa_id, item_tipo):
    return (Movimento.empresa_id == empresa_id, Movimento.item_tipo == item_tipo, Movimento.excluido.is_(False))


def saldo(db: Session, empresa_id, item_tipo: str, item_id) -> Decimal:
    s = db.scalar(select(func.sum(Movimento.quantidade)).where(*_base(empresa_id, item_tipo), Movimento.item_id == item_id))
    return Decimal(s or 0)


def saldos(db: Session, empresa_id, item_tipo: str) -> dict[uuid.UUID, Decimal]:
    linhas = db.execute(select(Movimento.item_id, func.sum(Movimento.quantidade))
                        .where(*_base(empresa_id, item_tipo)).group_by(Movimento.item_id)).all()
    return {i: Decimal(s) for i, s in linhas}


def custo_medio_peca(db: Session, empresa_id, modelo_id) -> Decimal | None:
    valor, qtd = db.execute(select(func.sum(Movimento.valor), func.sum(Movimento.quantidade))
                            .where(*_base(empresa_id, "peca"), Movimento.item_id == modelo_id,
                                   Movimento.tipo == "producao", Movimento.valor.is_not(None))).one()
    if not qtd:
        return None
    return Decimal(valor or 0) / Decimal(qtd)

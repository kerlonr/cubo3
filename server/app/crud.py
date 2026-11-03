"""Rotas CRUD por empresa: GET lista/um, PUT upsert idempotente por id, DELETE lógico."""
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Callable

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx, so_dono
from app.db import DaEmpresa, get_db

AUTOMATICOS = {"id", "empresa_id", "criado_em", "atualizado_em", "excluido"}


def valor_json(v: Any) -> Any:
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, uuid.UUID):
        return str(v)
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v


def serializar(obj, excluir: tuple[str, ...] = ()) -> dict:
    return {c.key: valor_json(getattr(obj, c.key)) for c in obj.__table__.columns if c.key not in excluir}


def obter(db: Session, c: Ctx, modelo: type[DaEmpresa], id: uuid.UUID, nome: str = "Registro"):
    obj = db.get(modelo, id)
    if obj is None or obj.empresa_id != c.empresa_id:
        raise HTTPException(404, f"{nome} não encontrado")
    return obj


def faltando(obj) -> list[str]:
    return [col.key for col in obj.__table__.columns
            if col.key not in AUTOMATICOS and not col.nullable and col.default is None
            and getattr(obj, col.key) is None]


def upsert(db: Session, c: Ctx, modelo: type[DaEmpresa], id: uuid.UUID, dados: dict):
    """Cria ou atualiza; devolve (obj, criado). Id de outra empresa → 404, nada muda."""
    obj = db.get(modelo, id)
    if obj is not None and obj.empresa_id != c.empresa_id:
        raise HTTPException(404, "Registro não encontrado")
    criado = obj is None
    if criado:
        obj = modelo(id=id, empresa_id=c.empresa_id)
        db.add(obj)
    for k, v in dados.items():
        setattr(obj, k, v)
    if falta := faltando(obj):
        db.rollback()
        raise HTTPException(422, f"Campos obrigatórios: {', '.join(falta)}")
    db.flush()
    return obj, criado


def consulta_lista(modelo, c: Ctx, atualizado_desde: datetime | None = None, incluir_excluidos: bool = False):
    q = select(modelo).where(modelo.empresa_id == c.empresa_id)
    if not incluir_excluidos:
        q = q.where(modelo.excluido.is_(False))
    if atualizado_desde is not None:
        q = q.where(modelo.atualizado_em > atualizado_desde)
    return q.order_by(modelo.criado_em)


def rotas_crud(modelo: type[DaEmpresa], entrada: type[BaseModel], saida: Callable[[Session, Any], dict],
               prefixo: str, *, so_dono_escreve: bool = False,
               ao_salvar: Callable[[Session, Ctx, Any, bool], None] | None = None,
               nome: str = "Registro", com_listagem: bool = True,
               ao_excluir: Callable[[Session, Ctx, Any], None] | None = None) -> APIRouter:
    """com_listagem=False: o módulo define o próprio GET da lista (filtros/ordem específicos)."""
    r = APIRouter(prefix="/api", tags=[prefixo.strip("/")])
    escreve = so_dono if so_dono_escreve else ctx

    if com_listagem:
        @r.get(prefixo)
        def listar(atualizado_desde: datetime | None = None, incluir_excluidos: bool = False,
                   c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
            q = consulta_lista(modelo, c, atualizado_desde, incluir_excluidos)
            return [saida(db, o) for o in db.scalars(q)]

    @r.get(prefixo + "/{id}")
    def um(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
        return saida(db, obter(db, c, modelo, id, nome))

    @r.put(prefixo + "/{id}")
    def salvar(id: uuid.UUID, dados: entrada, c: Ctx = Depends(escreve), db: Session = Depends(get_db)):
        obj, criado = upsert(db, c, modelo, id, dados.model_dump(exclude_unset=True))
        if ao_salvar:
            ao_salvar(db, c, obj, criado)
        db.commit()
        return saida(db, obj)

    @r.delete(prefixo + "/{id}")
    def excluir(id: uuid.UUID, c: Ctx = Depends(escreve), db: Session = Depends(get_db)):
        obj = obter(db, c, modelo, id, nome)
        obj.excluido = True
        if ao_excluir:
            ao_excluir(db, c, obj)
        db.commit()
        return {"ok": True}

    return r

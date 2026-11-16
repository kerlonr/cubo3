import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from app.custos import MINIMO, TETO
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx
from app.crud import obter, rotas_crud, serializar
from app.db import Data, get_db
from app.estoque.modelos import Carretel, Filamento, Insumo, Movimento
from app.estoque.servico import id_derivado, lancar, meio_dia_local, saldo, saldos


class FilamentoEntrada(BaseModel):
    marca: str | None = Field(None, min_length=1, max_length=60)
    material: str | None = Field(None, min_length=1, max_length=30)
    cor_nome: str | None = Field(None, max_length=40)
    cor_hex: str | None = Field(None, pattern=r"^#[0-9A-Fa-f]{6}$")
    diametro: Decimal | None = Field(None, ge=MINIMO, le=TETO)
    densidade: Decimal | None = Field(None, ge=MINIMO, le=TETO)
    preco_kg: Decimal | None = Field(None, ge=0, le=TETO)
    peso_carretel_vazio_g: Decimal | None = Field(None, ge=0, le=TETO)
    estoque_minimo_g: Decimal | None = Field(None, ge=0, le=TETO)


class CarretelEntrada(BaseModel):
    filamento_id: uuid.UUID | None = None
    peso_inicial_g: Decimal | None = Field(None, ge=MINIMO, le=TETO)
    preco_pago: Decimal | None = Field(None, ge=0, le=TETO)
    data_compra: date | None = None
    local: str | None = Field(None, max_length=60)
    aberto: bool | None = None
    arquivado: bool | None = None


class InsumoEntrada(BaseModel):
    nome: str | None = Field(None, min_length=1, max_length=80)
    unidade: str | None = Field(None, max_length=10)
    categoria: Literal["insumo", "embalagem"] | None = None
    custo_unitario: Decimal | None = Field(None, ge=0, le=TETO)
    estoque_minimo: Decimal | None = Field(None, ge=0, le=TETO)


class MovimentoEntrada(BaseModel):
    item_tipo: str
    item_id: uuid.UUID
    tipo: str
    quantidade: Decimal = Field(ge=-TETO, le=TETO)
    valor: Decimal | None = Field(None, ge=0, le=TETO)
    data: Data | None = None


class Pesagem(BaseModel):
    movimento_id: uuid.UUID
    peso_balanca_g: Decimal = Field(ge=0, le=TETO)


def resumo_filamento(f: Filamento) -> dict:
    return {"id": str(f.id), "marca": f.marca, "material": f.material, "cor_nome": f.cor_nome,
            "cor_hex": f.cor_hex, "excluido": f.excluido}


def saida_carretel(db: Session, c: Carretel) -> dict:
    return {**serializar(c), "saldo_g": float(saldo(db, c.empresa_id, "carretel", c.id)),
            "preco_kg_real": float(round(c.preco_kg_real, 2)),
            "filamento": resumo_filamento(db.get(Filamento, c.filamento_id))}


def saida_insumo(db: Session, i: Insumo) -> dict:
    return {**serializar(i), "saldo": float(saldo(db, i.empresa_id, "insumo", i.id))}


def ao_salvar_carretel(db: Session, c: Ctx, car: Carretel, criado: bool) -> None:
    obter(db, c, Filamento, car.filamento_id, "Filamento")
    if criado:
        lancar(db, c, id=id_derivado(car.id, "compra"), item_tipo="carretel", item_id=car.id, tipo="compra",
               quantidade=car.peso_inicial_g, valor=car.preco_pago, data=meio_dia_local(car.data_compra))
        return
    # Edição (preço, peso ou data digitados errado): a compra acompanha, e o gasto e o saldo ficam certos.
    compra = db.get(Movimento, id_derivado(car.id, "compra"))
    if compra is not None:
        compra.quantidade, compra.valor = car.peso_inicial_g, car.preco_pago
        compra.data = meio_dia_local(car.data_compra)
        db.flush()


def ao_excluir_carretel(db: Session, c: Ctx, car: Carretel) -> None:
    # Carretel cadastrado por engano: o gasto da compra sai do financeiro junto. Já usado, o gasto aconteceu.
    usado = db.scalar(select(Movimento.id).where(Movimento.item_tipo == "carretel", Movimento.item_id == car.id,
                                                 Movimento.excluido.is_(False), Movimento.tipo != "compra").limit(1))
    if usado is not None:
        raise HTTPException(409, "Esse carretel já foi usado. Arquive em vez de excluir (o gasto aconteceu).")
    compra = db.get(Movimento, id_derivado(car.id, "compra"))
    if compra is not None:
        compra.excluido = True


rotas_filamentos = rotas_crud(Filamento, FilamentoEntrada, lambda db, o: serializar(o), "/filamentos", nome="Filamento")
rotas_carreteis = rotas_crud(Carretel, CarretelEntrada, saida_carretel, "/carreteis",
                             ao_salvar=ao_salvar_carretel, ao_excluir=ao_excluir_carretel, nome="Carretel")
rotas_insumos = rotas_crud(Insumo, InsumoEntrada, saida_insumo, "/insumos", nome="Insumo")

rotas = APIRouter(prefix="/api", tags=["estoque"])


@rotas.put("/movimentos/{id}")
def gravar_movimento(id: uuid.UUID, dados: MovimentoEntrada, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    m = lancar(db, c, id=id, **dados.model_dump())
    db.commit()
    return serializar(m)


@rotas.delete("/movimentos/{id}")
def excluir_movimento(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    """Desfaz um lançamento manual (compra de insumo, ajuste). Os de impressão, venda e compra de
    carretel são corrigidos na origem (confirmação, pedido, cadastro do carretel)."""
    m = obter(db, c, Movimento, id, "Movimento")
    if m.impressao_id or m.pedido_id or (m.item_tipo == "carretel" and m.id == id_derivado(m.item_id, "compra")):
        raise HTTPException(409, "Esse lançamento é corrigido na origem (impressão, pedido ou carretel)")
    m.excluido = True
    db.commit()
    return {"ok": True}


@rotas.get("/movimentos")
def listar_movimentos(item_tipo: str | None = None, item_id: uuid.UUID | None = None,
                      c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    q = select(Movimento).where(Movimento.empresa_id == c.empresa_id, Movimento.excluido.is_(False))
    if item_tipo:
        q = q.where(Movimento.item_tipo == item_tipo)
    if item_id:
        q = q.where(Movimento.item_id == item_id)
    return [serializar(m) for m in db.scalars(q.order_by(Movimento.data, Movimento.criado_em))]


@rotas.post("/carreteis/{id}/pesagem")
def pesagem(id: uuid.UUID, dados: Pesagem, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    car = obter(db, c, Carretel, id, "Carretel")
    vazio = db.get(Filamento, car.filamento_id).peso_carretel_vazio_g
    if vazio is None:
        raise HTTPException(422, "Informe o peso do carretel vazio no cadastro do filamento")
    diferenca = (dados.peso_balanca_g - Decimal(vazio)) - saldo(db, c.empresa_id, "carretel", car.id)
    if diferenca != 0:
        lancar(db, c, id=dados.movimento_id, item_tipo="carretel", item_id=car.id, tipo="ajuste", quantidade=diferenca)
    db.commit()
    return saida_carretel(db, car)


@rotas.get("/estoque")
def estoque(c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    s_car = saldos(db, c.empresa_id, "carretel")
    ativos = list(db.scalars(select(Carretel).where(Carretel.empresa_id == c.empresa_id, Carretel.excluido.is_(False),
                                                    Carretel.arquivado.is_(False)).order_by(Carretel.criado_em)))
    total_por_filamento: dict[uuid.UUID, Decimal] = {}
    for car in ativos:
        total_por_filamento[car.filamento_id] = total_por_filamento.get(car.filamento_id, Decimal(0)) + s_car.get(car.id, 0)
    filamentos = db.scalars(select(Filamento).where(Filamento.empresa_id == c.empresa_id, Filamento.excluido.is_(False)))
    s_ins = saldos(db, c.empresa_id, "insumo")
    insumos = db.scalars(select(Insumo).where(Insumo.empresa_id == c.empresa_id, Insumo.excluido.is_(False)))
    return {
        "carreteis": [saida_carretel(db, car) for car in ativos],
        "filamentos": [{**resumo_filamento(f), "total_g": float(t := total_por_filamento.get(f.id, Decimal(0))),
                        "baixo": t < f.estoque_minimo_g} for f in filamentos],
        "insumos": [{"id": str(i.id), "nome": i.nome, "categoria": i.categoria,
                     "saldo": float(s := s_ins.get(i.id, Decimal(0))), "baixo": s < i.estoque_minimo} for i in insumos],
        "pecas": [{"modelo_id": str(m), "saldo": float(s)} for m, s in saldos(db, c.empresa_id, "peca").items()],
    }

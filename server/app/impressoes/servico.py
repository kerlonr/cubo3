import uuid
from decimal import Decimal
from typing import Literal

from fastapi import HTTPException
from pydantic import BaseModel, Field
from app.custos import TETO
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.auth.deps import Ctx
from app.catalogo.custo import receita_do_modelo
from app.catalogo.modelos import Modelo
from app.crud import obter
from app.custos import calcular_custo, custo_hora_impressora, r2
from app.db import agora
from app.empresa.modelos import Impressora
from app.empresa.rotas import impressora_padrao, param_empresa, param_impressora
from app.estoque.modelos import Carretel, Insumo, Movimento
from app.estoque.servico import id_derivado, lancar
from app.impressoes.modelos import Impressao

D = Decimal


class Uso(BaseModel):
    carretel_id: uuid.UUID
    gramas: Decimal = Field(gt=0, le=TETO)


class Confirmacao(BaseModel):
    finalidade: Literal["venda", "pessoal", "teste", "falhou"]
    pecas_boas: int = Field(0, ge=0, le=100_000)
    parte: int | None = Field(None, ge=0, le=49)  # índice da peça na receita; None = o item inteiro
    consumos: list[Uso] = []
    perdas: list[Uso] = []
    mao_obra_min: Decimal | None = Field(None, ge=0, le=TETO)
    modelo_id: uuid.UUID | None = None


def casar_modelo(db: Session, empresa_id, arquivo: str | None) -> uuid.UUID | None:
    if not arquivo:
        return None
    # shortcut: varre os modelos em Python (nomes_arquivo é JSON); ok para centenas de modelos.
    for m in db.scalars(select(Modelo).where(Modelo.empresa_id == empresa_id, Modelo.excluido.is_(False))):
        if arquivo in (m.nomes_arquivo or []):
            return m.id
    return None


def confirmar(db: Session, c: Ctx, imp: Impressao, dados: Confirmacao) -> Impressao:
    # Trava a impressão antes de qualquer lançamento: dois aparelhos confirmando juntos → só um baixa estoque.
    if imp.excluido:
        raise HTTPException(404, "Impressão não encontrada")
    tomada = db.execute(update(Impressao).where(Impressao.id == imp.id, Impressao.excluido.is_(False),
                                                Impressao.status.in_(("a_confirmar", "arquivada")))
                        .values(status="confirmada")).rowcount
    if not tomada:
        db.refresh(imp)
        if imp.status == "confirmada":
            return imp  # reenvio da fila offline ou outro aparelho já confirmou: nada muda
        raise HTTPException(409, "Impressão já descartada")
    modelo = obter(db, c, Modelo, dados.modelo_id, "Modelo") if dados.modelo_id else (
        db.get(Modelo, imp.modelo_id) if imp.modelo_id else None)
    # Mesmo carretel repetido na lista (ex.: duas cores do mesmo rolo) vira um lançamento só, somado.
    usos: dict[tuple[str, uuid.UUID], Decimal] = {}
    for tipo, lista in (("consumo", dados.consumos), ("perda", dados.perdas)):
        for u in lista:
            usos[(tipo, u.carretel_id)] = usos.get((tipo, u.carretel_id), D(0)) + u.gramas
    carreteis = {cid: obter(db, c, Carretel, cid, "Carretel") for _, cid in usos}

    material = sum((g * carreteis[cid].preco_kg_real / 1000 for (_, cid), g in usos.items()), D(0))
    emp = param_empresa(db, c.empresa_id)
    impressora = db.get(Impressora, imp.impressora_id) if imp.impressora_id else None
    segundos = imp.duracao_s or (int((imp.fim - imp.inicio).total_seconds()) if imp.inicio and imp.fim else 0)
    maquina = D(max(segundos, 0)) / 3600 * custo_hora_impressora(param_impressora(impressora), emp)
    receita = (modelo.receita or {}) if modelo else {}
    so_parte = dados.parte is not None and len(receita.get("filamentos", [])) >= 2
    if so_parte and dados.parte >= len(receita["filamentos"]):
        raise HTTPException(422, "Essa peça não existe na receita do modelo")
    # Digitada na confirmação = da impressão toda; a da receita é por peça (montagem de cada uma).
    # Impressão de uma parte só (o case): montagem e insumos entram quando o item fica completo (montar).
    minutos = dados.mao_obra_min if dados.mao_obra_min is not None else \
        (D(0) if so_parte else D(str(receita.get("mao_obra_min", 0))) * dados.pecas_boas)
    mao_obra = minutos / 60 * emp.mao_obra_hora
    r = receita_do_modelo(db, c.empresa_id, receita, D(dados.pecas_boas))
    insumos = D(0) if so_parte else sum((i.qtd * i.custo_unitario for i in r.insumos + r.embalagem), D(0))
    total = r2(material + maquina + mao_obra + insumos)

    for (tipo, cid), gramas in usos.items():
        lancar(db, c, id=id_derivado(imp.id, f"{tipo}:{cid}"), item_tipo="carretel",
               item_id=cid, tipo=tipo, quantidade=-gramas, impressao_id=imp.id, data=imp.fim, reativar=True)
    if dados.pecas_boas > 0 and not so_parte:  # insumos da receita saem do estoque (o alerta de "repor" funciona)
        for i in receita.get("insumos", []):
            ins = db.get(Insumo, uuid.UUID(str(i["insumo_id"]))) if i.get("insumo_id") else None
            qtd = D(str(i.get("qtd") or 0)) * dados.pecas_boas
            if ins is not None and ins.empresa_id == c.empresa_id and qtd > 0:
                lancar(db, c, id=id_derivado(imp.id, f"insumo:{ins.id}"), item_tipo="insumo", item_id=ins.id,
                       tipo="consumo", quantidade=-qtd, impressao_id=imp.id, data=imp.fim, reativar=True)
    if dados.finalidade == "venda" and modelo and dados.pecas_boas > 0 and not so_parte:
        lancar(db, c, id=id_derivado(imp.id, "producao"), item_tipo="peca", item_id=modelo.id, tipo="producao",
               quantidade=dados.pecas_boas, valor=total, impressao_id=imp.id, data=imp.fim, reativar=True)
    if modelo and imp.arquivo and imp.arquivo not in (modelo.nomes_arquivo or []):
        modelo.nomes_arquivo = [*(modelo.nomes_arquivo or []), imp.arquivo]

    imp.modelo_id = modelo.id if modelo else None
    imp.finalidade, imp.pecas_boas = dados.finalidade, dados.pecas_boas
    imp.parte = dados.parte if so_parte else None
    imp.custo_total = total
    imp.custo_unitario = r2(total / dados.pecas_boas) if dados.pecas_boas else None
    imp.status, imp.confirmada_por, imp.confirmada_em = "confirmada", c.usuario.id, agora()
    imp.fim = imp.fim or agora()
    db.flush()
    if so_parte:
        montar(db, c, modelo)
    return imp


def _partes_confirmadas(db: Session, modelo: Modelo, i: int):
    return select(func.coalesce(func.sum(Impressao.pecas_boas), 0), func.sum(Impressao.custo_total)).where(
        Impressao.modelo_id == modelo.id, Impressao.parte == i, Impressao.status == "confirmada",
        Impressao.finalidade == "venda", Impressao.excluido.is_(False), Impressao.pecas_boas > 0)


def custo_real_unidade(db: Session, c: Ctx, modelo: Modelo) -> Decimal:
    """Uma unidade do item de várias peças: custo real médio de cada peça (impressões confirmadas daquela
    peça; sem nenhuma ainda, a estimativa do catálogo), mais montagem e insumos uma vez só."""
    receita = modelo.receita or {}
    emp = param_empresa(db, c.empresa_id)
    imp = param_impressora(impressora_padrao(db, c.empresa_id, modelo.impressora_id))
    total = D(0)
    for i, parte in enumerate(receita.get("filamentos", [])):
        qtd, valor = db.execute(_partes_confirmadas(db, modelo, i)).one()
        if qtd:
            total += D(valor or 0) / D(qtd)
        else:
            so = {"filamentos": [parte], "horas": parte.get("horas") or 0,
                  "pecas_por_impressao": receita.get("pecas_por_impressao") or 1}
            total += calcular_custo(receita_do_modelo(db, c.empresa_id, so), imp, emp).total
    r = receita_do_modelo(db, c.empresa_id, receita)
    total += D(str(receita.get("mao_obra_min", 0))) / 60 * emp.mao_obra_hora
    total += sum((i.qtd * i.custo_unitario for i in r.insumos + r.embalagem), D(0))
    return r2(total)


def montar(db: Session, c: Ctx, modelo: Modelo) -> None:
    """Item de várias peças impressas separadas: o estoque ganha 1 unidade quando existe uma de cada peça.
    Recalcula sempre (confirmar ou reabrir uma peça): unidade a mais some, unidade nova entra com o custo
    real e baixa os insumos uma vez."""
    partes = (modelo.receita or {}).get("filamentos", [])
    if len(partes) < 2:
        return
    completas = min(int(db.execute(_partes_confirmadas(db, modelo, i)).one()[0]) for i in range(len(partes)))
    unidade = custo_real_unidade(db, c, modelo)
    insumos = [(i["insumo_id"], D(str(i.get("qtd") or 0))) for i in (modelo.receita or {}).get("insumos", [])
               if i.get("insumo_id")]
    n = 0
    while True:
        mid = id_derivado(modelo.id, f"montagem:{n}")
        if n < completas:
            lancar(db, c, id=mid, item_tipo="peca", item_id=modelo.id, tipo="producao", quantidade=1,
                   valor=unidade, data=agora(), reativar=True)
            for iid, qtd in insumos:
                ins = db.get(Insumo, uuid.UUID(str(iid)))
                if ins is not None and ins.empresa_id == c.empresa_id and qtd > 0:
                    lancar(db, c, id=id_derivado(mid, f"insumo:{ins.id}"), item_tipo="insumo", item_id=ins.id,
                           tipo="consumo", quantidade=-qtd, data=agora(), reativar=True)
        else:
            m = db.get(Movimento, mid)
            if m is None:
                break
            m.excluido = True
            for iid, _ in insumos:
                x = db.get(Movimento, id_derivado(mid, f"insumo:{uuid.UUID(str(iid))}"))
                if x is not None:
                    x.excluido = True
        n += 1
    db.flush()


def reabrir(db: Session, c: Ctx, imp: Impressao) -> Impressao:
    """Confirmou errado ou descartou sem querer: volta para "a confirmar". Os gastos de filamento, os
    insumos e as peças produzidas saem do estoque; a próxima confirmação lança tudo de novo."""
    if imp.status not in ("confirmada", "descartada"):
        raise HTTPException(409, "Só dá para reabrir impressão confirmada ou descartada")
    for m in db.scalars(select(Movimento).where(Movimento.impressao_id == imp.id, Movimento.empresa_id == c.empresa_id,
                                                Movimento.excluido.is_(False))):
        m.excluido = True
    imp.status, imp.finalidade, imp.pecas_boas = "a_confirmar", None, 0
    imp.custo_total = imp.custo_unitario = imp.confirmada_por = imp.confirmada_em = None
    parte, imp.parte = imp.parte, None
    db.flush()
    if parte is not None and imp.modelo_id:
        montar(db, c, db.get(Modelo, imp.modelo_id))  # a unidade montada com essa peça sai do estoque
    return imp


def descartar(db: Session, c: Ctx, imp: Impressao) -> Impressao:
    if imp.status == "confirmada":
        raise HTTPException(409, "Impressão já confirmada")
    imp.status = "descartada"
    db.flush()
    return imp

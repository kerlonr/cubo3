import uuid
from decimal import Decimal
from pathlib import Path

from fastapi import APIRouter, Depends, Header, HTTPException, Response, UploadFile
from fastapi.responses import FileResponse
from pydantic import AwareDatetime, BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx
from app.catalogo.arquivos import salvar_upload
from app.catalogo.modelos import Modelo
from app.config import config
from app.crud import obter, rotas_crud, serializar
from app.db import Data, agora, get_db
from app.vendas import servico
from app.auth.modelos import Empresa
from app.custos import r2
from app.pix import copia_e_cola, exibir, txid_de
from app.vendas.modelos import Cliente, Pedido, PedidoAnexo, PedidoPagamento


class ClienteEntrada(BaseModel):
    nome: str | None = Field(None, min_length=1, max_length=120)
    telefone: str | None = Field(None, max_length=30)
    email: str | None = Field(None, max_length=254)
    obs: str | None = Field(None, max_length=2000)


class NovoStatus(BaseModel):
    status: servico.Status


def saida_pedido(db: Session, p: Pedido, avisos: list[str] | None = None) -> dict:
    itens = []
    for it in servico._itens(db, p):
        m = db.get(Modelo, it.modelo_id) if it.modelo_id else None
        itens.append({**serializar(it), "modelo": {"id": str(m.id), "nome": m.nome, "excluido": m.excluido} if m else None})
    cl = db.get(Cliente, p.cliente_id) if p.cliente_id else None
    anexos = db.scalars(select(PedidoAnexo).where(PedidoAnexo.pedido_id == p.id, PedidoAnexo.excluido.is_(False))
                        .order_by(PedidoAnexo.criado_em))
    total, pago = servico.total_pedido(db, p), servico.recebido(db, p)
    return {**serializar(p), "itens": itens, "cliente": {"id": str(cl.id), "nome": cl.nome, "telefone": cl.telefone} if cl else None,
            "anexos": [saida_anexo(a) for a in anexos],
            "pagamentos": [serializar(x) for x in servico.pagamentos(db, p)],
            "total": float(r2(total)), "recebido": float(r2(pago)), "saldo": float(r2(max(total - pago, 0))),
            "excedente": float(r2(max(pago - total, 0))),
            "avisos": avisos or []}


TIPOS_ANEXO = {".png": "foto", ".jpg": "foto", ".jpeg": "foto", ".webp": "foto", ".pdf": "pdf"}


def saida_anexo(a: PedidoAnexo) -> dict:
    return {"id": str(a.id), "nome_original": a.nome_original, "tipo": a.tipo, "tamanho": a.tamanho,
            "url": f"/api/anexos/{a.id}", "criado_em": a.criado_em.isoformat()}


rotas_clientes = rotas_crud(Cliente, ClienteEntrada, lambda db, o: serializar(o), "/clientes", nome="Cliente")
rotas = APIRouter(prefix="/api", tags=["vendas"])


@rotas.get("/clientes/{id}/historico")
def historico(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    cl = obter(db, c, Cliente, id, "Cliente")
    pedidos = list(db.scalars(select(Pedido).where(Pedido.cliente_id == cl.id, Pedido.excluido.is_(False))
                              .order_by(Pedido.data.desc())))
    total = sum((p.receita for p in pedidos if p.status == "entregue"), 0)
    return {"cliente": serializar(cl), "pedidos": [saida_pedido(db, p) for p in pedidos], "total_comprado": float(total)}


@rotas.get("/pedidos")
def listar(status: str | None = None, cliente_id: uuid.UUID | None = None, c: Ctx = Depends(ctx),
           db: Session = Depends(get_db)):
    q = select(Pedido).where(Pedido.empresa_id == c.empresa_id, Pedido.excluido.is_(False))
    if status:
        q = q.where(Pedido.status == status)
    if cliente_id:
        q = q.where(Pedido.cliente_id == cliente_id)
    return [saida_pedido(db, p) for p in db.scalars(q.order_by(Pedido.data.desc()))]


def _pedido_ativo(db: Session, c: Ctx, id: uuid.UUID) -> Pedido:
    p = obter(db, c, Pedido, id, "Pedido")
    if p.excluido:
        raise HTTPException(404, "Pedido não encontrado")
    return p


@rotas.get("/pedidos/{id}")
def um(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    return saida_pedido(db, _pedido_ativo(db, c, id))


@rotas.put("/pedidos/{id}")
def salvar(id: uuid.UUID, dados: servico.PedidoEntrada, c: Ctx = Depends(ctx), db: Session = Depends(get_db),
           x_versao_base: AwareDatetime | None = Header(None)):
    existente = db.get(Pedido, id)
    if existente is not None and existente.empresa_id == c.empresa_id and x_versao_base is not None \
            and existente.atualizado_em > x_versao_base:
        if servico.ja_aplicado(db, existente, dados):
            return saida_pedido(db, existente)  # reenvio da mesma edição (resposta perdida): já está gravada
        raise HTTPException(409, "Pedido foi alterado por outra pessoa. Abra de novo e refaça a edição.")
    p, avisos = servico.salvar_pedido(db, c, id, dados)
    db.commit()
    return saida_pedido(db, p, avisos)


@rotas.post("/pedidos/{id}/status")
def status(id: uuid.UUID, dados: NovoStatus, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    p = _pedido_ativo(db, c, id)
    avisos = servico.mudar_status(db, c, p, dados.status)
    db.commit()
    return saida_pedido(db, p, avisos)


@rotas.delete("/pedidos/{id}")
def excluir(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    p = obter(db, c, Pedido, id, "Pedido")
    if p.status == "entregue":
        servico.mudar_status(db, c, p, "cancelado")  # devolve as peças ao estoque antes de sumir
    p.excluido = True
    db.commit()
    return {"ok": True}


@rotas.post("/pedidos/{id}/anexos")
async def anexar(id: uuid.UUID, arquivo: UploadFile, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    """Comprovante de pagamento (foto ou PDF), em qualquer etapa do pedido."""
    p = obter(db, c, Pedido, id, "Pedido")
    if p.excluido:
        raise HTTPException(404, "Pedido não encontrado")
    ext = Path(arquivo.filename or "").suffix.lower()
    if ext not in TIPOS_ANEXO:
        raise HTTPException(415, f"Comprovante precisa ser foto ou PDF (veio {ext or 'sem extensão'})")
    a = PedidoAnexo(id=uuid.uuid4(), empresa_id=c.empresa_id, pedido_id=p.id, nome_original=(arquivo.filename or "")[-255:],
                    tipo=TIPOS_ANEXO[ext], tamanho=0, caminho="")
    a.caminho = f"{c.empresa_id}/pedidos/{p.id}/{a.id}{ext}"
    a.tamanho = await salvar_upload(arquivo, config().arquivos_dir / a.caminho, config().max_upload_mb * 1024 * 1024)
    db.add(a)
    db.commit()
    return saida_anexo(a)


@rotas.get("/anexos/{id}")
def baixar_anexo(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    a = obter(db, c, PedidoAnexo, id, "Comprovante")
    if a.excluido:
        raise HTTPException(404, "Comprovante não encontrado")
    return FileResponse(config().arquivos_dir / a.caminho, filename=a.nome_original)


@rotas.delete("/anexos/{id}")
def apagar_anexo(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    # Exclusão lógica: o arquivo fica no disco (e no backup), comprovante de dinheiro não some de vez.
    a = obter(db, c, PedidoAnexo, id, "Comprovante")
    a.excluido = True
    db.commit()
    return {"ok": True}


class PagamentoEntrada(BaseModel):
    valor: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    data: Data | None = None
    forma: str | None = Field(None, max_length=30)
    obs: str | None = Field(None, max_length=200)
    anexo_id: uuid.UUID | None = None


@rotas.put("/pedidos/{pedido_id}/pagamentos/{id}")
def gravar_pagamento(pedido_id: uuid.UUID, id: uuid.UUID, dados: PagamentoEntrada, c: Ctx = Depends(ctx),
                     db: Session = Depends(get_db)):
    """Parcela recebida (sinal, parte, restante). Mesmo id = mesma parcela: reenvio da fila não duplica."""
    p = _pedido_ativo(db, c, pedido_id)
    if p.status == "cancelado":
        raise HTTPException(409, "Pedido cancelado não recebe pagamento")
    # Trava o pedido (Postgres): duas parcelas ao mesmo tempo não passam juntas do total.
    db.execute(select(Pedido.id).where(Pedido.id == p.id).with_for_update())
    x = db.get(PedidoPagamento, id)
    if x is not None and (x.empresa_id != c.empresa_id or x.pedido_id != p.id):
        raise HTTPException(404, "Pagamento não encontrado")
    if x is not None and x.excluido:
        return saida_pedido(db, p)  # reenvio de parcela que já foi apagada: não ressuscita
    servico.converter_pago_antigo(db, p, servico.total_pedido(db, p))
    if dados.anexo_id is not None:
        a = obter(db, c, PedidoAnexo, dados.anexo_id, "Comprovante")
        if a.pedido_id != p.id or a.excluido:
            raise HTTPException(422, "O comprovante precisa ser deste pedido")
    outros = sum((Decimal(y.valor) for y in servico.pagamentos(db, p) if y.id != id), Decimal(0))
    falta = servico.total_pedido(db, p) - outros
    if dados.valor > falta + Decimal("0.005"):
        raise HTTPException(422, f"Passa do total do pedido: falta receber R$ {max(falta, Decimal(0)):.2f}".replace(".", ","))
    if x is None:
        x = PedidoPagamento(id=id, empresa_id=c.empresa_id, pedido_id=p.id)
        db.add(x)
    x.valor, x.forma, x.obs, x.anexo_id = dados.valor, dados.forma, dados.obs, dados.anexo_id
    if dados.data is not None or x.data is None:
        x.data = dados.data or agora()
    db.flush()
    servico.atualizar_pago(db, p)
    db.commit()
    return saida_pedido(db, p)


@rotas.delete("/pagamentos/{id}")
def apagar_pagamento(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    x = obter(db, c, PedidoPagamento, id, "Pagamento")
    x.excluido = True
    db.flush()
    p = db.get(Pedido, x.pedido_id)
    if not servico.pagamentos(db, p):
        p.pago = False  # tirou a última parcela: volta a "a receber"
    servico.atualizar_pago(db, p)
    db.commit()
    return saida_pedido(db, p)


class CobrancaEntrada(BaseModel):
    valor: Decimal | None = Field(None, gt=0, max_digits=12, decimal_places=2)
    pedido_id: uuid.UUID | None = None


@rotas.post("/pix/cobranca")
def cobranca(dados: CobrancaEntrada, resposta: Response, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    """Pix copia e cola com o valor (o que falta do pedido, ou o valor informado). O código leva a chave
    (é o que o banco do cliente lê), então qualquer membro que cobra recebe a chave dentro dele; fora do
    código, a chave inteira só sai para o dono em /api/empresa/pix."""
    resposta.headers["Cache-Control"] = "no-store"
    pix = db.get(Empresa, c.empresa_id).pix
    if not pix:
        raise HTTPException(409, "Cadastre o seu Pix em Empresa → Pix")
    valor = dados.valor
    if dados.pedido_id is not None:
        p = obter(db, c, Pedido, dados.pedido_id, "Pedido")
        if p.excluido or p.status == "cancelado":
            raise HTTPException(409, "Pedido cancelado ou excluído")
        if valor is None:
            valor = r2(max(servico.total_pedido(db, p) - servico.recebido(db, p), Decimal(0)))
            if valor <= 0:
                raise HTTPException(409, "Esse pedido já está pago")
        elif valor > servico.total_pedido(db, p) + Decimal("0.005"):
            raise HTTPException(422, "Valor maior que o total do pedido")
    if valor is None:
        raise HTTPException(422, "Informe o valor")
    codigo = copia_e_cola(pix["chave"], pix["nome"], pix["cidade"], valor, txid_de(dados.pedido_id))
    return {"valor": float(valor), "copia_e_cola": codigo, "recebedor": pix["nome"], "tipo": pix["tipo"],
            "chave": exibir(pix["tipo"], pix["chave"])}

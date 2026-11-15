import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx
from app.catalogo.arquivos import salvar_upload
from app.catalogo.modelos import Modelo
from app.config import config
from app.crud import obter, rotas_crud, serializar
from app.db import get_db
from app.vendas import servico
from app.vendas.modelos import Cliente, Pedido, PedidoAnexo


class ClienteEntrada(BaseModel):
    nome: str | None = Field(None, min_length=1)
    telefone: str | None = None
    email: str | None = None
    obs: str | None = None


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
    return {**serializar(p), "itens": itens, "cliente": {"id": str(cl.id), "nome": cl.nome, "telefone": cl.telefone} if cl else None,
            "anexos": [saida_anexo(a) for a in anexos], "avisos": avisos or []}


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


@rotas.get("/pedidos/{id}")
def um(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    return saida_pedido(db, obter(db, c, Pedido, id, "Pedido"))


@rotas.put("/pedidos/{id}")
def salvar(id: uuid.UUID, dados: servico.PedidoEntrada, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    p, avisos = servico.salvar_pedido(db, c, id, dados)
    db.commit()
    return saida_pedido(db, p, avisos)


@rotas.post("/pedidos/{id}/status")
def status(id: uuid.UUID, dados: NovoStatus, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    p = obter(db, c, Pedido, id, "Pedido")
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
    ext = Path(arquivo.filename or "").suffix.lower()
    if ext not in TIPOS_ANEXO:
        raise HTTPException(415, f"Comprovante precisa ser foto ou PDF (veio {ext or 'sem extensão'})")
    a = PedidoAnexo(id=uuid.uuid4(), empresa_id=c.empresa_id, pedido_id=p.id, nome_original=arquivo.filename,
                    tipo=TIPOS_ANEXO[ext], tamanho=0, caminho="")
    a.caminho = f"{c.empresa_id}/pedidos/{p.id}/{a.id}{ext}"
    a.tamanho = await salvar_upload(arquivo, config().arquivos_dir / a.caminho, config().max_upload_mb * 1024 * 1024)
    db.add(a)
    db.commit()
    return saida_anexo(a)


@rotas.get("/anexos/{id}")
def baixar_anexo(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    a = obter(db, c, PedidoAnexo, id, "Comprovante")
    return FileResponse(config().arquivos_dir / a.caminho, filename=a.nome_original)


@rotas.delete("/anexos/{id}")
def apagar_anexo(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    # Exclusão lógica: o arquivo fica no disco (e no backup), comprovante de dinheiro não some de vez.
    a = obter(db, c, PedidoAnexo, id, "Comprovante")
    a.excluido = True
    db.commit()
    return {"ok": True}

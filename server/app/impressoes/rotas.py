import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx
from app.catalogo.modelos import Modelo
from app.config import config
from app.crud import consulta_lista, obter, rotas_crud, serializar
from app.db import get_db
from app.empresa.modelos import Impressora
from app.impressoes import servico
from app.impressoes.modelos import Impressao


class ImpressaoEntrada(BaseModel):
    impressora_id: uuid.UUID | None = None
    modelo_id: uuid.UUID | None = None
    arquivo: str | None = None
    inicio: datetime | None = None
    fim: datetime | None = None
    duracao_s: int | None = Field(None, ge=0)
    estimativa: dict | None = None


def saida_impressao(db: Session, i: Impressao) -> dict:
    return {**serializar(i), "miniatura_url": f"/api/impressoes/{i.id}/miniatura" if i.miniatura else None}


def ao_salvar(db: Session, c: Ctx, i: Impressao, criado: bool) -> None:
    if i.impressora_id:
        obter(db, c, Impressora, i.impressora_id, "Impressora")
    if i.modelo_id:
        obter(db, c, Modelo, i.modelo_id, "Modelo")


def ao_excluir(db: Session, c: Ctx, i: Impressao) -> None:
    if i.status == "confirmada":
        raise HTTPException(409, "Impressão confirmada já mexeu no estoque; não pode ser excluída")


rotas_impressoes = rotas_crud(Impressao, ImpressaoEntrada, saida_impressao, "/impressoes", ao_salvar=ao_salvar,
                              ao_excluir=ao_excluir, nome="Impressão", com_listagem=False)
rotas = APIRouter(prefix="/api", tags=["impressoes"])


@rotas.get("/impressoes")
def listar(status: str | None = None, atualizado_desde: datetime | None = None, incluir_excluidos: bool = False,
           c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    q = consulta_lista(Impressao, c, atualizado_desde, incluir_excluidos)
    if status:
        q = q.where(Impressao.status == status)
    return [saida_impressao(db, i) for i in db.scalars(q)]


@rotas.post("/impressoes/{id}/confirmar")
def confirmar(id: uuid.UUID, dados: servico.Confirmacao, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    i = servico.confirmar(db, c, obter(db, c, Impressao, id, "Impressão"), dados)
    db.commit()
    return saida_impressao(db, i)


@rotas.post("/impressoes/{id}/descartar")
def descartar(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    i = servico.descartar(db, c, obter(db, c, Impressao, id, "Impressão"))
    db.commit()
    return saida_impressao(db, i)


@rotas.get("/impressoes/{id}/miniatura")
def miniatura(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    i = obter(db, c, Impressao, id, "Impressão")
    if not i.miniatura or not (config().arquivos_dir / i.miniatura).exists():
        raise HTTPException(404, "Sem miniatura")
    return FileResponse(config().arquivos_dir / i.miniatura, media_type="image/png")

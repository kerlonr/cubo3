import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.deps import Ctx, ctx
from app.catalogo.arquivos import salvar_upload, tipo_do_arquivo
from app.catalogo.custo import custo_do_modelo, custo_json
from app.catalogo.modelos import Arquivo, Modelo
from app.config import config
from app.crud import consulta_lista, obter, rotas_crud, serializar
from app.db import get_db
from app.estoque.servico import saldo


class ItemReceitaFilamento(BaseModel):
    filamento_id: uuid.UUID
    gramas: Decimal = Field(ge=0)


class ItemReceitaInsumo(BaseModel):
    insumo_id: uuid.UUID
    qtd: Decimal = Field(ge=0)


class ReceitaEntrada(BaseModel):
    filamentos: list[ItemReceitaFilamento] = []
    horas: Decimal = Field(Decimal(0), ge=0)
    mao_obra_min: Decimal = Field(Decimal(0), ge=0)
    insumos: list[ItemReceitaInsumo] = []
    custo_envio: Decimal = Field(Decimal(0), ge=0)


class Link(BaseModel):
    titulo: str = ""
    url: str


class ModeloEntrada(BaseModel):
    nome: str | None = Field(None, min_length=1)
    descricao: str | None = None
    categoria: str | None = None
    tags: list[str] | None = None
    links: list[Link] | None = None
    receita: ReceitaEntrada | None = None
    impressora_id: uuid.UUID | None = None
    preco_venda: Decimal | None = Field(None, ge=0)
    nomes_arquivo: list[str] | None = None

    def model_dump(self, **kw):
        # JSON das colunas precisa de tipos simples (UUID/Decimal viram texto).
        d = super().model_dump(**kw)
        for campo in ("receita", "links"):
            if campo in d and d[campo] is not None:
                d[campo] = super().model_dump(mode="json", include={campo})[campo]
        return d


def saida_arquivo(a: Arquivo) -> dict:
    return {"id": str(a.id), "nome_original": a.nome_original, "tipo": a.tipo, "tamanho": a.tamanho,
            "url": f"/api/arquivos/{a.id}", "criado_em": a.criado_em.isoformat()}


def saida_modelo(db: Session, m: Modelo, vendidos: Decimal | None = None) -> dict:
    if vendidos is None:
        from app.vendas.servico import vendidos_por_modelo
        vendidos = vendidos_por_modelo(db, m.empresa_id).get(m.id, (Decimal(0),))[0]
    custo = custo_do_modelo(db, m.empresa_id, m)
    arquivos = db.scalars(select(Arquivo).where(Arquivo.modelo_id == m.id).order_by(Arquivo.criado_em))
    return {**serializar(m), "custo": custo_json(custo),
            "lucro_unitario": float(m.preco_venda - custo.total) if m.preco_venda is not None else None,
            "estoque": float(saldo(db, m.empresa_id, "peca", m.id)), "vendidos": float(vendidos),
            "arquivos": [saida_arquivo(a) for a in arquivos],
            "capa_url": f"/api/arquivos/{m.capa_id}" if m.capa_id else None}


rotas_modelos = rotas_crud(Modelo, ModeloEntrada, saida_modelo, "/modelos", nome="Modelo", com_listagem=False)
rotas = APIRouter(prefix="/api", tags=["catalogo"])


@rotas.get("/modelos")
def listar_modelos(busca: str | None = None, categoria: str | None = None, tag: str | None = None,
                   ordem: str = "nome", periodo_dias: int | None = None, atualizado_desde: str | None = None, incluir_excluidos: bool = False,
                   c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    # shortcut: filtro e ordem em Python; ok para centenas de modelos, levar para SQL se passar de alguns milhares.
    modelos = list(db.scalars(consulta_lista(Modelo, c, atualizado_desde, incluir_excluidos)))
    if busca:
        b = busca.casefold()
        modelos = [m for m in modelos if b in m.nome.casefold() or b in (m.descricao or "").casefold()]
    if categoria:
        modelos = [m for m in modelos if (m.categoria or "").casefold() == categoria.casefold()]
    if tag:
        modelos = [m for m in modelos if tag.casefold() in [t.casefold() for t in m.tags or []]]
    from app.vendas.servico import vendidos_por_modelo  # vendas depende do catálogo; import tardio evita ciclo
    vendas = vendidos_por_modelo(db, c.empresa_id, periodo_dias)
    zero = (Decimal(0), Decimal(0))
    modelos.sort(key=lambda m: m.nome.casefold())
    if ordem == "recentes":
        modelos.sort(key=lambda m: m.criado_em, reverse=True)
    elif ordem == "mais_vendidos":
        modelos.sort(key=lambda m: vendas.get(m.id, zero)[0], reverse=True)
    elif ordem == "lucro":
        modelos.sort(key=lambda m: vendas.get(m.id, zero)[1], reverse=True)
    return [saida_modelo(db, m, vendas.get(m.id, zero)[0]) for m in modelos]


@rotas.post("/modelos/{id}/arquivos")
async def enviar_arquivo(id: uuid.UUID, arquivo: UploadFile, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    m = obter(db, c, Modelo, id, "Modelo")
    ext, tipo = tipo_do_arquivo(arquivo.filename or "")
    a = Arquivo(id=uuid.uuid4(), empresa_id=c.empresa_id, modelo_id=m.id, nome_original=arquivo.filename,
                tipo=tipo, tamanho=0, caminho="")
    a.caminho = f"{c.empresa_id}/{m.id}/{a.id}{ext}"
    a.tamanho = await salvar_upload(arquivo, config().arquivos_dir / a.caminho, config().max_upload_mb * 1024 * 1024)
    db.add(a)
    if tipo == "foto" and m.capa_id is None:
        m.capa_id = a.id
    db.commit()
    return saida_arquivo(a)


@rotas.get("/arquivos/{id}")
def baixar_arquivo(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    a = obter(db, c, Arquivo, id, "Arquivo")
    return FileResponse(config().arquivos_dir / a.caminho, filename=a.nome_original)


@rotas.delete("/arquivos/{id}")
def apagar_arquivo(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    a = obter(db, c, Arquivo, id, "Arquivo")
    m = db.get(Modelo, a.modelo_id)
    if m.capa_id == a.id:
        m.capa_id = None
    db.delete(a)
    db.commit()
    (config().arquivos_dir / a.caminho).unlink(missing_ok=True)
    return {"ok": True}

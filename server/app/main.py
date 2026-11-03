import os
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.auth.rotas import rotas as rotas_auth
from app.catalogo import calculadora
from app.catalogo import rotas as catalogo
from app.db import SessionLocal
from app.empresa import rotas as empresa
from app.estoque import rotas as estoque
from app.financeiro import rotas as financeiro
from app.impressoes import rotas as impressoes
from app.klipper import rotas as klipper
from app.klipper.monitor import monitores
from app.vendas import rotas as vendas


@asynccontextmanager
async def ciclo(app: FastAPI):
    if os.environ.get("KLIPPER_ATIVO", "1") != "0":
        await monitores.iniciar_todos(SessionLocal)
    yield
    await monitores.parar_todos()


def criar_app() -> FastAPI:
    app = FastAPI(title="Cubo³", docs_url="/api/docs", openapi_url="/api/openapi.json", lifespan=ciclo)

    @app.get("/api/saude")
    def saude():
        return {"ok": True}

    for r in (rotas_auth, empresa.rotas, empresa.rotas_canais, empresa.rotas_impressoras,
              estoque.rotas_filamentos, estoque.rotas_carreteis, estoque.rotas_insumos, estoque.rotas,
              catalogo.rotas, catalogo.rotas_modelos, calculadora.rotas,
              impressoes.rotas, impressoes.rotas_impressoes, vendas.rotas, vendas.rotas_clientes,
              financeiro.rotas, financeiro.rotas_despesas, klipper.rotas):
        app.include_router(r)
    return app


app = criar_app()

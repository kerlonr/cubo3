from fastapi import FastAPI

from app.auth.rotas import rotas as rotas_auth
from app.empresa import rotas as empresa


def criar_app() -> FastAPI:
    app = FastAPI(title="Cubo³", docs_url="/api/docs", openapi_url="/api/openapi.json")

    @app.get("/api/saude")
    def saude():
        return {"ok": True}

    for r in (rotas_auth, empresa.rotas, empresa.rotas_canais, empresa.rotas_impressoras):
        app.include_router(r)
    return app


app = criar_app()

from fastapi import FastAPI

from app.auth.rotas import rotas as rotas_auth


def criar_app() -> FastAPI:
    app = FastAPI(title="Cubo³", docs_url="/api/docs", openapi_url="/api/openapi.json")

    @app.get("/api/saude")
    def saude():
        return {"ok": True}

    app.include_router(rotas_auth)
    return app


app = criar_app()

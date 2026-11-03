from fastapi import FastAPI


def criar_app() -> FastAPI:
    app = FastAPI(title="Cubo³", docs_url="/api/docs", openapi_url="/api/openapi.json")

    @app.get("/api/saude")
    def saude():
        return {"ok": True}

    return app


app = criar_app()

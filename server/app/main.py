import json
import os
import re
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.responses import FileResponse

from app.ao_vivo import hub
from app.auth.rotas import rotas as rotas_auth
from app.catalogo import calculadora
from app.catalogo import rotas as catalogo
from app.config import config
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
    docs = os.environ.get("API_DOCS") == "1"
    app = FastAPI(title="Cubo³", docs_url="/api/docs" if docs else None,
                  openapi_url="/api/openapi.json" if docs else None, lifespan=ciclo)

    @app.exception_handler(RequestValidationError)
    async def erro_de_validacao(request: Request, exc: RequestValidationError):
        # Sem devolver o valor recebido: NaN/Infinity quebravam a resposta (500) ao virar JSON.
        erros = [{"loc": list(e.get("loc", [])), "msg": e.get("msg", ""), "type": e.get("type", "")} for e in exc.errors()]
        return JSONResponse(status_code=422, content={"detail": erros})

    @app.middleware("http")
    async def avisar_mudanca(request: Request, call_next):
        """Toda escrita aceita avisa os aparelhos da empresa (WebSocket /api/ao-vivo): o celular e o
        PC recarregam a tela aberta na hora. Comandos da impressora e leituras via POST não contam."""
        resposta = await call_next(request)
        if request.method in ("PUT", "POST", "DELETE") and resposta.status_code < 400                 and request.url.path.startswith("/api/") and not _SEM_AVISO.match(request.url.path):
            try:
                hub.publicar(uuid.UUID(request.headers.get("x-empresa", "")), {"tipo": "dados", "caminho": request.url.path})
            except ValueError:
                pass  # sem empresa (não acontece em escrita aceita): nada a avisar
        return resposta

    @app.get("/api/saude")
    def saude():
        return {"ok": True}

    for r in (rotas_auth, empresa.rotas, empresa.rotas_canais, empresa.rotas_impressoras,
              estoque.rotas_filamentos, estoque.rotas_carreteis, estoque.rotas_insumos, estoque.rotas,
              catalogo.rotas, catalogo.rotas_modelos, calculadora.rotas,
              impressoes.rotas, impressoes.rotas_impressoes, vendas.rotas, vendas.rotas_clientes,
              financeiro.rotas, financeiro.rotas_despesas, klipper.rotas):
        app.include_router(r)
    _versao_e_web(app)
    return app


_SEM_AVISO = re.compile(r"^/api/(auth/|calculadora$|arquivos/[^/]+/(link|imprimir)$|"
                        r"impressoras/[^/]+/(comando|gcode|camera/link|arquivos/imprimir)$)")


def _versao_e_web(app: FastAPI) -> None:
    cfg = config()

    def _versao() -> dict:
        arq = cfg.apk_dir / "versao.json" if cfg.apk_dir else None
        if arq is None or not arq.is_file():
            raise HTTPException(404, "Nenhuma versão do app publicada")
        return json.loads(arq.read_text(encoding="utf-8"))

    @app.get("/api/versao")
    def versao():
        v = _versao()
        return {"versao": v["versao"], "build": v["build"], "apk_url": "/baixar"}

    @app.get("/baixar")
    def baixar():
        apk = cfg.apk_dir / _versao()["apk"]
        if not apk.is_file():
            raise HTTPException(404, "APK não encontrado")
        return FileResponse(apk, filename=apk.name, media_type="application/vnd.android.package-archive")

    if cfg.web_dir is None or not cfg.web_dir.is_dir():
        return
    raiz = cfg.web_dir.resolve()

    @app.get("/{caminho:path}", include_in_schema=False)
    def web(caminho: str):
        if caminho == "api" or caminho.startswith("api/"):
            raise HTTPException(404, "Rota não encontrada")
        alvo = (raiz / caminho).resolve()
        if alvo.is_relative_to(raiz) and alvo.is_file():
            return FileResponse(alvo)
        return FileResponse(raiz / "index.html")  # rotas do app web (SPA)


app = criar_app()

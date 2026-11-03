import time
import uuid
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import AfterValidator, BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session
from typing_extensions import Annotated

from app.auth.deps import Ctx, ctx, so_dono, usuario_atual
from app.auth.modelos import Empresa, Membro, Usuario
from app.auth.seguranca import confere_senha, emitir_tokens, hash_senha, ler_token
from app.auth.servico import adicionar_membro, criar_dono, normaliza_email
from app.config import config
from app.db import get_db

rotas = APIRouter(prefix="/api", tags=["auth"])

JANELA_S = 15 * 60
MAX_FALHAS = 5


def _senha_valida(v: str) -> str:
    if len(v) < 8:
        raise ValueError("A senha precisa ter pelo menos 8 caracteres")
    return v


SenhaNova = Annotated[str, AfterValidator(_senha_valida)]
Email = Annotated[str, Field(pattern=r"^[^@\s]+@[^@\s]+$")]


class Login(BaseModel):
    email: str
    senha: str


class Refresh(BaseModel):
    refresh: str


class TrocaSenha(BaseModel):
    atual: str
    nova: SenhaNova


class NovoMembro(BaseModel):
    email: Email
    nome: str = Field(min_length=1)
    senha_inicial: SenhaNova
    papel: Literal["dono", "membro"] = "membro"


class Cadastro(BaseModel):
    nome: str = Field(min_length=1)
    email: Email
    senha: SenhaNova
    empresa: str = Field(min_length=1)


def _falhas(request: Request) -> dict[str, list[float]]:
    if not hasattr(request.app.state, "falhas_login"):
        request.app.state.falhas_login = {}
    return request.app.state.falhas_login


@rotas.post("/auth/login")
def login(dados: Login, request: Request, db: Session = Depends(get_db)):
    email = normaliza_email(dados.email)
    falhas = _falhas(request)
    recentes = [t for t in falhas.get(email, []) if time.time() - t < JANELA_S]
    falhas[email] = recentes
    if len(recentes) >= MAX_FALHAS:
        raise HTTPException(429, "Muitas tentativas. Espere 15 minutos.")
    u = db.scalar(select(Usuario).where(Usuario.email == email, Usuario.excluido.is_(False)))
    if u is None or not confere_senha(dados.senha, u.senha_hash):
        recentes.append(time.time())
        raise HTTPException(401, "E-mail ou senha incorretos")
    falhas.pop(email, None)
    return {**emitir_tokens(u), "trocar_senha": u.trocar_senha}


@rotas.post("/auth/refresh")
def refresh(dados: Refresh, db: Session = Depends(get_db)):
    claims = ler_token(dados.refresh, "refresh")
    u = db.get(Usuario, uuid.UUID(claims["sub"]))
    if u is None or u.excluido or u.token_versao != claims.get("v"):
        raise HTTPException(401, "Sessão inválida ou expirada")
    return emitir_tokens(u)


@rotas.post("/auth/senha")
def trocar_senha(dados: TrocaSenha, u: Usuario = Depends(usuario_atual), db: Session = Depends(get_db)):
    if not confere_senha(dados.atual, u.senha_hash):
        raise HTTPException(400, "Senha atual incorreta")
    u.senha_hash = hash_senha(dados.nova)
    u.token_versao += 1
    u.trocar_senha = False
    db.commit()
    return emitir_tokens(u)


@rotas.post("/auth/cadastro")
def cadastro(dados: Cadastro, db: Session = Depends(get_db)):
    if not config().cadastro_aberto:
        raise HTTPException(403, "Cadastro fechado. Peça acesso ao dono da empresa.")
    if db.scalar(select(Usuario).where(Usuario.email == normaliza_email(dados.email))):
        raise HTTPException(409, "E-mail já cadastrado")
    u, _ = criar_dono(db, dados.email, dados.nome, dados.senha, dados.empresa)
    db.commit()
    return {**emitir_tokens(u), "trocar_senha": False}


@rotas.get("/eu")
def eu(u: Usuario = Depends(usuario_atual), db: Session = Depends(get_db)):
    linhas = db.execute(
        select(Empresa.id, Empresa.nome, Membro.papel).join(Membro, Membro.empresa_id == Empresa.id)
        .where(Membro.usuario_id == u.id, Empresa.excluido.is_(False)).order_by(Empresa.nome)
    ).all()
    return {"id": str(u.id), "nome": u.nome, "email": u.email, "trocar_senha": u.trocar_senha,
            "empresas": [{"id": str(i), "nome": n, "papel": p} for i, n, p in linhas]}


@rotas.get("/empresa/membros")
def membros(c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    linhas = db.execute(
        select(Usuario.id, Usuario.nome, Usuario.email, Membro.papel).join(Membro, Membro.usuario_id == Usuario.id)
        .where(Membro.empresa_id == c.empresa_id).order_by(Usuario.nome)
    ).all()
    return [{"id": str(i), "nome": n, "email": e, "papel": p} for i, n, e, p in linhas]


@rotas.post("/empresa/membros")
def novo_membro(dados: NovoMembro, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    m = adicionar_membro(db, c.empresa_id, dados.email, dados.nome, dados.senha_inicial, dados.papel)
    db.commit()
    return {"id": str(m.usuario_id), "papel": m.papel}


@rotas.delete("/empresa/membros/{usuario_id}")
def remover_membro(usuario_id: uuid.UUID, c: Ctx = Depends(so_dono), db: Session = Depends(get_db)):
    m = db.scalar(select(Membro).where(Membro.usuario_id == usuario_id, Membro.empresa_id == c.empresa_id))
    if m is None:
        raise HTTPException(404, "Membro não encontrado")
    if m.papel == "dono":
        donos = db.scalar(select(func.count()).select_from(Membro)
                          .where(Membro.empresa_id == c.empresa_id, Membro.papel == "dono"))
        if donos <= 1:
            raise HTTPException(409, "A empresa precisa de pelo menos um dono")
    db.delete(m)
    db.commit()
    return {"ok": True}

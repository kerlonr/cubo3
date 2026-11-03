import uuid
from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.modelos import Membro, Usuario
from app.auth.seguranca import ler_token
from app.db import get_db

_bearer = HTTPBearer(auto_error=False)


@dataclass
class Ctx:
    usuario: Usuario
    empresa_id: uuid.UUID
    papel: str


def usuario_do_token(db: Session, token: str) -> Usuario:
    claims = ler_token(token, "acesso")
    u = db.get(Usuario, uuid.UUID(claims["sub"]))
    if u is None or u.excluido or u.token_versao != claims.get("v"):
        raise HTTPException(401, "Sessão inválida ou expirada")
    return u


def usuario_atual(cred: HTTPAuthorizationCredentials | None = Depends(_bearer), db: Session = Depends(get_db)) -> Usuario:
    if cred is None:
        raise HTTPException(401, "Faça login")
    return usuario_do_token(db, cred.credentials)


def papel_na_empresa(db: Session, usuario_id, empresa_id) -> str | None:
    return db.scalar(select(Membro.papel).where(Membro.usuario_id == usuario_id, Membro.empresa_id == empresa_id))


def ctx(x_empresa: str = Header(...), u: Usuario = Depends(usuario_atual), db: Session = Depends(get_db)) -> Ctx:
    try:
        empresa_id = uuid.UUID(x_empresa)
    except ValueError:
        raise HTTPException(403, "Empresa inválida")
    papel = papel_na_empresa(db, u.id, empresa_id)
    if papel is None:
        raise HTTPException(403, "Você não faz parte desta empresa")
    return Ctx(u, empresa_id, papel)


def so_dono(c: Ctx = Depends(ctx)) -> Ctx:
    if c.papel != "dono":
        raise HTTPException(403, "Só o dono da empresa pode fazer isso")
    return c

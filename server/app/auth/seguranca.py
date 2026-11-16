from datetime import timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from fastapi import HTTPException

from app.config import config
from app.db import agora

_ph = PasswordHasher()
DURACAO = {"acesso": timedelta(minutes=30), "refresh": timedelta(days=60), "download": timedelta(minutes=10), "camera": timedelta(seconds=60)}


def hash_senha(s: str) -> str:
    return _ph.hash(s)


def confere_senha(s: str, h: str) -> bool:
    try:
        return _ph.verify(h, s)
    except VerificationError:
        return False


def _token(u, tipo: str) -> str:
    claims = {"sub": str(u.id), "tipo": tipo, "v": u.token_versao, "exp": agora() + DURACAO[tipo]}
    return jwt.encode(claims, config().jwt_segredo, algorithm="HS256")


def token_link(tipo: str, sub) -> str:
    """Link curto que autoriza sem cabeçalho de login (download no navegador, vídeo num <img>)."""
    claims = {"sub": str(sub), "tipo": tipo, "exp": agora() + DURACAO[tipo]}
    return jwt.encode(claims, config().jwt_segredo, algorithm="HS256")


def token_download(arquivo_id) -> str:
    return token_link("download", arquivo_id)


def emitir_tokens(u) -> dict:
    return {"acesso": _token(u, "acesso"), "refresh": _token(u, "refresh")}


def ler_token(t: str, tipo: str) -> dict:
    try:
        claims = jwt.decode(t, config().jwt_segredo, algorithms=["HS256"], options={"require": ["exp", "sub", "tipo"]})
    except jwt.PyJWTError:
        raise HTTPException(401, "Sessão inválida ou expirada")
    if claims.get("tipo") != tipo:
        raise HTTPException(401, "Sessão inválida ou expirada")
    return claims

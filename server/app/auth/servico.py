from typing import Callable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.modelos import Empresa, Membro, Usuario
from app.auth.seguranca import hash_senha

# Módulos registram aqui o que nasce junto com uma empresa (ex.: canal "Direto").
ao_criar_empresa: list[Callable[[Session, Empresa], None]] = []


def normaliza_email(email: str) -> str:
    return email.strip().lower()


def _usuario(db: Session, email: str, nome: str, senha: str, trocar_senha: bool) -> Usuario:
    email = normaliza_email(email)
    u = db.scalar(select(Usuario).where(Usuario.email == email))
    if u is None:
        u = Usuario(email=email, nome=nome, senha_hash=hash_senha(senha), trocar_senha=trocar_senha)
        db.add(u)
        db.flush()
    return u


def criar_dono(db: Session, email: str, nome: str, senha: str, empresa_nome: str) -> tuple[Usuario, Empresa]:
    u = _usuario(db, email, nome, senha, trocar_senha=False)
    e = Empresa(nome=empresa_nome, config={})
    db.add(e)
    db.flush()
    db.add(Membro(usuario_id=u.id, empresa_id=e.id, papel="dono"))
    for gancho in ao_criar_empresa:
        gancho(db, e)
    db.flush()
    return u, e


def adicionar_membro(db: Session, empresa_id, email: str, nome: str, senha_inicial: str, papel: str = "membro") -> Membro:
    u = _usuario(db, email, nome, senha_inicial, trocar_senha=True)
    m = db.scalar(select(Membro).where(Membro.usuario_id == u.id, Membro.empresa_id == empresa_id))
    if m is None:
        m = Membro(usuario_id=u.id, empresa_id=empresa_id, papel=papel)
        db.add(m)
        db.flush()
    return m

"""Comandos de administração. Uso: python -m app.cli criar-dono --email E --nome N --empresa "Cubo³"."""
import argparse
import getpass


def main() -> None:
    p = argparse.ArgumentParser(prog="app.cli")
    sub = p.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("criar-dono")
    d.add_argument("--email", required=True)
    d.add_argument("--nome", required=True)
    d.add_argument("--empresa", required=True)
    a = p.parse_args()
    senha = getpass.getpass("Senha: ")
    if senha != getpass.getpass("Repita a senha: ") or len(senha) < 8:
        raise SystemExit("Senhas diferentes ou com menos de 8 caracteres")

    import app.main  # noqa: F401  registra modelos e ganchos
    from app.auth.servico import criar_dono
    from app.db import SessionLocal

    with SessionLocal() as db:
        u, e = criar_dono(db, a.email, a.nome, senha, a.empresa)
        db.commit()
        print(f"Dono {u.email} criado na empresa {e.nome} ({e.id})")


if __name__ == "__main__":
    main()

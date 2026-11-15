"""Revisão 8451bff: sobe um banco SQLite em 0001 com um modelo antigo, migra para head, volta e sobe de novo.
Rodar de server/: python tests/revisao_migracao_0002.py"""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

caminho = Path(tempfile.mkdtemp()) / "mig.db"
env = {**os.environ, "DATABASE_URL": f"sqlite+pysqlite:///{caminho.as_posix()}", "JWT_SEGREDO": "x" * 40}


def alembic(*args):
    r = subprocess.run([sys.executable, "-m", "alembic", *args], env=env, capture_output=True, text=True)
    print("alembic", *args, "->", r.returncode, (r.stderr.strip().splitlines() or [""])[-1])
    assert r.returncode == 0, r.stderr


alembic("upgrade", "0001")
c = sqlite3.connect(caminho)
m, cap = uuid.uuid4().hex, uuid.uuid4().hex
receita = {"filamentos": [{"filamento_id": None, "gramas": "33"}], "horas": "3.1667",
           "insumos": [{"insumo_id": uuid.uuid4().hex, "qtd": "1"}]}
c.execute("insert into modelos (id, empresa_id, nome, tags, links, receita, nomes_arquivo, capa_id, criado_em,"
          " atualizado_em, excluido) values (?,?,?,?,?,?,?,?,?,?,0)",
          (m, uuid.uuid4().hex, "Antigo", "[]", "[]", json.dumps(receita), "[]", cap,
           "2026-10-01 12:00:00", "2026-10-01 12:00:00"))
c.commit()
antes = c.execute("select * from modelos").fetchall()
c.close()

alembic("upgrade", "head")
c = sqlite3.connect(caminho)
cols = [r[1] for r in c.execute("pragma table_info(modelos)")]
depois = c.execute("select * from modelos").fetchall()
print("colunas:", cols)
print("linha depois:", depois)
assert "capa_ajuste" in cols
assert depois[0][:len(antes[0])] == antes[0] or set(antes[0]) <= set(depois[0]), "dados mudaram"
assert depois[0][cols.index("capa_ajuste")] is None
c.close()

alembic("downgrade", "0001")
c = sqlite3.connect(caminho)
assert c.execute("select * from modelos").fetchall() == antes, "downgrade perdeu dados"
c.close()
alembic("upgrade", "head")
alembic("check")
print("OK")

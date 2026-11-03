import os

from alembic import context
from sqlalchemy import engine_from_config, pool

import app.main  # noqa: F401  carrega todos os modelos
from app.db import Base

config = context.config
config.set_main_option("sqlalchemy.url", os.environ.get("DATABASE_URL", "sqlite+pysqlite:///./cubo3.db"))
target_metadata = Base.metadata
OPCOES = dict(target_metadata=target_metadata, render_as_batch=True, user_module_prefix="app.db.")


def run_migrations_offline() -> None:
    context.configure(url=config.get_main_option("sqlalchemy.url"), literal_binds=True, **OPCOES)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    conectavel = engine_from_config(config.get_section(config.config_ini_section, {}), prefix="sqlalchemy.",
                                    poolclass=pool.NullPool)
    with conectavel.connect() as conexao:
        context.configure(connection=conexao, **OPCOES)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

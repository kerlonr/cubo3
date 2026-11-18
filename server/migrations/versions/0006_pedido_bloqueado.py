"""pedidos.bloqueado (venda fechada: ninguém altera mais)

Só adiciona uma coluna com padrão false: nenhum dado existente muda.

Revision ID: 0006
Revises: 0005
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = '0006'
down_revision: Union[str, None] = '0005'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('pedidos') as t:
        t.add_column(sa.Column('bloqueado', sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    with op.batch_alter_table('pedidos') as t:
        t.drop_column('bloqueado')

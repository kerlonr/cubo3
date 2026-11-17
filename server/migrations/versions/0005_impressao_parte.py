"""impressoes.parte (impressão de uma parte do item: case, keycap...)

Só adiciona uma coluna que aceita nulo: nenhum dado existente muda.

Revision ID: 0005
Revises: 0004
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = '0005'
down_revision: Union[str, None] = '0004'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('impressoes') as t:
        t.add_column(sa.Column('parte', sa.Integer(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table('impressoes') as t:
        t.drop_column('parte')

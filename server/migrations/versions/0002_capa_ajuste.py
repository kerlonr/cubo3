"""capa_ajuste no modelo (enquadramento da foto de capa)

Só adiciona uma coluna que aceita nulo: nenhum dado existente muda.

Revision ID: 0002
Revises: 0001
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = '0002'
down_revision: Union[str, None] = '0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('modelos') as t:
        t.add_column(sa.Column('capa_ajuste', sa.JSON(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table('modelos') as t:
        t.drop_column('capa_ajuste')

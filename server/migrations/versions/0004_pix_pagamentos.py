"""pix da empresa e pagamentos parciais do pedido

Só adiciona (coluna que aceita nulo e tabela nova): nenhum dado existente muda.

Revision ID: 0004
Revises: 0003
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

import app.db

revision: str = '0004'
down_revision: Union[str, None] = '0003'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('empresas') as t:
        t.add_column(sa.Column('pix', sa.JSON(), nullable=True))
    op.create_table('pedido_pagamentos',
    sa.Column('pedido_id', sa.Uuid(), nullable=False),
    sa.Column('valor', sa.Numeric(precision=12, scale=4), nullable=False),
    sa.Column('data', app.db.UtcDateTime(timezone=True), nullable=False),
    sa.Column('forma', sa.String(length=30), nullable=True),
    sa.Column('obs', sa.String(length=200), nullable=True),
    sa.Column('anexo_id', sa.Uuid(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('criado_em', app.db.UtcDateTime(timezone=True), nullable=False),
    sa.Column('atualizado_em', app.db.UtcDateTime(timezone=True), nullable=False),
    sa.Column('excluido', sa.Boolean(), nullable=False),
    sa.Column('empresa_id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], ),
    sa.ForeignKeyConstraint(['pedido_id'], ['pedidos.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('pedido_pagamentos') as t:
        t.create_index(t.f('ix_pedido_pagamentos_atualizado_em'), ['atualizado_em'], unique=False)
        t.create_index(t.f('ix_pedido_pagamentos_empresa_id'), ['empresa_id'], unique=False)
        t.create_index(t.f('ix_pedido_pagamentos_pedido_id'), ['pedido_id'], unique=False)


def downgrade() -> None:
    op.drop_table('pedido_pagamentos')
    with op.batch_alter_table('empresas') as t:
        t.drop_column('pix')

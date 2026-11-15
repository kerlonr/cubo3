"""pedido_anexos (comprovantes de pagamento)

Só cria uma tabela nova: nenhum dado existente muda.

Revision ID: 0003
Revises: 0002
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

import app.db

revision: str = '0003'
down_revision: Union[str, None] = '0002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('pedido_anexos',
    sa.Column('pedido_id', sa.Uuid(), nullable=False),
    sa.Column('nome_original', sa.String(length=255), nullable=False),
    sa.Column('tipo', sa.String(length=10), nullable=False),
    sa.Column('tamanho', sa.Integer(), nullable=False),
    sa.Column('caminho', sa.String(length=255), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('criado_em', app.db.UtcDateTime(timezone=True), nullable=False),
    sa.Column('atualizado_em', app.db.UtcDateTime(timezone=True), nullable=False),
    sa.Column('excluido', sa.Boolean(), nullable=False),
    sa.Column('empresa_id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], ),
    sa.ForeignKeyConstraint(['pedido_id'], ['pedidos.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('pedido_anexos') as t:
        t.create_index(t.f('ix_pedido_anexos_atualizado_em'), ['atualizado_em'], unique=False)
        t.create_index(t.f('ix_pedido_anexos_empresa_id'), ['empresa_id'], unique=False)
        t.create_index(t.f('ix_pedido_anexos_pedido_id'), ['pedido_id'], unique=False)


def downgrade() -> None:
    op.drop_table('pedido_anexos')

import uuid
from decimal import Decimal

from sqlalchemy.orm import Session

from app.catalogo.modelos import Modelo
from app.custos import Custo, ItemCusto, ItemFilamento, Receita, calcular_custo
from app.empresa.rotas import impressora_padrao, param_empresa, param_impressora
from app.estoque.modelos import Filamento, Insumo

D = Decimal


def _da_empresa(db: Session, modelo, id, empresa_id):
    obj = db.get(modelo, uuid.UUID(str(id))) if id else None  # ids da receita vêm do JSON como texto
    return obj if obj is not None and obj.empresa_id == empresa_id else None


def receita_do_modelo(db: Session, empresa_id, receita: dict, multiplicar_insumos: Decimal = D(1)) -> Receita:
    filamentos = []
    for f in receita.get("filamentos", []):
        fil = _da_empresa(db, Filamento, f.get("filamento_id"), empresa_id)
        # Cadastrado vale mais; sem cadastro usa o preço avulso da receita (antes virava R$ 0 e inflava o lucro).
        preco = fil.preco_kg if fil else D(str(f.get("preco_kg") or 0))
        filamentos.append(ItemFilamento(D(str(f.get("gramas", 0))), preco))
    insumos, embalagem = [], []
    for i in receita.get("insumos", []):
        ins = _da_empresa(db, Insumo, i.get("insumo_id"), empresa_id)
        if ins is None:
            continue
        item = ItemCusto(D(str(i.get("qtd", 0))) * multiplicar_insumos, ins.custo_unitario)
        (embalagem if ins.categoria == "embalagem" else insumos).append(item)
    return Receita(filamentos, D(str(receita.get("horas", 0))), D(str(receita.get("mao_obra_min", 0))),
                   insumos, embalagem, D(str(receita.get("custo_envio", 0))))


def custo_do_modelo(db: Session, empresa_id, modelo: Modelo) -> Custo:
    imp = impressora_padrao(db, empresa_id, modelo.impressora_id)
    return calcular_custo(receita_do_modelo(db, empresa_id, modelo.receita or {}),
                          param_impressora(imp), param_empresa(db, empresa_id))


def custo_json(c: Custo) -> dict:
    return {k: float(v) for k, v in vars(c).items()}

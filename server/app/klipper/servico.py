import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import config
from app.empresa.modelos import Impressora
from app.impressoes.modelos import Impressao
from app.impressoes.servico import casar_modelo
from app.klipper import moonraker
from app.klipper.moonraker import DadosTrabalho

MIN_DURACAO_S = 60  # cancelada antes de 1 min não gastou material que valha cobrar confirmação


def ja_registrado(db: Session, impressora_id, job_id: str) -> Impressao | None:
    return db.scalar(select(Impressao).where(Impressao.impressora_id == impressora_id, Impressao.job_id == job_id))


def registrar_trabalho(db: Session, empresa_id, impressora_id, dados: DadosTrabalho,
                       arquivada: bool = False) -> Impressao | None:
    """Cria a impressão de um trabalho do Klipper. None se já existe (evento repetido) ou se não vale registrar."""
    if ja_registrado(db, impressora_id, dados.job_id):
        return None
    if not arquivada and dados.status != "completed" and dados.duracao_s < MIN_DURACAO_S:
        return None
    i = Impressao(id=uuid.uuid4(), empresa_id=empresa_id, impressora_id=impressora_id, origem="klipper",
                  job_id=dados.job_id, arquivo=dados.arquivo, inicio=dados.inicio, fim=dados.fim,
                  duracao_s=dados.duracao_s, situacao_klipper=dados.status,
                  status="arquivada" if arquivada else "a_confirmar",
                  estimativa={"gramas_total": dados.gramas_total, "filamentos": dados.filamentos},
                  modelo_id=casar_modelo(db, empresa_id, dados.arquivo))
    imp = db.get(Impressora, impressora_id)
    if dados.miniatura_rel and imp and imp.moonraker_url:
        conteudo = moonraker.baixar(imp.moonraker_url, imp.api_key, dados.miniatura_rel)
        if conteudo:
            i.miniatura = f"{empresa_id}/miniaturas/{i.id}.png"
            destino = config().arquivos_dir / i.miniatura
            destino.parent.mkdir(parents=True, exist_ok=True)
            destino.write_bytes(conteudo)
    db.add(i)
    db.flush()
    return i

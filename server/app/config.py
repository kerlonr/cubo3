import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass(frozen=True)
class Config:
    database_url: str
    jwt_segredo: str
    cadastro_aberto: bool
    arquivos_dir: Path
    web_dir: Path | None
    apk_dir: Path | None
    max_upload_mb: int
    fuso: str


def _caminho(nome: str) -> Path | None:
    v = os.environ.get(nome)
    return Path(v) if v else None


@lru_cache
def config() -> Config:
    segredo = os.environ.get("JWT_SEGREDO", "")
    if len(segredo) < 32:
        raise RuntimeError("Defina JWT_SEGREDO com pelo menos 32 caracteres")
    return Config(
        database_url=os.environ.get("DATABASE_URL", "sqlite+pysqlite:///./cubo3.db"),
        jwt_segredo=segredo,
        cadastro_aberto=os.environ.get("CADASTRO_ABERTO", "false").lower() == "true",
        arquivos_dir=_caminho("ARQUIVOS_DIR") or Path("./arquivos"),
        web_dir=_caminho("WEB_DIR"),
        apk_dir=_caminho("APK_DIR"),
        max_upload_mb=int(os.environ.get("MAX_UPLOAD_MB", "95")),
        fuso=os.environ.get("FUSO", "America/Sao_Paulo"),
    )

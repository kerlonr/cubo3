from pathlib import Path

from fastapi import HTTPException, UploadFile

TIPOS = {".stl": "stl", ".3mf": "3mf", ".gcode": "gcode", ".obj": "obj", ".step": "step", ".stp": "step",
         ".png": "foto", ".jpg": "foto", ".jpeg": "foto", ".webp": "foto"}
BLOCO = 1024 * 1024


def tipo_do_arquivo(nome: str) -> tuple[str, str]:
    ext = Path(nome).suffix.lower()
    if ext not in TIPOS:
        raise HTTPException(415, f"Tipo de arquivo não aceito: {ext or 'sem extensão'}")
    return ext, TIPOS[ext]


async def salvar_upload(upload: UploadFile, destino: Path, limite_bytes: int) -> int:
    """Grava em .parcial e só renomeia no fim; acima do limite apaga e devolve 413."""
    destino.parent.mkdir(parents=True, exist_ok=True)
    parcial = destino.with_name(destino.name + ".parcial")
    total = 0
    try:
        with parcial.open("wb") as f:
            while bloco := await upload.read(BLOCO):
                total += len(bloco)
                if total > limite_bytes:
                    raise HTTPException(413, f"Arquivo maior que {limite_bytes // BLOCO} MB")
                f.write(bloco)
        parcial.replace(destino)
    finally:
        parcial.unlink(missing_ok=True)
    return total

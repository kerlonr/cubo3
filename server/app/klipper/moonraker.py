"""Leitura dos dados do Moonraker (API do Klipper): histórico, estado ao vivo e arquivos."""
import json
import posixpath
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import httpx

TIMEOUT = 5


@dataclass
class DadosTrabalho:
    job_id: str
    arquivo: str
    status: str
    inicio: datetime | None
    fim: datetime | None
    duracao_s: int
    gramas_total: float | None
    filamentos: list[dict] = field(default_factory=list)
    miniatura_rel: str | None = None


def _lista(v) -> list:
    """O fatiador manda lista JSON em texto ('["PLA", "PLA"]'), texto puro ('PLA') ou 'PLA;PETG'."""
    if isinstance(v, list):
        return v
    if not isinstance(v, str) or not v.strip():
        return []
    s = v.strip()
    if s.startswith("["):
        try:
            return list(json.loads(s))
        except ValueError:
            pass
    return [p.strip() for p in s.split(";") if p.strip()]


def _quando(ts) -> datetime | None:
    return datetime.fromtimestamp(ts, tz=timezone.utc) if ts else None


def trabalho_de_historico(job: dict) -> DadosTrabalho:
    meta = job.get("metadata") or {}
    tipos, nomes, cores = _lista(meta.get("filament_type")), _lista(meta.get("filament_name")), _lista(meta.get("filament_colors"))
    total = meta.get("filament_weight_total")
    n = max(len(tipos), len(cores), len(nomes))
    filamentos = [{"tipo": tipos[i] if i < len(tipos) else None,
                   "marca": nomes[i].lstrip(".").strip() if i < len(nomes) else None,
                   "cor": cores[i] if i < len(cores) else None,
                   "gramas": total if n == 1 else None} for i in range(n)]
    miniaturas = sorted(meta.get("thumbnails") or [], key=lambda t: t.get("width", 0) * t.get("height", 0))
    arquivo = job.get("filename") or ""
    rel = posixpath.join(posixpath.dirname(arquivo), miniaturas[-1]["relative_path"]) if miniaturas else None
    return DadosTrabalho(job_id=str(job["job_id"]), arquivo=arquivo, status=job.get("status") or "",
                         inicio=_quando(job.get("start_time")), fim=_quando(job.get("end_time")),
                         duracao_s=round(job.get("print_duration") or 0), gramas_total=total,
                         filamentos=filamentos, miniatura_rel=rel)


def mesclar_estado(estado: dict, status: dict) -> dict:
    objetos = {k: dict(v) for k, v in (estado.get("objetos") or {}).items()}
    for nome, campos in (status or {}).items():
        objetos.setdefault(nome, {}).update(campos or {})
    ps, ds, sd = objetos.get("print_stats", {}), objetos.get("display_status", {}), objetos.get("virtual_sdcard", {})
    ext, mesa = objetos.get("extruder", {}), objetos.get("heater_bed", {})
    progresso = ds.get("progress", sd.get("progress"))
    duracao = ps.get("print_duration")
    restante = None
    if progresso and duracao and ps.get("state") == "printing":
        restante = round(duracao / progresso - duracao)
    return {"objetos": objetos, "estado": ps.get("state"), "arquivo": ps.get("filename"), "progresso": progresso,
            "duracao_s": duracao, "restante_s": restante, "bico": ext.get("temperature"), "bico_alvo": ext.get("target"),
            "mesa": mesa.get("temperature"), "mesa_alvo": mesa.get("target")}


def publico(estado: dict | None) -> dict | None:
    return None if estado is None else {k: v for k, v in estado.items() if k != "objetos"}


def ws_url(url: str) -> str:
    return url.rstrip("/").replace("https://", "wss://", 1).replace("http://", "ws://", 1) + "/websocket"


def _cabecalhos(chave: str | None) -> dict:
    return {"X-Api-Key": chave} if chave else {}


def listar_historico(url: str, chave: str | None, limite: int) -> list[dict]:
    r = httpx.get(f"{url.rstrip('/')}/server/history/list", params={"limit": limite, "order": "desc"},
                  headers=_cabecalhos(chave), timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()["result"]["jobs"]


def buscar_job(url: str, chave: str | None, job_id: str) -> dict:
    r = httpx.get(f"{url.rstrip('/')}/server/history/job", params={"uid": job_id}, headers=_cabecalhos(chave),
                  timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()["result"]["job"]


def baixar(url: str, chave: str | None, caminho_gcodes: str) -> bytes | None:
    try:
        r = httpx.get(f"{url.rstrip('/')}/server/files/gcodes/{caminho_gcodes}", headers=_cabecalhos(chave),
                      timeout=TIMEOUT)
        return r.content if r.status_code == 200 else None
    except httpx.HTTPError:
        return None


def comando(url: str, chave: str | None, caminho: str, params: dict | None = None) -> dict:
    r = httpx.post(f"{url.rstrip('/')}{caminho}", params=params, headers=_cabecalhos(chave), timeout=15)
    r.raise_for_status()
    return r.json()


def estado_impressao(url: str, chave: str | None) -> str:
    r = httpx.get(f"{url.rstrip('/')}/printer/objects/query", params={"print_stats": "state"},
                  headers=_cabecalhos(chave), timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()["result"]["status"]["print_stats"]["state"]


def enviar_e_imprimir(url: str, chave: str | None, nome: str, caminho: Path) -> dict:
    with caminho.open("rb") as f:
        r = httpx.post(f"{url.rstrip('/')}/server/files/upload", files={"file": (nome, f, "application/octet-stream")},
                       data={"print": "true"}, headers=_cabecalhos(chave), timeout=300)
    r.raise_for_status()
    return r.json()

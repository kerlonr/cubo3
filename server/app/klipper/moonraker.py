"""Leitura dos dados do Moonraker (API do Klipper): histórico, estado ao vivo e arquivos."""
import json
import posixpath
import time
from urllib.parse import quote, urlsplit
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


def _pct(fator) -> int | None:
    return None if fator is None else round(fator * 100)


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
    th, gm, fan = objetos.get("toolhead", {}), objetos.get("gcode_move", {}), objetos.get("fan", {})
    return {"objetos": objetos, "estado": ps.get("state"), "arquivo": ps.get("filename"), "progresso": progresso,
            "duracao_s": duracao, "restante_s": restante, "bico": ext.get("temperature"), "bico_alvo": ext.get("target"),
            "mesa": mesa.get("temperature"), "mesa_alvo": mesa.get("target"),
            "posicao": [round(v, 3) for v in th.get("position", [])[:3]] or None,
            "eixos_home": th.get("homed_axes", ""),
            "velocidade_pct": _pct(gm.get("speed_factor")), "fluxo_pct": _pct(gm.get("extrude_factor")),
            "z_offset": (gm.get("homing_origin") or [None] * 3)[2], "ventoinha_pct": _pct(fan.get("speed")),
            "mensagem": ds.get("message")}


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
        r = httpx.get(f"{url.rstrip('/')}/server/files/gcodes/{quote(caminho_gcodes, safe='/')}",
                      headers=_cabecalhos(chave),
                      timeout=TIMEOUT)
        return r.content if r.status_code == 200 else None
    except httpx.HTTPError:
        return None


class ErroKlipper(Exception):
    """O Klipper recebeu e recusou (ex.: "Must home axis first"): a mensagem dele vai para o app."""


def comando(url: str, chave: str | None, caminho: str, params: dict | None = None) -> dict:
    r = httpx.post(f"{url.rstrip('/')}{caminho}", params=params, headers=_cabecalhos(chave), timeout=60)
    if 400 <= r.status_code < 500:
        try:
            mensagem = r.json()["error"]["message"]
        except (ValueError, KeyError, TypeError):
            mensagem = r.text[:200]
        raise ErroKlipper(mensagem)
    r.raise_for_status()
    return r.json()


def listar_arquivos(url: str, chave: str | None) -> list[dict]:
    # shortcut: só a raiz de gcodes (subpastas ignoradas); aprofundar se o Kerlon usar pastas.
    r = httpx.get(f"{url.rstrip('/')}/server/files/directory", params={"path": "gcodes", "extended": "true"},
                  headers=_cabecalhos(chave), timeout=15)
    r.raise_for_status()
    return r.json()["result"]["files"]


def listar_macros(url: str, chave: str | None) -> list[str]:
    r = httpx.get(f"{url.rstrip('/')}/printer/objects/list", headers=_cabecalhos(chave), timeout=TIMEOUT)
    r.raise_for_status()
    return [o.split(" ", 1)[1] for o in r.json()["result"]["objects"]
            if o.startswith("gcode_macro ") and not o.split(" ", 1)[1].startswith("_")]


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


def urls_webcam(url: str, webcams: list[dict]) -> dict | None:
    """Endereços da primeira câmera ligada; os relativos (crowsnest) ficam no host da impressora, porta 80."""
    cam = next((w for w in webcams if w.get("enabled", True)), None)
    if cam is None or not cam.get("stream_url"):
        return None
    p = urlsplit(url)
    base = f"{p.scheme}://{p.hostname}"
    resolver = lambda u: u if u.startswith("http") else base + u
    return {"foto": resolver(cam.get("snapshot_url") or cam["stream_url"]), "video": resolver(cam["stream_url"])}


_cache_webcam: dict[str, tuple[float, dict | None]] = {}


def webcam(url: str, chave: str | None) -> dict | None:
    agora_s = time.monotonic()
    if url in _cache_webcam and agora_s - _cache_webcam[url][0] < 300:
        return _cache_webcam[url][1]
    r = httpx.get(f"{url.rstrip('/')}/server/webcams/list", headers=_cabecalhos(chave), timeout=TIMEOUT)
    r.raise_for_status()
    cam = urls_webcam(url, r.json()["result"]["webcams"])
    _cache_webcam[url] = (agora_s, cam)
    return cam


def foto(url_foto: str) -> bytes:
    r = httpx.get(url_foto, timeout=TIMEOUT)
    r.raise_for_status()
    return r.content


async def abrir_video(url_video: str):
    """Abre o MJPEG da câmera: (content-type, iterador de pedaços, função que fecha a conexão)."""
    cliente = httpx.AsyncClient(timeout=httpx.Timeout(10, read=None))
    try:
        resp = await cliente.send(cliente.build_request("GET", url_video), stream=True)
        resp.raise_for_status()
    except Exception:
        await cliente.aclose()
        raise

    async def fechar():
        await resp.aclose()
        await cliente.aclose()

    return resp.headers.get("content-type", "multipart/x-mixed-replace"), resp.aiter_raw(), fechar

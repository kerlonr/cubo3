"""Uma conexão WebSocket por impressora com o Moonraker; reconecta sozinha."""
import asyncio
import json
import logging
import time
import uuid
from typing import Callable

import websockets
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.ao_vivo import Hub, hub
from app.empresa.modelos import Impressora
from app.klipper import moonraker
from app.klipper.servico import registrar_trabalho

log = logging.getLogger("cubo3.klipper")
OBJETOS = {"print_stats": None, "display_status": None, "virtual_sdcard": None, "extruder": None, "heater_bed": None}
INTERVALO_PUBLICACAO_S = 2


class Monitor:
    def __init__(self, impressora_id: uuid.UUID, empresa_id: uuid.UUID, url: str, api_key: str | None,
                 sessoes: Callable[[], Session], hub: Hub):
        self.impressora_id, self.empresa_id, self.url, self.api_key = impressora_id, empresa_id, url, api_key
        self.sessoes, self.hub = sessoes, hub
        self.estado: dict | None = None
        self._ultima_publicacao = 0.0

    def _publicar_estado(self) -> None:
        self._ultima_publicacao = time.monotonic()
        self.hub.publicar(self.empresa_id, {"tipo": "estado", "impressora_id": str(self.impressora_id),
                                            **moonraker.publico(self.estado)})

    def _atualizar(self, status: dict, forcar: bool = False) -> None:
        anterior = (self.estado or {}).get("estado")
        self.estado = moonraker.mesclar_estado(self.estado or {}, status)
        if forcar or self.estado["estado"] != anterior or \
                time.monotonic() - self._ultima_publicacao >= INTERVALO_PUBLICACAO_S:
            self._publicar_estado()

    def _registrar(self, job: dict) -> None:
        with self.sessoes() as db:
            i = registrar_trabalho(db, self.empresa_id, self.impressora_id, moonraker.trabalho_de_historico(job))
            db.commit()
            if i is not None and i.status == "a_confirmar":
                self.hub.publicar(self.empresa_id, {"tipo": "impressao_terminou", "impressao_id": str(i.id),
                                                    "impressora_id": str(self.impressora_id), "arquivo": i.arquivo,
                                                    "situacao": i.situacao_klipper})

    async def _sessao(self, ws) -> None:
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "server.connection.identify", "params": {
            "client_name": "cubo3", "version": "1.0", "type": "other", "url": "https://cubo3.kerlonr.com.br"}}))
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "printer.objects.subscribe",
                                  "params": {"objects": OBJETOS}}))
        async for bruto in ws:
            msg = json.loads(bruto)
            metodo = msg.get("method")
            if msg.get("id") == 2 and isinstance(msg.get("result"), dict):
                self._atualizar(msg["result"].get("status", {}), forcar=True)
            elif metodo == "notify_status_update":
                self._atualizar(msg["params"][0])
            elif metodo == "notify_history_changed":
                p = msg["params"][0]
                if p.get("action") == "finished":
                    await asyncio.to_thread(self._registrar, p["job"])
            elif metodo in ("notify_klippy_disconnected", "notify_klippy_shutdown"):
                self._atualizar({"print_stats": {"state": "desligada"}}, forcar=True)

    async def rodar(self) -> None:
        espera = 2
        while True:
            try:
                cab = {"X-Api-Key": self.api_key} if self.api_key else None
                async with websockets.connect(moonraker.ws_url(self.url), additional_headers=cab,
                                              max_size=4 * 1024 * 1024, open_timeout=10) as ws:
                    espera = 2
                    await self._sessao(ws)
            except asyncio.CancelledError:
                raise
            except Exception as e:  # rede, Moonraker reiniciando, JSON inesperado: tenta de novo
                log.warning("impressora %s: %s", self.impressora_id, e)
            self.estado = {"estado": "desconectada"}
            self._publicar_estado()
            await asyncio.sleep(espera)
            espera = min(espera * 2, 60)


class GerenciadorMonitores:
    def __init__(self, hub: Hub):
        self.hub = hub
        self.loop: asyncio.AbstractEventLoop | None = None
        self.sessoes: Callable[[], Session] | None = None
        self._monitores: dict[uuid.UUID, tuple[Monitor, asyncio.Task]] = {}

    async def iniciar_todos(self, sessoes: Callable[[], Session]) -> None:
        self.loop, self.sessoes = asyncio.get_running_loop(), sessoes
        with sessoes() as db:
            for imp in db.scalars(select(Impressora).where(Impressora.moonraker_url.is_not(None),
                                                           Impressora.excluido.is_(False))):
                self._iniciar(_dados(imp))

    def _iniciar(self, d: dict) -> None:
        self._parar(d["id"])
        if d["url"] and not d["excluido"]:
            m = Monitor(d["id"], d["empresa_id"], d["url"], d["api_key"], self.sessoes, self.hub)
            self._monitores[d["id"]] = (m, self.loop.create_task(m.rodar()))

    def _parar(self, impressora_id) -> None:
        if (par := self._monitores.pop(impressora_id, None)) is not None:
            par[1].cancel()

    def reiniciar(self, imp: Impressora) -> None:
        """Chamado pelas rotas (threadpool) quando a impressora muda ou é excluída."""
        if self.loop is not None:
            self.loop.call_soon_threadsafe(self._iniciar, _dados(imp))

    async def parar_todos(self) -> None:
        for impressora_id in list(self._monitores):
            self._parar(impressora_id)

    def estado(self, impressora_id) -> dict | None:
        par = self._monitores.get(impressora_id)
        return moonraker.publico(par[0].estado) if par else None

    def estados_da_empresa(self, empresa_id) -> list[dict]:
        return [{"tipo": "estado", "impressora_id": str(i), **moonraker.publico(m.estado)}
                for i, (m, _) in self._monitores.items() if m.empresa_id == empresa_id and m.estado]


def _dados(imp: Impressora) -> dict:
    return {"id": imp.id, "empresa_id": imp.empresa_id, "url": imp.moonraker_url, "api_key": imp.api_key,
            "excluido": imp.excluido}


monitores = GerenciadorMonitores(hub)

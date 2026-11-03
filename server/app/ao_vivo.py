"""Eventos ao vivo por empresa (estado da impressora, fim de impressão) para o app via WebSocket."""
import asyncio
import uuid


class Hub:
    def __init__(self) -> None:
        self._filas: dict[uuid.UUID, set[tuple[asyncio.AbstractEventLoop, asyncio.Queue]]] = {}

    def conectar(self, empresa_id: uuid.UUID) -> tuple[asyncio.AbstractEventLoop, asyncio.Queue]:
        par = (asyncio.get_running_loop(), asyncio.Queue(maxsize=100))
        self._filas.setdefault(empresa_id, set()).add(par)
        return par

    def desconectar(self, empresa_id: uuid.UUID, par) -> None:
        self._filas.get(empresa_id, set()).discard(par)

    def publicar(self, empresa_id: uuid.UUID, evento: dict) -> None:
        """Pode ser chamado de qualquer thread (rotas síncronas rodam no threadpool)."""
        for loop, fila in list(self._filas.get(empresa_id, ())):
            loop.call_soon_threadsafe(_colocar, fila, evento)


def _colocar(fila: asyncio.Queue, evento: dict) -> None:
    if fila.full():
        fila.get_nowait()  # cliente lento: descarta o mais antigo em vez de travar
    fila.put_nowait(evento)


hub = Hub()

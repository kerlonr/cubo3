import asyncio
import uuid

import httpx
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.ao_vivo import hub
from app.auth.deps import Ctx, ctx, papel_na_empresa, usuario_do_token
from app.crud import obter
from app.db import get_db
from app.empresa.modelos import Impressora
from app.impressoes.modelos import Impressao
from app.impressoes.rotas import saida_impressao
from app.klipper import moonraker
from app.klipper.monitor import monitores
from app.klipper.servico import ja_registrado, registrar_trabalho

rotas = APIRouter(prefix="/api", tags=["klipper"])


def _com_moonraker(db: Session, c: Ctx, id: uuid.UUID) -> Impressora:
    imp = obter(db, c, Impressora, id, "Impressora")
    if not imp.moonraker_url:
        raise HTTPException(422, "Impressora sem endereço do Klipper (Moonraker)")
    return imp


@rotas.get("/impressoras/{id}/ao-vivo")
def ao_vivo_impressora(id: uuid.UUID, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = obter(db, c, Impressora, id, "Impressora")
    return monitores.estado(imp.id) or {"estado": "desconectada" if imp.moonraker_url else "sem_integracao"}


@rotas.get("/impressoras/{id}/historico")
def historico(id: uuid.UUID, limite: int = 50, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    try:
        jobs = moonraker.listar_historico(imp.moonraker_url, imp.api_key, min(max(limite, 1), 200))
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")
    trazidos = set(db.scalars(select(Impressao.job_id).where(Impressao.impressora_id == imp.id)))
    saida = []
    for job in jobs:
        d = moonraker.trabalho_de_historico(job)
        saida.append({"job_id": d.job_id, "arquivo": d.arquivo, "status": d.status,
                      "fim": d.fim.isoformat() if d.fim else None, "duracao_s": d.duracao_s,
                      "gramas_total": d.gramas_total, "filamentos": d.filamentos, "ja_trazido": d.job_id in trazidos})
    return saida


@rotas.post("/impressoras/{id}/historico/{job_id}/trazer")
def trazer(id: uuid.UUID, job_id: str, c: Ctx = Depends(ctx), db: Session = Depends(get_db)):
    imp = _com_moonraker(db, c, id)
    if (existente := ja_registrado(db, imp.id, job_id)) is not None:
        return saida_impressao(db, existente)
    try:
        job = moonraker.buscar_job(imp.moonraker_url, imp.api_key, job_id)
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "A impressora não respondeu")
    i = registrar_trabalho(db, c.empresa_id, imp.id, moonraker.trabalho_de_historico(job), arquivada=True)
    db.commit()
    return saida_impressao(db, i)


@rotas.websocket("/ao-vivo")
async def ao_vivo(ws: WebSocket, token: str = "", empresa: str = "", db: Session = Depends(get_db)):
    try:
        usuario = usuario_do_token(db, token)
    except HTTPException:
        await ws.close(code=4401)
        return
    try:
        empresa_id = uuid.UUID(empresa)
        membro = papel_na_empresa(db, usuario.id, empresa_id) is not None
    except ValueError:
        membro = False
    db.close()  # não segura conexão do banco enquanto o WebSocket fica aberto
    if not membro:
        await ws.close(code=4403)
        return
    await ws.accept()
    par = hub.conectar(empresa_id)
    leitor = asyncio.create_task(ws.receive_text())
    try:
        for estado in monitores.estados_da_empresa(empresa_id):
            await ws.send_json(estado)
        while True:
            pega = asyncio.create_task(par[1].get())
            feitos, _ = await asyncio.wait({pega, leitor}, return_when=asyncio.FIRST_COMPLETED)
            if leitor in feitos:
                pega.cancel()
                if leitor.exception() is not None:
                    break
                leitor = asyncio.create_task(ws.receive_text())  # cliente mandou "ping": ignora
                continue
            await ws.send_json(pega.result())
    except WebSocketDisconnect:
        pass
    finally:
        leitor.cancel()
        hub.desconectar(empresa_id, par)

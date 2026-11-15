"""SeguWatts — vitrine dos componentes do MVP (Global Solution 2026.2).

A aplicação apresenta os projetos de cada disciplina e expõe:
  /              página de apresentação (renderizada no servidor, funciona sem JS)
  /api/projetos  conteúdo em JSON
  /api/status    versão publicada e tempo no ar
  /healthz       verificação de vida usada pelo Docker e pela nuvem
  /metrics       métricas Prometheus (protegidas por token quando METRICS_TOKEN existe)
"""

import hmac
import json
import os
import time
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from app.metricas import INFO, MiddlewareMetricas

BASE = Path(__file__).resolve().parent
VERSAO = os.getenv("GIT_SHA", "dev")
AMBIENTE = os.getenv("AMBIENTE", "local")
DEMO_FALHAS = os.getenv("DEMO_FALHAS", "false").lower() in {"1", "true", "sim"}
INICIO = time.time()

INFO.labels(VERSAO[:7], AMBIENTE).set(1)

CABECALHOS_SEGURANCA = {
    "Content-Security-Policy": (
        "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; "
        "font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; "
        "form-action 'none'; object-src 'none'"
    ),
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
    "Cross-Origin-Opener-Policy": "same-origin",
}


@lru_cache(maxsize=1)
def carregar_conteudo() -> dict:
    with open(BASE / "data" / "projetos.json", encoding="utf-8") as arquivo:
        return json.load(arquivo)


app = FastAPI(
    title="SeguWatts — vitrine do MVP",
    version=VERSAO,
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)
app.add_middleware(MiddlewareMetricas)
app.mount("/static", StaticFiles(directory=BASE / "static"), name="static")
templates = Jinja2Templates(directory=BASE / "templates")


@app.middleware("http")
async def aplicar_cabecalhos(request: Request, call_next):
    resposta = await call_next(request)
    for nome, valor in CABECALHOS_SEGURANCA.items():
        resposta.headers.setdefault(nome, valor)
    if request.url.path.startswith("/static/"):
        resposta.headers["Cache-Control"] = "public, max-age=86400"
    return resposta


def status_atual() -> dict:
    return {
        "versao": VERSAO[:7],
        "ambiente": AMBIENTE,
        "no_ar_desde": datetime.fromtimestamp(INICIO, tz=timezone.utc).isoformat(),
        "segundos_no_ar": int(time.time() - INICIO),
    }


@app.get("/", response_class=HTMLResponse)
def inicio(request: Request):
    return templates.TemplateResponse(
        request,
        "index.html",
        {"c": carregar_conteudo(), "status": status_atual()},
    )


@app.get("/api/projetos")
def projetos():
    return carregar_conteudo()


@app.get("/api/projetos/{slug}")
def projeto(slug: str):
    for item in carregar_conteudo()["componentes"]:
        if item["slug"] == slug:
            return item
    raise HTTPException(status_code=404, detail="Componente não encontrado. Veja /api/projetos.")


@app.get("/api/status")
def status():
    return status_atual()


@app.get("/healthz")
def healthz():
    return {"status": "ok", "versao": VERSAO[:7]}


@app.get("/api/demo/falha")
def demo_falha():
    """Gera erro 500 de propósito para disparar o alerta de taxa de erros na demonstração.

    Só existe quando DEMO_FALHAS=true; em produção, por padrão, responde 404.
    """
    if not DEMO_FALHAS:
        raise HTTPException(status_code=404, detail="Não encontrado.")
    return JSONResponse({"erro": "falha simulada para teste de alerta"}, status_code=500)


@app.get("/metrics")
def metrics(request: Request):
    token = os.getenv("METRICS_TOKEN", "")
    if token:
        enviado = request.headers.get("authorization", "")
        if not hmac.compare_digest(enviado.encode(), f"Bearer {token}".encode()):
            raise HTTPException(status_code=401, detail="Token de métricas inválido.")
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

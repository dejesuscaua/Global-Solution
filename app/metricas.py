"""Métricas Prometheus das quatro métricas de ouro (latência, tráfego, erros e saturação)."""

import time

from prometheus_client import Counter, Gauge, Histogram
from starlette.types import ASGIApp, Message, Receive, Scope, Send

REQUISICOES = Counter(
    "seguwatts_http_requests_total",
    "Requisições HTTP atendidas (tráfego e erros).",
    ["metodo", "rota", "status"],
)
DURACAO = Histogram(
    "seguwatts_http_request_duration_seconds",
    "Tempo de resposta das requisições HTTP (latência).",
    ["metodo", "rota"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
EM_ANDAMENTO = Gauge(
    "seguwatts_http_requests_in_progress",
    "Requisições sendo processadas agora (saturação).",
)
INFO = Gauge(
    "seguwatts_build_info",
    "Versão publicada da aplicação.",
    ["versao", "ambiente"],
)

ROTAS_IGNORADAS = {"/metrics"}


class MiddlewareMetricas:
    """Mede cada requisição usando o molde da rota (ex.: /api/projetos/{slug}).

    Usar o molde, e não o caminho literal, evita explosão de cardinalidade
    quando alguém varre URLs inexistentes.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["path"] in ROTAS_IGNORADAS:
            await self.app(scope, receive, send)
            return

        status = {"codigo": 500}

        async def send_com_status(message: Message) -> None:
            if message["type"] == "http.response.start":
                status["codigo"] = message["status"]
            await send(message)

        inicio = time.perf_counter()
        EM_ANDAMENTO.inc()
        try:
            await self.app(scope, receive, send_com_status)
        finally:
            EM_ANDAMENTO.dec()
            rota = scope.get("route")
            molde = getattr(rota, "path", None) or "nao_encontrada"
            metodo = scope["method"]
            DURACAO.labels(metodo, molde).observe(time.perf_counter() - inicio)
            REQUISICOES.labels(metodo, molde, str(status["codigo"])).inc()

# syntax=docker/dockerfile:1
# ---------- Etapa 1: instala dependências em um prefixo isolado ----------
FROM python:3.13-slim AS dependencias
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- Etapa 2: imagem final enxuta, sem pip, sem compilador, sem segredo ----------
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Atualiza pacotes do sistema (corrige CVEs da imagem base), cria usuário sem privilégios
# e remove o pip, que não é necessário em execução e só aumenta a superfície de ataque.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app \
 && python -m pip uninstall -y pip

WORKDIR /srv
COPY --from=dependencias /install /usr/local
# Código pertence ao root e é somente leitura para o usuário da aplicação.
COPY app ./app

ARG GIT_SHA=dev
ENV GIT_SHA=${GIT_SHA}

USER 10001:10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*", "--no-server-header"]

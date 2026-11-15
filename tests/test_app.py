import importlib

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def cliente(monkeypatch):
    monkeypatch.delenv("METRICS_TOKEN", raising=False)
    monkeypatch.delenv("DEMO_FALHAS", raising=False)
    import app.main as main

    importlib.reload(main)
    return TestClient(main.app)


def test_pagina_inicial_mostra_todos_os_componentes(cliente):
    r = cliente.get("/")
    assert r.status_code == 200
    for nome in ["EcoBot", "SeguWatts Vision", "Pipeline SeguWatts", "Energia Clara", "Alertas SeguWatts", "Deploy Blindado"]:
        assert nome in r.text


def test_cabecalhos_de_seguranca(cliente):
    r = cliente.get("/")
    assert "default-src 'self'" in r.headers["content-security-policy"]
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"
    assert "max-age" in r.headers["strict-transport-security"]


def test_api_projetos_e_detalhe(cliente):
    dados = cliente.get("/api/projetos").json()
    assert len(dados["componentes"]) == 6
    assert cliente.get("/api/projetos/dados").json()["nome"] == "Pipeline SeguWatts"
    assert cliente.get("/api/projetos/inexistente").status_code == 404


def test_healthz_e_status(cliente):
    assert cliente.get("/healthz").json()["status"] == "ok"
    status = cliente.get("/api/status").json()
    assert {"versao", "ambiente", "segundos_no_ar"} <= status.keys()


def test_metricas_registram_rota_pelo_molde(cliente):
    cliente.get("/api/projetos/visao")
    cliente.get("/nao-existe-123")
    corpo = cliente.get("/metrics").text
    assert 'rota="/api/projetos/{slug}"' in corpo
    assert 'rota="nao_encontrada"' in corpo
    assert "/nao-existe-123" not in corpo
    assert "seguwatts_http_requests_in_progress" in corpo


def test_metricas_exigem_token_quando_configurado(monkeypatch):
    monkeypatch.setenv("METRICS_TOKEN", "token-de-teste")
    import app.main as main

    c = TestClient(main.app)
    assert c.get("/metrics").status_code == 401
    assert c.get("/metrics", headers={"Authorization": "Bearer errado"}).status_code == 401
    assert c.get("/metrics", headers={"Authorization": "Bearer token-de-teste"}).status_code == 200


def test_falha_simulada_desligada_por_padrao(cliente):
    assert cliente.get("/api/demo/falha").status_code == 404


def test_falha_simulada_quando_ligada(monkeypatch):
    monkeypatch.setenv("DEMO_FALHAS", "true")
    import app.main as main

    importlib.reload(main)
    assert TestClient(main.app).get("/api/demo/falha").status_code == 500

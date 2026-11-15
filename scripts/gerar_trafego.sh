#!/usr/bin/env bash
# Gera tráfego na aplicação para popular o painel do Grafana e, opcionalmente,
# disparar o alerta TaxaDeErrosAlta.
#
#   ./scripts/gerar_trafego.sh                         # tráfego normal no local
#   ./scripts/gerar_trafego.sh --com-falhas            # ~30% de erros 500 (dispara o alerta)
#   URL=https://seu-app.azurecontainerapps.io ./scripts/gerar_trafego.sh
set -euo pipefail

URL="${URL:-http://127.0.0.1:8000}"
DURACAO="${DURACAO:-300}"   # segundos
COM_FALHAS=false
[[ "${1:-}" == "--com-falhas" ]] && COM_FALHAS=true

rotas=("/" "/api/projetos" "/api/status" "/api/projetos/dados" "/api/projetos/visao" "/healthz" "/rota-que-nao-existe")
fim=$(( $(date +%s) + DURACAO ))
echo "Gerando tráfego em ${URL} por ${DURACAO}s (falhas: ${COM_FALHAS}). Ctrl+C para parar."

while (( $(date +%s) < fim )); do
  for rota in "${rotas[@]}"; do
    curl -s -o /dev/null -w "%{http_code} ${rota}\n" "${URL}${rota}" &
  done
  if $COM_FALHAS; then
    for _ in 1 2 3; do curl -s -o /dev/null -w "%{http_code} /api/demo/falha\n" "${URL}/api/demo/falha" & done
  fi
  wait
  sleep 0.5
done

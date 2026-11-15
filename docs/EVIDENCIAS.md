# Roteiro de evidências (PDF da disciplina)

O PDF único deve trazer links clicáveis (URL pública, repositório, execuções do Actions) e os prints abaixo. A coluna **Pontos** segue a rubrica de 14 pontos da disciplina.

## Checklist de prints

| # | Print | Onde tirar | Pontos |
|---|---|---|---|
| 1 | Dockerfile (multi-stage, `USER 10001`, sem pip) | GitHub, arquivo `Dockerfile` | Container 2,0 |
| 2 | `docker compose ps` com os 5 serviços *Up* e o app *healthy* | terminal | Container 2,0 |
| 3 | `docker run --rm --entrypoint id <imagem>` mostrando `uid=10001(app)` | terminal | Container 2,0 |
| 4 | `./scripts/azure_setup.sh` concluído (apply e URL pública) | Cloud Shell | IaC 3,0 |
| 5 | Resource group no Portal Azure com os recursos criados pelo Terraform | portal.azure.com | IaC 3,0 |
| 6 | Web App: *HTTPS Only: On*, TLS mínimo 1.2, FTP desligado e *Advanced tool site (SCM)* com regra padrão **Deny** (nenhuma porta de administração aberta) | Portal → Web App → Configuration e Networking → Access restrictions | IaC 3,0 |
| 7 | `.gitignore` mostrando `*.tfstate` e `*.tfvars`, e o state no Azure Storage | GitHub + Portal | IaC 3,0 |
| 8 | Execução **barrada** pelo pipeline (ver roteiro abaixo) | GitHub → Actions | Pipeline 4,0 |
| 9 | Execução **corrigida**, toda verde, com deploy e smoke test | GitHub → Actions | Pipeline 4,0 |
| 10 | Variables do repositório (sem nenhum secret do Azure) e a federated credential da identidade `id-seguwatts-deploy` | GitHub Settings → Secrets and variables; Portal → Managed Identities → Federated credentials | Pipeline 4,0 |
| 11 | Página pública no ar mostrando o SHA do último commit em "Versão publicada" | navegador | Pipeline 4,0 |
| 12 | Painel Grafana "SeguWatts · Métricas de ouro" com o ambiente `seguwatts-producao` | http://127.0.0.1:3000 | Observabilidade 3,0 |
| 13 | Alerta `TaxaDeErrosAlta` em *Firing* no Prometheus | http://127.0.0.1:9090/alerts | Observabilidade 3,0 |
| 14 | Log do notificador recebendo o webhook do Alertmanager | `docker compose logs notificador` | Observabilidade 3,0 |
| 15 | Diagrama de arquitetura, responsabilidade compartilhada, LGPD e custo | README | Documentação 2,0 |

## Execução barrada e execução corrigida

Faça a demonstração em uma branch separada, para não sujar a `main`. O pipeline roda em qualquer branch, mas só a `main` faz deploy.

### Opção A: segredo vazado (Gitleaks)

```bash
git switch -c demo/segredo-vazado
# Token falso com o formato de um token do GitHub (36 caracteres aleatórios depois de ghp_)
echo "GITHUB_TOKEN=ghp_$(openssl rand -hex 18)" > app/config_local.py
git add app/config_local.py
git commit -m "demo: credencial esquecida no código"
git push -u origin demo/segredo-vazado
```

O job **Segredos (Gitleaks)** falha, aponta o arquivo e a linha, e o build e o deploy nem começam. **Print 8.**

Correção:

```bash
git rm app/config_local.py
git commit -m "fix: remove credencial do código"
git push
```

Explique no PDF que, na vida real, um segredo vazado precisa ser **revogado** imediatamente: apagar o arquivo não apaga o histórico. O novo push passa porque o Gitleaks analisa os commits enviados naquele push. **Print 9** (ou faça o merge da correção na `main` para mostrar também o deploy).

### Opção B: biblioteca vulnerável (Trivy)

```bash
git switch -c demo/dependencia-vulneravel
echo "requests==2.19.1" >> requirements.txt
git commit -am "demo: adiciona biblioteca desatualizada"
git push -u origin demo/dependencia-vulneravel
```

O job **Imagem (build + Trivy)** falha listando as CVEs HIGH do `requests 2.19.1`. Para corrigir, troque por uma versão atual (ou remova a linha), faça commit e push, e a execução fica verde.

### Opção C: código inseguro (Semgrep)

Adicione em `app/main.py` uma rota com `subprocess.run(cmd, shell=True)` recebendo parâmetro da URL. O job **Código (Semgrep)** falha com a regra de injeção de comando. Remova a rota e o pipeline volta a passar.

> Para a nota, uma execução barrada e uma corrigida bastam. Mostrar duas barreiras diferentes (A e B) reforça que o pipeline barra tanto segredo quanto vulnerabilidade.

## Links para colar no PDF

- URL pública do MVP: `https://seguwatts-xxxxxx.azurewebsites.net`
- Repositório: https://github.com/dejesuscaua/Global-Solution
- Execução barrada: `https://github.com/dejesuscaua/Global-Solution/actions/runs/<id>`
- Execução corrigida com deploy: `https://github.com/dejesuscaua/Global-Solution/actions/runs/<id>`
- Pacote da imagem: https://github.com/dejesuscaua/Global-Solution/pkgs/container/global-solution

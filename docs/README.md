# docs/ — the-lab-zone

Documentação estruturada do homelab `the-lab-zone`, migrada do `BOOTSTRAP.md` monolítico
(3711 linhas) para três gêneros distintos. A separação existe porque cada gênero responde a
uma pergunta diferente — e porque o indexador RAG (`DOC_GLOBS: docs/**/*.md`) recupera melhor
quando cada arquivo é coeso.

## Os três gêneros

| Diretório | Gênero | Responde à pergunta | Formato |
|---|---|---|---|
| `decisions/` | **ADR** (Architecture Decision Record) | *Por que* a coisa é assim? | Nygard (contexto → decisão → consequências), numerado `NNNN-` |
| `runbooks/` | **Runbook por domínio** | *Quebrou — e agora?* | `Sintoma → Causa → Diagnóstico → Fix → Lição`, agrupado por componente |
| `setup/` | **Setup por fase** | *Como instalar/refazer?* | Procedimento + critério de saída, por fase do bootstrap |

Como navegar:
- **"Por que escolhemos X?"** → `decisions/` (índice em `decisions/README.md`).
- **"Tô vendo o sintoma Y"** → `runbooks/INDEX.md` (busca por sintoma → runbook).
- **"Quero reconstruir a fase Z"** → `setup/` (ordenado `00`→`10` + `99-apendices`).

Front-matter YAML em todo arquivo (`tipo`, `componente`/`fase`, `tags`, `fases`,
`relacionado`) alimenta o indexador. Tudo em PT-BR.

## Lições transversais (valem em todo o cluster)

1. **Status verde é promessa; a prova é ler o destino.** Bucket info (não
   `ContinuousArchiving`), arping/nc (não o lease migrar), target em `/api/v1/targets` (não o
   CR `operational`), série no banco (não o "0 differences" do `rclone check`). Foi a lição
   da Fase 10 inteira, mas é universal.
2. **VM operator não materializa recurso novo → restart.** Aconteceu ≥3x em fases diferentes
   (scrape, rule, config). Recurso VM correto que "não aparece" → reiniciar o operator (ou o
   vmagent) é o primeiro reflexo, não o último.
3. **Default-deny de CNP é POR APP, com audit ON antes.** Cross-namespace exige
   `io.kubernetes.pod.namespace`; origem ingress usa `fromEntities`; ordem audit ON →
   confirmar Enabled → aplicar baseline. Hubble flow (`--verdict DROPPED`) é a fonte da
   verdade, não timeline de Jobs.
4. **Goose/agentes:** desligar extensions platform, só MCPs. `Ready` do ToolHive ≠ backend
   alcançável cross-pod.
5. **Agentes são read-only e só propõem via PR** (ADR-0015) — nunca mutam o cluster.
6. **Chave de Helm inexistente falha em silêncio.** `helm template | rg` o campo crítico
   antes de confiar (causa raiz do backup fantasma do CNPG por 10 dias).

## Mapa de fases

| Fase | Tema | Setup | Runbooks principais |
|---|---|---|---|
| 0–1 | Pré-req + Talos no Proxmox | `setup/00`, `setup/01` | talos |
| 2 | GitOps core (Cilium, ArgoCD, ESO) | `setup/02` | gitops-argocd, secrets-eso, cilium-rede |
| 3 | Ingress TLS (Gateway, cert, DNS) | `setup/03` | gateway-dns, cilium-rede |
| 4 | Storage LocalPV | `setup/04` | storage |
| 5 | Observabilidade (VM stack) | `setup/05` | observability |
| 6 | Plataforma de dados (6 stores) | `setup/06` | data-platform |
| 7 | Stack de IA (MCP, GPU, Ollama) | `setup/07` | toolhive-mcp, gpu |
| 8 | Analytics/ELT (Argo, dbt, goose) | `setup/08` | argo-workflows |
| 9 | SSO + Network Policies | `setup/09` | sso-authentik, network-policies |
| 10 | DR (off-site, Velero, Barman) | `setup/10` | backup-dr |

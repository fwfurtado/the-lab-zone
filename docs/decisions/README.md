# ADRs — Decisões de arquitetura

Decisões registradas no formato Nygard (contexto → decisão → consequências). Cada ADR captura
*por que* uma escolha foi feita, pra que ela não seja revertida por esquecimento.

| # | Decisão | Fase | Resumo |
|---|---|---|---|
| [0001](0001-gitops-puro-argocd-app-of-apps.md) | GitOps puro via ArgoCD (app-of-apps) | 2 | Nada instalado à mão após a Fase 2; DR aplica o estado final, não reexecuta a história |
| [0002](0002-admin-local-argocd-sempre-habilitado.md) | Admin local do ArgoCD sempre habilitado | 2, 9 | SSO é conveniência; admin local é a porta de emergência do DR |
| [0003](0003-divisao-vaults-1password.md) | Divisão de vaults no 1Password | 2 | `homelab` (bootstrap/humano) vs `the-lab-zone` (runtime/ESO); Connect só vê o de runtime |
| [0004](0004-gateway-api-canal-experimental.md) | Gateway API canal experimental | 3 | Cilium 1.19 indexa TLSRoute em v1alpha2 (só no experimental); CRDs vendorizados |
| [0005](0005-split-horizon-powerdns.md) | DNS split-horizon com PowerDNS | 3 | Recursor na frente do authoritative; recursão raiz |
| [0006](0006-cert-wildcard-dns01-cloudflare.md) | Cert wildcard via DNS-01 | 3 | `*.lab` num cert só; staging + prod, flip declarativo |
| [0007](0007-storage-localpv-hostpath-anti-fake-ha.md) | LocalPV hostpath (anti fake-HA) | 4 | Mayastor no mesmo host é fake-HA; durabilidade é app-level |
| [0008](0008-observability-victoriametrics-single.md) | Observabilidade VictoriaMetrics Single | 5 | VM Single + VictoriaLogs + OTel; HA seria fake-HA |
| [0009](0009-data-platform-stores.md) | Stores stateful (Garage/CNPG/Valkey/CH/Qdrant/Memgraph) | 6 | Provisionar vazios e validados antes de qualquer app |
| [0010](0010-toolhive-operator-mcp.md) | MCP servers via ToolHive operator | 7 | CRD `MCPServer` padroniza secret/RBAC/proxy; stdio+proxy contorna OAuth |
| [0011](0011-kyverno-policy-engine.md) | Kyverno como policy engine | 7 | Mutate idempotente do `sessionAffinity` do ToolHive |
| [0012](0012-gpu-device-plugin-ollama-litellm.md) | GPU device plugin + Ollama + LiteLLM | 7 | qwen3-coder MoE cabe nos 24GB; device plugin standalone |
| [0013](0013-argo-workflows-git-artifact-elt.md) | Argo Workflows + git artifact (ELT) | 8 | Imagens genéricas; código por git artifact, sem rebuild |
| [0014](0014-dr-destino-sempre-b2.md) | Destino de DR sempre B2 (off-site) | 10 | Garage morre com o T630; B2 é off-site |
| [0015](0015-agentes-readonly-via-pr.md) | Agentes read-only, mudanças só via PR | 11 | Nunca mutam o cluster; coerente com GitOps puro |

## Não-decisões documentadas

Algumas coisas foram **deliberadamente não feitas**, com gatilho de retomada (registradas nos
runbooks): ArgoCD CLI gRPC-web atrás do Gateway (descartado — over-engineering), Hubble
forward-auth (adiado p/ Cilium 1.20 / GEP-1494). Registrar a não-decisão e o porquê vale tanto
quanto registrar um fix.

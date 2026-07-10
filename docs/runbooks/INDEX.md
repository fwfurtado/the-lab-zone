# Runbooks — índice por sintoma

Busca rápida: encontre o **sintoma** que você está vendo → vá pro runbook. Cada runbook agrupa
todos os incidentes de um domínio no formato `Sintoma → Causa → Diagnóstico → Fix → Lição`.

## Por domínio

| Domínio | Arquivo | Cobre |
|---|---|---|
| Talos | [talos/control-plane-etcd-gpu-taints.md](talos/control-plane-etcd-gpu-taints.md) | control plane sem métricas, etcd não hot-reload, leader changes/latência de commit, taint de nó joinado |
| ArgoCD | [gitops-argocd/adocao-sync-drift.md](gitops-argocd/adocao-sync-drift.md) | server-side apply, app.yaml silencioso, AppProject, sync travado, selfHeal, ignoreDifferences |
| Secrets/ESO | [secrets-eso/connect-replica-stale.md](secrets-eso/connect-replica-stale.md) | réplica do 1Password Connect congelada |
| Cilium (rede) | [cilium-rede/mtu-l2-gatewayapi.md](cilium-rede/mtu-l2-gatewayapi.md) | MTU do VXLAN, L2 announcement, operator CrashLoop (Gateway API) |
| Gateway/DNS | [gateway-dns/gateway-cert-dns-split-horizon.md](gateway-dns/gateway-cert-dns-split-horizon.md) | VAP, cert-manager namespace/enableGatewayAPI, pin do IP, split-horizon |
| Storage | [storage/openebs-localpv-hostpath.md](storage/openebs-localpv-hostpath.md) | logging vestigial do Mayastor, chaves do chart, plano TF |
| Storage | [storage/proxmox-nvme-expansion-plan.md](storage/proxmox-nvme-expansion-plan.md) | capacidade de disco no Proxmox, isolamento do control plane, plano NVMe em 2 fases |
| Observability | [observability/victoriametrics-grafana-otel.md](observability/victoriametrics-grafana-otel.md) | VM stack, webhook cert churn, operator não materializa, OTel, severidade de log (filelog por formato), LogsQL |
| Data platform | [data-platform/garage-clickhouse-cnpg-stores.md](data-platform/garage-clickhouse-cnpg-stores.md) | Garage S3, ClickHouse Altinity, Memgraph, VMPodScrape |
| ToolHive/MCP | [toolhive-mcp/toolhive-mcp-servers.md](toolhive-mcp/toolhive-mcp-servers.md) | sessionAffinity, Kyverno, stdio+OAuth, bind 0.0.0.0, SearXNG |
| GPU | [gpu/dcgm-runtimeclass-daemonset.md](gpu/dcgm-runtimeclass-daemonset.md) | DCGM (OOM/distroless), RuntimeClass+DaemonSet, taint+otel |
| Argo Workflows | [argo-workflows/workflows-elt-clickhouse-dbt.md](argo-workflows/workflows-elt-clickhouse-dbt.md) | generateName, templateRef, Argo 3.6, dbt/goose/ClickHouse |
| SSO/Authentik | [sso-authentik/authentik-oidc-apps.md](sso-authentik/authentik-oidc-apps.md) | grant_types, signing_key, trailing slash, Harbor/Forgejo/Langfuse |
| Network Policies | [network-policies/cilium-cnp-default-deny.md](network-policies/cilium-cnp-default-deny.md) | default-deny ingress, audit mode, fromEntities, archiveLogs, drops→Slack |
| Security | [security/trivy-operator-scan-jobs.md](security/trivy-operator-scan-jobs.md) | Trivy operator, scan jobs, cache lock, ClientServer, timeouts |
| Backup/DR | [backup-dr/cnpg-velero-offsite-dr.md](backup-dr/cnpg-velero-offsite-dr.md) | backup fantasma CNPG, anunciante L2 GPU, rclone vazio, Velero, plumbing |

## Por sintoma (atalhos)

**"Pequeno passa, grande trava" / `awaiting headers` / scrape com timeout cross-node**
→ cilium-rede (MTU do VXLAN não desconta overhead).

**Target/scrape/rule criado, correto, mas não aparece em `/targets`**
→ observability (operator não materializou → restart); checar também `matchExpressions`
(backup-dr) e `namespaceSelector` cross-ns (argo-workflows).

**`arping` no VIP timeout, mas `kubectl` ok / Gateway some intermitente**
→ backup-dr (nó GPU `enp7s0` vira anunciante L2 quebrado) ou cilium-rede (regex/lease).

**Backup "verde" mas bucket vazio / `ContinuousArchiving: True` sem dado**
→ backup-dr (backup fantasma do CNPG — quatro camadas).

**`rclone check` "0 differences" mas suspeito**
→ backup-dr (vazio-vs-vazio; confirmar `matching files > 0`).

**App OIDC falha (`invalid_request` / "failed to verify token") em todos de uma vez**
→ sso-authentik (provider compartilhado: grant_types / signing_key).

**`KubeJobFailed` intermitente em backup / Job Completed mas CNP suspeita**
→ backup-dr + network-policies (default-deny ingress intra-namespace; Hubble é a verdade).

**MCPServer `Ready` mas proxy com `connection refused`**
→ toolhive-mcp (bind 127.0.0.1; `Ready` ≠ alcançável cross-pod).

**App `OutOfSync` eterno / `caBundle` piscando / strategy Forbidden**
→ gitops-argocd (ignoreDifferences; strategy imutável) + observability (webhook cert churn).

**Tudo `unknown` no VictoriaLogs / filtro por nível não funciona / painel do Explore quebra**
→ observability (severidade não-setada vira `Unspecified`; `logfmt_parser` inexistente; nome de
campo dot-notation; `count()` sem alias) — ver ADR-0019.

**Pod GPU/DaemonSet `Pending`/`Unschedulable` ou DaemonSet `RolloutStuck`**
→ gpu (RuntimeClass scheduling tarde; taint trava telemetria já agendada).

**etcd perde líder / `context deadline exceeded` / `slow fdatasync` / `ReadIndex took too long`**
→ talos (leader changes recorrentes; diagnóstico cruzado Talos + VictoriaMetrics + Proxmox).

**Argo mostra `Unable to create Service resource` / webhook `connection refused` / pod `Pending` sem evento**
→ talos (cascata de control plane: scheduler/operator/webhook perdendo lease) e storage
(migracao stateful em curso pode mascarar a raiz).

**Alerta fira mas não chega no Slack**
→ network-policies (`useManagedConfig:true`; snake_case; `disableNamespaceMatcher`).

**`AUTHENTICATION_FAILED` no ClickHouse com a senha certa / goose "no migrations to run"**
→ argo-workflows (usuário SQL some com o access storage; `goose_db_version` é dado e sobrevive).
Erro de auth prova servidor **vivo**; pod de teste sem labels dá timeout por CNP, não por CH morto.

**Dashboard do Git não atualiza no Grafana / `no database write permissions because of duplicates`**
→ observability (um uid duplicado congela a escrita de TODOS os providers, sem erro na UI).
`gnetId` no values é arquivo no PVC: remover do Git não apaga do disco.

**Grafana em CrashLoop com `Datasource provisioning error: data source not found`**
→ observability (mudou `uid` de datasource existente → precisa de `deleteDatasources`).
Se o pod sobe mas a UI não abre datasource, é cache do navegador — teste com `/api/datasources/uid/<uid>/health`.

**Alerta de agente (`agents-red`) firing sem incidente real**
→ observability (span de erro ≠ falha; `> 0` em span-metric de agente conta ruído de recuperação).
Compare erro interno vs. erro de raiz (`span_name="invoke_agent agent"`); alerte na raiz ou em razão, não em contagem bruta.

## Lições que se repetem (ver README de docs/)

Status verde é promessa, leia o destino · VM operator não materializa → restart (3x) ·
default-deny por app com audit ON antes · Hubble flow é a verdade (não timeline de Jobs) ·
chave de Helm inexistente falha em silêncio · `Ready` do ToolHive ≠ alcançável cross-pod.

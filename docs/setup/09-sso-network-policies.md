---
tipo: setup
fase: 9
titulo: SSO (Authentik) + Network Policies default-deny + observabilidade de drops
relacionado: [runbooks/sso-authentik, runbooks/network-policies, decisions/0002-admin-local-argocd-sempre-habilitado]
---

# Setup Fase 9 — SSO + Network Policies + drops

Estado final: SSO via Authentik em 6 apps (ArgoCD, Grafana, Open WebUI, Langfuse in-cluster;
Harbor, Forgejo em VM mgmt). Default-deny **ingress** em `data` e `ai`, app por app, validado
em Cilium Policy Audit Mode. Hubble forward-auth adiado p/ Cilium 1.20.

Os incidentes desta fase estão nos runbooks `sso-authentik`, `network-policies` e `backup-dr`.
Este setup cobre a **ordem/procedimento**.

## Parte 1 — SSO via Authentik
Provider OIDC configurado via Terraform (com `op run` + 1Password). Pontos obrigatórios do
provider (senão quebra todos os apps de uma vez):
- `grant_types = ["authorization_code", "refresh_token"]` (não defaulta no Authentik 2026.5).
- `signing_key` setado (senão assina HS256; clientes esperam RS256 via JWKS).
- `offline_access` no scope mapping (Harbor precisa do refresh pro CLI secret).

Por app: cuidar do trailing slash do issuer (Langfuse SEM barra; Harbor COM barra), do
provisioning manual de org no Langfuse (Members), dos campos de claim do Harbor (Group Claim
`groups`, Group Filter vazio), e do auto-register externo do Forgejo. ArgoCD: extender
`access_token_validity` para 12h (OIDC token expiry). Admin local permanece habilitado (ADR-0002).

## Parte 2 — Network Policies (default-deny ingress em data e ai)
Fronteira GitOps: `manifests/` = enforçado; `pending/` = baseline em audit, à mão, fora do
GitOps; promoção = `git mv pending/ → manifests/`. AppProject `security` reusado; CNPs vão pra
`data`/`ai` pelo próprio `metadata.namespace`.

**Ritual padrão por app (ordem é sagrada):**
```
1. label real:  kubectl -n <ns> get pod -l <selector> --show-labels
2. LIGA audit ANTES (vem Disabled!) + confirma Enabled em TODOS os pods
3. aplica baseline (pending/); confere VALID:True e policy-enabled:ingress no endpoint
4. observa (força reconexão dos clientes p/ os SYN): hubble observe -t policy-verdict --follow
5. cada AUDIT vira allow (fromEndpoints+toPorts; fromEntities p/ ingress/host/health);
   refina até zerar AUDIT, cobrindo 1 ciclo completo (inclui crons/backups)
6. PROMOVE: git mv pending/ → manifests/; audit Disabled (vira enforcement)
7. rede de segurança: hubble observe --verdict DROPPED --follow
```
Default-deny ingress = `ingress: - {}` (não `[]`, que é inválido). Cobertos em `data`
(clickhouse, postgresql, garage, valkey, qdrant, memgraph) e `ai` (open-webui, litellm,
langfuse, ollama). Atenção ao `archiveLogs` do Argo (libera Garage:3900 pros produtores +
`argo-workflows-server`).

## Parte 3 — Observabilidade de drops (alerta → Slack)
Cadeia: `hubble_drop_total` → VMRule `CiliumPolicyDrop` → vmalert → vmalertmanager → Slack.
1. Cilium values: `hubble.metrics.enabled` com `drop:labelsContext=...`, flow, tcp, dns.
2. VMServiceScrape em `kube-system` (mesmo ns do service `hubble-metrics`) → **restart operator**.
3. VMRule `CiliumPolicyDrop` (`rate(hubble_drop_total{reason="POLICY_DENIED",destination_namespace
   =~"data|ai"}[5m])>0, for:2m`) → **restart operator**.
4. Grafana: Alertmanager datasource + `vmalert.proxyURL` no vmsingle + `manageAlerts:true`.
5. Slack: ExternalSecret (webhook do Infisical) + VMAlertmanagerConfig (route snake_case);
   vmks `alertmanager.useManagedConfig:true` + `disableNamespaceMatcher:true`.

Validar fim-a-fim com drop **sustentado** > `for:` (burst não basta). A verdade do config do
alertmanager é o pod (`/etc/alertmanager/config_out/`), não o secret `-config`.

## Concluído na Fase 9
SSO em 6 apps; default-deny ingress em data/ai app por app; observabilidade de drops validada
fim-a-fim; backups (Qdrant/ClickHouse) migrados de CronJob → Argo CronWorkflow. Pendências:
Hubble forward-auth (Cilium 1.20), egress em data/ai, `inhibit_rules` no VMAlertmanagerConfig.

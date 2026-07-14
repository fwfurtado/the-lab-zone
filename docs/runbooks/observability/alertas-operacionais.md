---
tipo: runbook
componente: observability-alerts
tags: [alertmanager, vmalert, blackbox, argocd, cert-manager, external-secrets, grafana, victoriametrics, runbook]
fases: [5, 9, 10]
relacionado: [runbooks/observability, runbooks/gitops-argocd, runbooks/gateway-dns, runbooks/secrets-eso, runbooks/network-policies]
---

# Alertas operacionais

Runbook para os alertas que entram pelo fluxo `VMRule -> VMAlert -> Alertmanager -> Slack`
e, quando `triage="true"`, tambem pelo `triage-webhook`.

## Primeiro corte

**Sintoma:** alerta chegou no Slack.

**Diagnostico rapido:**

```bash
kubectl -n observability get vmalertmanagerconfig slack
kubectl -n observability get vmalertmanager victoria-metrics-vmks
kubectl -n observability get vmalert victoria-metrics-vmks
kubectl -n observability get vmrule | grep -E '<alertname>|grafana|blackbox|argocd|cert-manager|external-secrets'
```

No Grafana:

- Dashboard `Core / Core Platform`
- Dashboard `Observability / Synthetic Probes`
- Dashboard `Observability / Observability Stack`
- Datasource `Alertmanager` para ver grupo, labels e receiver efetivo.

Se a notificacao nao chegou no Slack, mas o alerta esta firing:

```bash
kubectl -n observability get vmalertmanagerconfig slack -o yaml
kubectl -n observability describe vmalertmanagerconfig slack
kubectl -n observability logs statefulset/vmalertmanager-victoria-metrics-vmks -c alertmanager --since=30m
```

Esperado no `VMAlertmanagerConfig`: `ConfigParsedAndApplied=True`.

## BlackboxProbeFailed

**Sintoma:** `BlackboxProbeFailed` para uma URL.

**Causa provavel:** rota publica indisponivel, Gateway/DNS/TLS quebrado, app retornando status
nao-2xx, ou endpoint de health errado para a classe do servico.

**Diagnostico:**

```bash
kubectl -n observability get vmprobe
kubectl -n observability exec deploy/blackbox-exporter -- \
  wget -qO- 'http://127.0.0.1:9115/probe?module=http_2xx&target=<URL>' \
  | grep -E 'probe_success|probe_http_status_code|probe_duration_seconds|probe_ssl'
kubectl -n gateway get gateway,httproute -A
kubectl -n gateway get httproute -A | grep '<host>'
```

Interpretação:

- `probe_success 0` + `probe_http_status_code 404`: endpoint errado ou app nao serve `/`.
- `probe_success 0` + sem status HTTP: DNS, TCP, TLS ou Gateway.
- `probe_ssl_earliest_cert_expiry` baixo: certificado proximo de expirar.
- `probe_class=special-health`: validar o endpoint explicito, ex. `/health`.

**Fix:**

- App web: corrigir app/Gateway/HTTPRoute.
- API sem pagina em `/`: mover para `public-api` com endpoint 2xx real.
- vLLM/servico especial: usar `special-health` apontando para `/health`.
- DNS/TLS/Gateway: seguir `docs/runbooks/gateway-dns/gateway-cert-dns-split-horizon.md`.

**Lição:** probe sintetico deve representar o contrato real do servico, nao assumir que `/`
sempre e uma pagina web.

## BlackboxProbeSlow

**Sintoma:** `BlackboxProbeSlow` por mais de 5m.

**Diagnostico:**

```bash
kubectl -n observability exec deploy/blackbox-exporter -- \
  wget -qO- 'http://127.0.0.1:9115/probe?module=http_2xx&target=<URL>' \
  | grep 'probe_http_duration_seconds'
```

Olhar fases: `resolve`, `connect`, `tls`, `processing`, `transfer`.

**Fix:** depende da fase lenta: DNS/split-horizon, Gateway/Cilium/TLS, ou app/backend.

## ArgoCDApplicationOutOfSync

**Sintoma:** app do Argo CD fica `OutOfSync`.

**Diagnostico:**

```bash
kubectl -n argocd get app <app> -o json | jq -r '
  .status.resources[]? |
  select(.status != "Synced" or (.requiresPruning // false) == true) |
  [.group,.kind,(.namespace // ""),.name,(.status // ""),(.health.status // ""),(.requiresPruning // false)] | @tsv'

kubectl -n argocd get app <app> -o json | jq -r '
  .status.operationState.message // "",
  (.status.operationState.syncResult.resources[]? |
   select((.status // "") != "Synced") |
   [.kind,(.namespace // ""),.name,(.status // ""),(.message // "")] | @tsv)'
```

**Causas comuns:** CRD com migracao de `storedVersions`, campo mutado por controller,
prune pendente, AppProject bloqueando recurso, ou operacao antiga em retry.

**Fix:** `argocd app terminate-op <app>` se for retry antigo; corrigir Git se for drift real;
avaliar `ignoreDifferences` apenas para campo controlado por outro controller. Para CRD com
ownership compartilhado, escolher dono unico. Ver tambem
`docs/runbooks/gitops-argocd/adocao-sync-drift.md`.

## ArgoCDApplicationUnhealthy

**Sintoma:** app `Synced`, mas `Healthy` diferente de `Healthy`.

**Diagnostico:**

```bash
kubectl -n argocd get app <app> -o json | jq -r '
  .status.resources[]? |
  select((.health.status // "") != "Healthy") |
  [.group,.kind,(.namespace // ""),.name,(.status // ""),(.health.status // ""),(.health.message // "")] | @tsv'
kubectl -n <ns> describe <kind> <name>
kubectl -n <ns> get events --sort-by=.lastTimestamp | tail -n 40
```

## CertManagerCertificateNotReady

**Sintoma:** certificado com condition `Ready=False` ou `Ready=Unknown`.

**Diagnostico:**

```bash
kubectl get certificate -A
kubectl -n <ns> describe certificate <cert>
kubectl -n <ns> get certificaterequest,order,challenge
kubectl -n cert-manager logs deploy/cert-manager --since=30m
```

**Causas comuns:** DNS-01 sem credencial Cloudflare, Gateway/HTTPRoute usando secret
inexistente, Issuer/ClusterIssuer nao ready, ou Challenge ACME pendente.

**Fix:** seguir o objeto filho (`CertificateRequest -> Order -> Challenge`). Para Gateway/DNS/TLS,
ver `docs/runbooks/gateway-dns/gateway-cert-dns-split-horizon.md`.

## CertManagerCertificateExpiringSoon

**Sintoma:** certificado expira em menos de 14/30 dias, dependendo da regra.

**Diagnostico:**

```bash
kubectl get certificate -A
kubectl -n <ns> describe certificate <cert>
kubectl -n cert-manager logs deploy/cert-manager --since=2h
```

**Fix:** confirmar `renewalTime`; se a renovacao falha, investigar `Order`/`Challenge`.
Nao apagar Secret de TLS sem entender quem consome esse certificado.

## ExternalSecretNotReady

**Sintoma:** `ExternalSecret` com `Ready=False`.

**Diagnostico:**

```bash
kubectl get externalsecret -A
kubectl -n <ns> describe externalsecret <name>
kubectl get clustersecretstore
kubectl describe clustersecretstore onepassword
kubectl -n external-secrets logs deploy/external-secrets --since=30m
```

**Causas comuns:** item/propriedade nao existe no 1Password, `ClusterSecretStore` sem
autenticacao, replica stale do 1Password Connect, ou Secret target conflitando com outro owner.

**Fix:** se houver suspeita de Connect stale, seguir
`docs/runbooks/secrets-eso/connect-replica-stale.md`.

## ExternalSecretsReconcileErrors

**Sintoma:** aumento de erros de reconcile do External Secrets.

**Diagnostico:**

```bash
kubectl -n external-secrets logs deploy/external-secrets --since=30m | grep -iE 'error|failed'
kubectl get externalsecret -A
```

**Fix:** tratar o primeiro `ExternalSecret` com erro concreto; um erro de store costuma gerar
varios `ExternalSecretNotReady`.

## MetricsAPIUnavailable

**Sintoma:** `kubectl top` falha ou API `metrics.k8s.io` nao responde.

**Diagnostico:**

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl describe apiservice v1beta1.metrics.k8s.io
kubectl -n kube-system get pods -l app.kubernetes.io/name=metrics-server
kubectl -n kube-system logs deploy/metrics-server --since=30m
kubectl top nodes
```

**Fix:** validar values do metrics-server e permissao do consumidor:

```bash
kubectl auth can-i list nodes.metrics.k8s.io --as system:serviceaccount:<ns>:<sa>
kubectl auth can-i list pods.metrics.k8s.io --as system:serviceaccount:<ns>:<sa>
```

## GrafanaTargetDown

**Sintoma:** `VMServiceScrape/grafana` nao consegue raspar `/metrics`.

**Diagnostico:**

```bash
kubectl -n observability get vmservicescrape grafana
kubectl -n observability get svc grafana -o wide
kubectl -n observability get pods -l app.kubernetes.io/name=grafana
kubectl -n observability logs deploy/grafana -c grafana --since=30m
kubectl -n observability exec deploy/blackbox-exporter -- \
  wget -S -qO- http://grafana.observability.svc.cluster.local/metrics | head
```

**Fix:** se Pod crashando, ler logs do container `grafana`; se Service/selector errado, comparar
labels do Pod e Service; se dashboard invalido, checar sidecar e JSON dos ConfigMaps.

## GrafanaDatasourceErrors

**Sintoma:** Grafana retorna 5xx ao consultar datasource.

**Diagnostico:**

```bash
kubectl -n observability logs deploy/grafana -c grafana --since=30m | grep -i datasource
kubectl -n observability get svc | grep -E 'vmsingle|victoria-logs|tempo|loki|alertmanager'
```

**Fix:** geralmente e DNS/service name, datasource UID, ou backend indisponivel. Ver
`docs/runbooks/observability/victoriametrics-grafana-otel.md`.

## VictoriaMetrics stack default alerts

Alertas do chart `victoria-metrics-k8s-stack` ja cobrem VMSingle, VMAgent, VMAlert,
Alertmanager, VM Operator, kube-state-metrics e node-exporter.

**Primeiro diagnostico:**

```bash
kubectl -n observability get pods,svc | grep -E 'vmsingle|vmagent|vmalert|vmalertmanager|operator|grafana|blackbox'
kubectl -n observability get vmservicescrape,vmrule | grep -E 'vmsingle|vmagent|vmalert|alertmanager|operator|grafana|blackbox'
kubectl -n observability logs deploy/vmagent-victoria-metrics-vmks --since=30m
kubectl -n observability logs deploy/vmalert-victoria-metrics-vmks --since=30m
kubectl -n observability logs statefulset/vmalertmanager-victoria-metrics-vmks -c alertmanager --since=30m
```

**Casos comuns:**

- Scrape/Rule criado mas nao aparece: restart do VM Operator ou VMAgent, conforme
  `docs/runbooks/observability/victoriametrics-grafana-otel.md`.
- Alertmanager config nao aplica: `describe vmalertmanagerconfig slack` precisa mostrar
  `ConfigParsedAndApplied=True`.
- VMSingle com disco alto: olhar dashboard `Observability Stack` e PVC/storage.
- VMAgent com pending remote write: VMSingle indisponivel ou rede entre VMAgent e VMSingle.

## Teste controlado de ponta a ponta

Para testar `VMAlert -> Alertmanager -> Slack` sem quebrar um servico real, criar uma regra
temporaria com `vector(1)` e remover depois.

```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMRule
metadata:
  name: alert-pipeline-test
  namespace: observability
spec:
  groups:
    - name: alert-pipeline-test
      rules:
        - alert: AlertPipelineTest
          expr: vector(1)
          for: 1m
          labels:
            severity: info
            component: observability-test
          annotations:
            summary: "Teste controlado do pipeline de alertas"
            description: "Remover esta VMRule apos validar Slack/Alertmanager."
```

**Lição:** teste sintetico deve ser removido no mesmo change/run. Nao usar alerta real como
teste de roteamento.

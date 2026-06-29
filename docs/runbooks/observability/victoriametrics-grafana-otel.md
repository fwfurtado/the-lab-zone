---
tipo: runbook
componente: observability
tags: [victoriametrics, vmagent, vmoperator, grafana, otel-collector, vmservicescrape, webhook-cert, reconciliacao]
fases: [5, 6, 7]
relacionado: [runbooks/cilium-rede, runbooks/argo-workflows]
---

# VictoriaMetrics, Grafana e OTel Collector

Incidentes da stack de observabilidade. O padrão dominante: **VM operator não materializa
recurso novo → restart** (aconteceu ≥3x; ver no fim).

## CRDs bloqueados pelo AppProject

**Sintoma:** ArgoCD recusa sync com `resource ... is not permitted in project`.
**Causa:** `clusterResourceWhitelist` não incluía `CustomResourceDefinition` nem os CRDs do
operator VictoriaMetrics (`operator.victoriametrics.com/*`).
**Fix:** expandir `clusterResourceWhitelist` no `projects/observability.yaml`.

## node-exporter FailedCreate por PodSecurity

**Sintoma:** pods do node-exporter `Pending`/`FailedCreate` com erro de PodSecurity admission.
**Causa:** o namespace `observability` com policy `baseline` bloqueia `hostNetwork`/`hostPID`/
`hostPath` que o node-exporter exige.
**Fix:** labels `pod-security.kubernetes.io/{enforce,audit,warn}: privileged` no `namespace.yaml`.

## VMAlert falha no `helm template` sem notifier

**Sintoma:** `helm template` falha com `Neither notifier, notifiers nor notifierConfigRef is
set for vmalert`.
**Causa:** o chart `victoria-metrics-k8s-stack` valida em template time que o VMAlert tem ao
menos um notifier; com `alertmanager.enabled: false` o deploy falha por inteiro.
**Fix:** `alertmanager.enabled: true` — o Alertmanager interno vira o notifier padrão.

## VictoriaLogs Headless (sem ClusterIP)

**Sintoma:** `victoria-logs-vls-server` com `ClusterIP: None`; OTel não resolve o endpoint.
**Causa:** o chart `victoria-logs-single` defaulta `clusterIP: None`. A key `service.clusterIP`
na **raiz** do values é ignorada — a correta é `server.service.clusterIP`.
**Fix:** `server.service.clusterIP: ""` (string vazia → K8s atribui ClusterIP normal).
**Atenção:** mudar `clusterIP` é imutável — `kubectl delete svc victoria-logs-vls-server`; o
ArgoCD recria no próximo sync.

## Grafana Deployment OutOfSync após mudança de strategy

(Mesma classe de "strategy imutável" do `runbooks/gitops-argocd/`.) Deployment com PVC RWO
deve nascer com `deploymentStrategy.type: Recreate` + `rollingUpdate: null`. Mudar depois exige
`kubectl delete deployment grafana` + terminate + sync com prune.

## Grafana datasource com DNS errado (nameOverride)

**Sintoma:** datasources VM/VLogs falham em Test com "connection refused"/"no such host".
**Causa:** service names gerados com `nameOverride: vmks` diferem dos nomes sem override; só são
conhecidos após o primeiro deploy.
**Fix:** usar os service names reais (ex. `vmsingle-victoria-metrics-vmks:8428`,
`victoria-logs-vls-server:9428`) nos FQDNs do datasource.

## Grafana dashboard via ConfigMap: datasource não resolvido

**Sintoma:** dashboard importado por ConfigMap com dropdown "Datasource" vazio.
**Causa:** o mecanismo `__inputs`/`${DS_VICTORIAMETRICS}` é pra import manual; via ConfigMap a
variável não resolve.
**Fix:** substituir `${DS_VICTORIAMETRICS}` pelo UID real do datasource direto no JSON. (O
sidecar `grafana-sc-dashboard` importa qualquer ConfigMap com label `grafana_dashboard: "1"`.)

## OTel Collector — `image.repository` obrigatório (chart ≥ 0.127.x)

**Sintoma:** `[ERROR] 'image.repository' must be set`.
**Causa:** breaking change — o chart parou de ter default por suportar múltiplas distribuições.
**Fix:** declarar `image.repository: .../opentelemetry-collector-k8s` + `command.name: otelcol-k8s`.

## OTel Collector — `prometheusremotewrite` indisponível no `otelcol-k8s`

**Sintoma:** CrashLoopBackOff com `unknown type: "prometheusremotewrite"`.
**Causa:** `otelcol-k8s` é distribuição slim sem esse exporter (só `otlp`, `otlphttp`, `debug`,
`file`, `loadbalancing`, `otelarrow`).
**Fix:** trocar pra `otlphttp` apontando pro endpoint OTLP nativo do VMSingle
(`http://vmsingle-...:8428/opentelemetry`). VMSingle aceita OTLP em `/opentelemetry`.

## kube-controller-manager/scheduler/etcd: ver runbook do Talos

Targets DOWN do control plane (bind-address 127.0.0.1, TLS só p/ localhost, etcd sem listener)
estão em `runbooks/talos/control-plane-etcd-gpu-taints.md` — é causa de machine config, não da
stack VM.

## Webhook cert do VM Operator em churn sob ArgoCD

**Sintoma:** bursts (~a cada sync) de `tls: bad certificate` nos logs do operator (de IPs dos
CIDRs de pod dos CPs), cada burst seguido de `certwatcher Updated current TLS certificate`. Em
paralelo, `MountVolume.SetUp failed ... secret "...-validation" not found` + restarts.
**Causa:** o cert do webhook era **Helm-generated** (usa `lookup` do Helm pra reusar o cert). O
ArgoCD renderiza com `helm template` e **não respeita `lookup`** — a cada sync gera cert +
caBundle novos. Com `prune: true`, o secret é recriado, abrindo janela de `FailedMount` →
restart → reabre a janela de `bad certificate`. Loop auto-sustentado.
**Fix:** migrar pro cert-manager: `admissionWebhooks.certManager.enabled: true` no
`victoria-metrics-operator`. E `ignoreDifferences` no `caBundle` que o cainjector injeta (senão
o app pisca OutOfSync):
```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jqPathExpressions: ['.webhooks[]?.clientConfig.caBundle']
```
**Validação:** o secret `...-validation` ficar **sem** o label `app.kubernetes.io/instance`
garante que o ArgoCD não o reivindica nem pruna (cert-manager é o dono).
**Lição:** k8s-stack via ArgoCD **sem** cert-manager churna o cert do webhook (`lookup` não
respeitado). Com cert-manager no cluster, `certManager.enabled: true` elimina o loop — e dá o
fix **permanente** pro restart-paliativo do incidente abaixo.

## VMPodScrape/VMServiceScrape/VMRule não materializa → RESTART do operator

**Sintoma:** recurso do VM operator criado e correto (`operational`/`VALID`), selectors casam,
`selectAllByDefault: true`, sem erro — mas não vira target/rulefile/config. Visto com:
VMPodScrape após TLS mismatch (fase 6), scrape novo (fase 7), scrape+rule+config de drops (fase 9).
**Causa:** o operator não reconcilia o recurso novo até ser reiniciado.
**Fix:** `kubectl -n observability rollout restart deploy/victoria-metrics-victoria-metrics-operator`
(ou o vmagent, se o scrape novo não aparece nos `activeTargets` — `rollout restart
deploy/vmagent-...`, fase 7).
**Lição:** **aconteceu ≥3x.** Recurso VM correto que "não aparece" → primeiro reflexo é
reiniciar o operator (ou o vmagent), não o último recurso. Causas estruturais que ALÉM disso
quebram o target: selectors errados (labels reais via `--show-labels`), `matchExpressions`
(usar só `matchLabels` — ver `runbooks/backup-dr/`), scrape cross-namespace sem
`namespaceSelector` (ver `runbooks/argo-workflows/`).

## Lição transversal

`operational`/`VALID`/`selectAllByDefault` não provam target gerado. A prova é o target em
`/api/v1/targets` (`health: up`) e a série no banco — não o status do CR. Query de verdade no
**VMSingle** (8428), não no vmagent (8429, só buffer).

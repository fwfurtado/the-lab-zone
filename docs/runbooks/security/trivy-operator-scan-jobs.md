---
tipo: runbook
componente: security
tags: [trivy-operator, vulnerabilityreport, scan-job, cache-lock, clientserver, timeout, node-collector]
fases: [9]
relacionado: [runbooks/observability, runbooks/gitops-argocd]
---

# Trivy Operator: scan jobs, cache lock e timeout

Incidente de `KubeJobFailed` no namespace `trivy-system`, disparado por
`node-collector-b985fddb5` e depois ampliado para dezenas de
`scan-vulnerabilityreport-*`.

## Cache lock em massa nos scan jobs

**Sintoma:** alerta `KubeJobFailed` com `severity=warning` para
`trivy-system/node-collector-b985fddb5`. Ao abrir o namespace, vários Jobs
`scan-vulnerabilityreport-*` falham no mesmo intervalo. Nos logs dos containers
`init`, `main`, `clone` ou `wait`:

```text
Failed acquire cache or database lock
cache may be in use by another process: timeout
```

**Causa:** o chart estava em `trivy.mode: Standalone`. O operator cria um scan
container por container do Pod alvo; quando o Pod alvo tem múltiplos containers
(ex. Argo Workflows: `init`, `main`, `wait`, `clone`), todos os processos Trivy
do mesmo scan job usam o mesmo `emptyDir` em `/tmp/trivy/.cache`. O lock do
cache/DB é exclusivo; os processos competem entre si e estouram timeout. O
`--slow` só reduz paralelismo interno do scan, não serializa o acesso ao cache.

**Diagnóstico:**

```bash
kubectl -n trivy-system get pods,jobs
kubectl -n trivy-system logs deploy/trivy-operator --since=2h
kubectl -n trivy-system get events --field-selector type=Warning --sort-by=.lastTimestamp
kubectl logs -n trivy-system <scan-pod> -c main
```

Conferir a configuração efetiva:

```bash
kubectl -n trivy-system get cm trivy-operator-config trivy-operator-trivy-config -o yaml
```

Sinais ruins:

- `trivy.mode: Standalone`
- `trivy.imageScanCacheDir: /tmp/trivy/.cache`
- erros de lock simultâneos em containers diferentes do mesmo Job

**Fix definitivo:** usar Trivy em `ClientServer` com Trivy Server gerenciado
pelo chart. O cache/DB deixa de morar nos Pods de scan e passa para o
`StatefulSet/trivy-server` com PVC.

Valores relevantes em `apps/security/trivy-operator/values.yaml`:

```yaml
trivy:
  mode: ClientServer
  storageClassEnabled: true
  storageClassName: openebs-hostpath-ssd
  storageSize: 5Gi
  timeout: "15m0s"

operator:
  builtInTrivyServer: true
  scanJobTimeout: 20m
  scanJobsConcurrentLimit: 1

trivyOperator:
  scanJobCompressLogs: false
```

**Validação pós-sync:**

```bash
kubectl -n trivy-system get pods,svc,statefulset,pvc
kubectl -n trivy-system get cm trivy-operator-config trivy-operator-trivy-config -o yaml
```

Esperado:

- `pod/trivy-server-0` `Running`
- `service/trivy-service`
- PVC `data-trivy-server-0` `Bound`
- `OPERATOR_BUILT_IN_TRIVY_SERVER: "true"`
- `trivy.mode: ClientServer`
- `trivy.serverURL: http://trivy-service.trivy-system:4954`

## Timeout ao popular cache do Trivy Server

**Sintoma:** após migrar para `ClientServer`, o lock local some, mas alguns
`scan-vulnerabilityreport-*` ainda chegam a `BackoffLimitExceeded` durante a
primeira leva de scans. Reproduzindo via cliente contra o server:

```text
context deadline exceeded
failed to store layer ... in cache: unable to store cache on the server
```

**Causa:** imagens maiores, especialmente Python/ML ou imagens com muitas
camadas, podem passar de 5m no primeiro scan enquanto o Trivy Server baixa,
analisa e persiste layers no cache. O cache persistente reduz o custo das
tentativas seguintes, mas o primeiro ciclo precisa de timeout maior.

**Fix:** manter `trivy.timeout: "15m0s"` e `operator.scanJobTimeout: 20m`. O
timeout do Job deve ser maior que o timeout do Trivy; caso contrário o kubelet
mata o Job antes do scanner retornar erro legível.

**Teste controlado de imagem específica:**

```bash
kubectl -n trivy-system exec trivy-server-0 -- \
  trivy image --server http://127.0.0.1:4954 --timeout 15m --format json <imagem>
```

Não executar `trivy image <imagem>` standalone dentro do `trivy-server-0`: isso
concorre com o processo server pelo mesmo cache e reproduz artificialmente o
lock.

## Logs compactados como bzip2/base64

**Sintoma:** logs de scan aparecem começando com `Qlpo...` ou o operator
compacta `status.message` como `<<ccr:...>>`.

**Causa:** `trivyOperator.scanJobCompressLogs` vinha habilitado pelo chart. Isso
economiza log, mas atrapalha triagem durante incidente.

**Fix:** `trivyOperator.scanJobCompressLogs: false`.

Se precisar ler um log antigo compactado:

```bash
kubectl -n trivy-system logs <scan-pod> -c <container> | base64 -d | bzip2 -dc
```

## Forçar um ciclo de scan

O operator recria scan jobs quando um `VulnerabilityReport` esperado desaparece.

Um Pod específico:

```bash
kubectl delete vulnerabilityreports -n <ns> \
  -l trivy-operator.resource.kind=Pod,trivy-operator.resource.name=<pod>
```

Um namespace:

```bash
kubectl delete vulnerabilityreports -n <ns> --all
```

Cluster inteiro:

```bash
kubectl delete vulnerabilityreports -A --all
```

Usar o cluster inteiro só depois de confirmar `ClientServer` e Trivy Server
`Running`, senão uma leva grande de scans pode reabrir o incidente.

## Resíduo vs falha ativa

`BackoffLimitExceeded` em `kubectl get events` pode ficar retido mesmo depois do
Job ter sido removido por GC. Para decidir se ainda há problema:

```bash
kubectl -n trivy-system get pods,jobs
kubectl -n trivy-system logs deploy/trivy-operator --since=5m
kubectl -n trivy-system get events --field-selector type=Warning --sort-by=.lastTimestamp
```

Interpretação:

- Sem `scan-vulnerabilityreport-*` ativo/persistido e sem erro novo no log do
  operator: provavelmente só evento retido.
- `scan-vulnerabilityreport-*` novo com `BackoffLimitExceeded`: abrir o log do
  container do scan; a causa real não é o status do Job.
- `node-collector-b985fddb5` antigo com `DeadlineExceeded`: resíduo do incidente
  original. Pode ser removido para limpar alerta residual:

```bash
kubectl -n trivy-system delete job node-collector-b985fddb5
```

## Lição transversal

`scanJobsConcurrentLimit: 1` limita Jobs simultâneos, mas não resolve disputa
entre containers dentro do mesmo scan job. Quando o workload alvo tem múltiplos
containers, a fronteira correta para o cache do Trivy é um serviço central
(`ClientServer`) com PVC, não um `emptyDir` compartilhado em cada Job.

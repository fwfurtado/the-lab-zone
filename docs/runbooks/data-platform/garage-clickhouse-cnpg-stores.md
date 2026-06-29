---
tipo: runbook
componente: data-platform
tags: [garage, clickhouse, altinity, memgraph, vmpodscrape, s3, fsgroup, watch-namespaces, secret-rele]
fases: [6]
relacionado: [runbooks/backup-dr, runbooks/observability]
---

# Plataforma de dados: Garage, ClickHouse, Memgraph e scrapes

Incidentes ao subir os 6 stores stateful (Garage, CNPG, Valkey, ClickHouse, Qdrant, Memgraph).
Backup do CNPG/Qdrant/ClickHouse está em `runbooks/backup-dr/`.

## Garage — campo `environment` não aceita objetos

**Sintoma:** `.env: expected list, got &{map[...]}`.
**Causa:** o campo `environment` do chart Garage v2 só aceita dict de strings literais; passar
`secretKeyRef` como valor quebra o template.
**Fix:** secrets montados via `extraVolumes` projected (`defaultMode: 0600`, `subPath`); no
`environment`, só strings literais.

## Garage — fsGroup do K8s impede permissão 0600

**Sintoma:** `File /etc/garage-secrets/rpcSecret is world-readable! (mode: 0100640, expected
0600)`.
**Causa:** o chart tem `fsGroup: 1000` hardcodado; o K8s aplica nos volumes montados,
adicionando bit de leitura de grupo mesmo com `defaultMode: 0600`.
**Fix:** `GARAGE_ALLOW_WORLD_READABLE_SECRETS: "true"` (string literal) no `environment` — o
Garage documenta essa env pra ambientes container onde o fsGroup é inevitável.

## Garage — buckets com alias local apenas

**Sintoma:** `GetBucketInfo returned NoSuchBucket` ao dar permissão por nome.
**Causa:** o provider AWS cria buckets no Garage com alias **local** (vinculado à key de
criação); `garage bucket allow <nome>` requer alias **global**.
**Fix:** após `tf-apply`, rodar `just garage alias-buckets` (`garage bucket alias --global <ID>
<nome>`).

## Garage — region na assinatura AWS4

**Sintoma:** `unexpected scope: '.../us-east-1/s3/...', expected: '.../garage/s3/...'`.
**Causa:** o provider valida a region como string AWS válida, mas o Garage exige `garage` no
scope.
**Fix:** `skip_region_validation = true` + `region = "garage"` no provider. Pro rclone: `region
= garage`.

## ClickHouse operator — `watchNamespaces` via env var

**Sintoma:** CHI criado em `data` não é processado; logs param em "workers started".
**Causa:** o Altinity operator só monitora o namespace dele por default. `watch.namespaces.
include: []` no ConfigMap significa "nenhum adicional", não "todos".
**Fix:** `WATCH_NAMESPACES=data` via env var no values do operator.

## ClickHouse — `passwordSecretRef` não relê Secret após criação

**Sintoma:** atualizar senha no 1Password + reconcile, mas o hash no `chop-generated-users.xml`
fica o antigo.
**Causa:** o operator cacheia o valor do Secret na criação do CHI e não observa mudanças.
**Fix:** `from_env` no XML de usuários via `configuration.files`; as env vars vêm de
`valueFrom.secretKeyRef` no container e o ClickHouse expande `<password_sha256_hex
from_env="VAR"/>` em runtime. O ExternalSecret gera os hashes via template ESO.

## ClickHouse — senha default ao invés da configurada (SHA256 duplo)

**Sintoma:** autenticação falha com a senha do 1Password mas funciona com `default`.
**Causa:** o `passwordSecretRef` usava o **hash SHA256** como valor; o ClickHouse faz SHA256 do
valor recebido → SHA256(SHA256) ≠ hash esperado.
**Fix:** 1Password armazena a senha em **plaintext**; o ExternalSecret calcula `sha256sum` via
template ESO e gera `adminPasswordSha256`/`langfusePasswordSha256` como campos separados.

## ClickHouse — porta 9363 (Prometheus) não exposta por padrão

**Sintoma:** VMPodScrape com `port: "9363"` → `connection refused`.
**Causa:** suporte nativo a Prometheus existe, mas o endpoint não vem habilitado.
**Fix:** bloco `<prometheus>` (endpoint `/metrics`, port 9363, metrics/events/asynchronous_metrics
true) via `configuration.files` no CHI.

## Memgraph — métricas requerem Enterprise License

**Sintoma:** VMPodScrape 400 com `Memgraph must have an Enterprise License for providing
metrics!`.
**Causa:** o `/metrics` só existe na Enterprise.
**Fix:** remover o VMPodScrape do Memgraph. Sem dashboard de métricas na community.

## VMPodScrape — selectors incorretos (labels do operator)

**Sintoma:** `podScrape/observability/clickhouse 0/0 up` — sem endpoints.
**Causa:** os labels do selector não batem com os reais. O ClickHouse operator gera pods com
labels próprios (`clickhouse.altinity.com/*`); o CNPG usa `cnpg.io/cluster`.
**Fix:** `kubectl get pods -n data --show-labels` e ajustar os `matchLabels`. (Garage usa
`port: admin`/3903; Memgraph `port: http`.)

## VMPodScrape — operator não processa após TLS mismatch

Mesma família do churn de webhook: após o cert-manager rotacionar o cert do webhook, o operator
pode ficar com `tls: private key does not match public key` e não reconciliar scrapes. Fix:
`rollout restart` do operator (ver `runbooks/observability/`).

## Lição transversal

Stores de operator (Altinity, CNPG) têm labels próprios e cacheiam Secret na criação —
`--show-labels` antes do selector, `from_env`/template ESO pra senha. Garage tem quirks de S3
(alias global, region=garage, path-style, world-readable secrets). Métrica nova só aparece após
o operator/vmagent reler — ver `runbooks/observability/`.

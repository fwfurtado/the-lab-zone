---
tipo: setup
fase: 6
titulo: Plataforma de dados — Garage, CNPG, Valkey, ClickHouse, Redpanda, Qdrant, Memgraph
relacionado: [decisions/0009-data-platform-stores]
---

# Setup Fase 6 — Plataforma de dados

Provisiona os 7 stores stateful vazios e validados antes de qualquer app de negócio. Critério de
saída: 7 stores rodando, PVCs bound, smoke tests passando, backups/DR aplicáveis configurados e
métricas no Grafana/VictoriaMetrics.

## AppProject e pré-requisitos
Operators (CNPG wave 5, ClickHouse/Redpanda wave 6) no AppProject `core`; workloads no `data`. O
project `data` tem `observability` como destination adicional pros VMPodScrape.
Criar no vault `the-lab-zone` (antes do push): `garage`, `cnpg`, `valkey`, `clickhouse`,
`redpanda`, `qdrant`, `memgraph` + as keys S3 por serviço (`garage-cnpg`,
`garage-clickhouse`, `garage-qdrant`). O item `redpanda` deve conter `superuser-username`,
`superuser-password`, `bootstrap-password` e `console-password` para External Secrets.

## Ordem de deploy
```bash
kubectl apply -f projects/data.yaml
# operators sincronizam (core)
just garage init-layout --id=<NODE_ID>     # layout antes dos buckets
just buckets tf-init && just buckets tf-plan && just buckets tf-apply
just garage alias-buckets                  # alias GLOBAL (TF cria só local)
# keys por serviço + permissões (just garage generate-key / make-owner-of-bucket)
git add apps/ projects/ && git commit && git push   # ArgoCD synca por wave
```

## Validações
Garage: `just garage status` (role dc1, 100G) + `bucket list` (cnpg-wal, clickhouse-backup,
qdrant-snapshots, velero, langfuse). CNPG: `get cluster` healthy + `SELECT version()`. Valkey:
`PING` → PONG. ClickHouse: `SELECT 1` + teste de backup manual. Redpanda: cluster `Healthy`,
Console público só na LAN, sem auth de UI no primeiro corte (risco aceito), VMPodScrape `redpanda` UP em `/targets`.
Qdrant: `/collections` → `{"collections":[]}`. Memgraph: `RETURN 1` via Lab UI.
Primeiro PR do Redpanda não cria topics, users, schemas nem clients permanentes; só instala o
broker interno, Console, segredos via ESO e cobertura operacional pendente/auditável.
VMPodScrapes UP em `/targets`; dashboards Grafana (gnetIds 20417/14192/24603/763 + Garage +
Redpanda ConfigMap).

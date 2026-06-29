---
tipo: setup
fase: 6
titulo: Plataforma de dados — Garage, CNPG, Valkey, ClickHouse, Qdrant, Memgraph
relacionado: [decisions/0009-data-platform-stores]
---

# Setup Fase 6 — Plataforma de dados

Provisiona os 6 stores stateful vazios e validados antes de qualquer app de negócio. Critério de
saída: 6 stores rodando, PVCs bound, smoke tests passando, backups configurados, métricas no
Grafana.

## AppProject e pré-requisitos
Operators (CNPG wave 5, ClickHouse wave 6) no AppProject `core`; workloads no `data`. O project
`data` tem `observability` como destination adicional pros VMPodScrape.
Criar no vault `the-lab-zone` (antes do push): `garage`, `cnpg`, `valkey`, `clickhouse`,
`qdrant`, `memgraph` + as keys S3 por serviço (`garage-cnpg`, `garage-clickhouse`,
`garage-qdrant`).

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
`PING` → PONG. ClickHouse: `SELECT 1` + teste de backup manual. Qdrant: `/collections` →
`{"collections":[]}`. Memgraph: `RETURN 1` via Lab UI.
VMPodScrapes UP em `/targets`; dashboards Grafana (gnetIds 20417/14192/24603/763 + Garage
ConfigMap).

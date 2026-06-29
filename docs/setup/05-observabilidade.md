---
tipo: setup
fase: 5
titulo: Observabilidade — VictoriaMetrics, VictoriaLogs, Grafana, OTel
relacionado: [decisions/0008-observability-victoriametrics-single]
---

# Setup Fase 5 — Observabilidade

Primeiro consumidor real do tier `openebs-hostpath`. Critério de saída:
`https://grafana.lab.the-lab.zone` com cadeado verde mostrando métricas e logs; VMAlert
avaliando regras base com Alertmanager recebendo.

## Service names reais (pós-deploy)
| Componente | Service | Porta |
|---|---|---|
| VMSingle | `vmsingle-victoria-metrics-vmks` | 8428 |
| VMAgent | `vmagent-victoria-metrics-vmks` | 8429 |
| VMAlertmanager | `vmalertmanager-victoria-metrics-vmks` | 9093 |
| VictoriaLogs | `victoria-logs-vls-server` | 9428 |

## Pré-requisito (1Password vault `the-lab-zone`)
Item `grafana` com `username: admin` e `password` forte.

## Ordem de aplicação
```bash
kubectl apply -f projects/observability.yaml   # AppProject primeiro
git add apps/observability/ projects/observability.yaml && git commit && git push
# waves: -1 namespace; 1 victoria-metrics/victoria-logs; 2 grafana/otel-collector
```

## Validação por componente
- VMSingle: `curl '.../api/v1/query?query=up' | jq '.data.result|length'` > 0.
- VictoriaLogs: `curl '.../select/logsql/query?query=*&limit=5'` retorna logs.
- OTel: um pod por nó, todos Running.
- Grafana: HTTPRoute Accepted=True; datasources VM/VLogs Test OK; dashboards 15661/1860 com dados.

**Critério de saída:** apps Synced/Healthy; pods Running; PVCs Bound.

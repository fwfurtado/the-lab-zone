---
tipo: adr
numero: 8
titulo: Observabilidade com VictoriaMetrics Single + VictoriaLogs + OTel
status: aceito
fases: [5]
relacionado: [runbooks/observability]
---

# ADR-0008 — Stack de observabilidade VictoriaMetrics

## Status
Aceito (Fase 5).

## Contexto
Métricas, logs e alertas num homelab single-node. A partir desta fase, tudo que nasce já
nasce monitorado.

## Decisão
- **Métricas:** VictoriaMetrics **Single** (HA seria fake-HA no mesmo disco).
- **Logs:** VictoriaLogs (sem dependência de object storage externo — Loki exigiria
  MinIO/Garage, que só chega na Fase 6).
- **Coleta de logs:** OTel Collector DaemonSet (`otelcol-k8s`, preset `logsCollection`) —
  Fluent Bit foi removido do chart do victoria-logs.
- **Alertas:** VMAlert + Alertmanager integrado ao chart `victoria-metrics`.
- **Ingestão:** OTLP over HTTP pro VMSingle (`/opentelemetry` nativo) e VictoriaLogs.
- **Grafana:** app separado (controle independente de versão/config).

## Consequências
- `otelcol-k8s` é slim: sem `prometheusremotewrite`, usa `otlphttp` pra tudo.
- O webhook do VM operator precisa de cert-manager sob ArgoCD (senão churna — ver runbook
  observability).
- Traces ficam pra Fase 7 (com LiteLLM/Langfuse).

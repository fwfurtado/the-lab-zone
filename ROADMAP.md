|Fase|Objetivo / entrega|Componentes principais|Dependências & notas-chave|
|--- |--- |--- |--- |
|5 — Observabilidade|Métricas, logs e alertas. Primeiro consumidor real do tier
                quente.|VictoriaMetrics, VictoriaLogs, Grafana, Alertmanager, OTel
                Collector|Depende da Fase 4 (PVs hostpath). VM substitui
                Prometheus+Thanos.
                Traces ficam pra depois (VictoriaTraces/Tempo)
                — relevante pro
                LiteLLM→OTel
                na Fase 7.|
|6 — Plano de dados|Todos os stores stateful, validados vazios,
                antes de qualquer app em cima.|Garage → CNPG → Valkey → ClickHouse → Qdrant → Memgraph|Depende da Fase 4. Garage primeiro (destino de
                backup de todos). Valkey
                noeviction
                (fila Langfuse). ClickHouse+Postgres em
                UTC (req Langfuse). CNPG single-instance +
                WAL→Garage/B2 (PITR). Cada store validado isolado.|
|7 — Stack de AI|RAG + inferência + orquestração de agentes + observabilidade de
                LLM.|Ollama (P40 + nó 3090), LiteLLM, LightRAG, Open WebUI,
                ToolHive (runtime MCP),
                LangGraph (orquestração),
                Langfuse v3|Depende da Fase 6 (consome CNPG, Qdrant, Memgraph, Valkey,
                ClickHouse, Garage S3). Langfuse exige
                Postgres+ClickHouse+Valkey+S3 (peso aceito). LangGraph com
                checkpointer no CNPG. ToolHive via operator (CRDs
                MCPServer).|
|8 — Analytics / streaming (opcional)|Camada analítica/ELT, só se a necessidade for real.|ClickHouse, dbt (+ Redpanda/Debezium se houver CDC)|Opcional. O ClickHouse
                pode ser o mesmo instanciado pro Langfuse na
                Fase 6/7 — reuso, não duplicação.|
|9 — Segurança + SSO|Identidade, varredura, runtime security e isolamento de rede.|Authentik (OIDC), Trivy, Tetragon, NetworkPolicies default-deny|Authentik destrava SSO (incl. CLI do ArgoCD via SSO — lembra do
                --core
                de hoje como ponte).
                NetworkPolicies por último, pra não quebrar o
                que já subiu.|
|10 — DR|Backup/restore validado de ponta a ponta.|Velero/restic → B2|Teste de restore completo, não só backup. Fecha
                o ciclo de resiliência aberto na Fase 0.|

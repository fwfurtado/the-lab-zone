CONTROLLER := "https://pinot.lab.the-lab.zone"
TABLES_DIR := "apps/data/pinot/tables"

# Schema e table config são objetos da API do Pinot (control plane no ZK), não
# recursos k8s -- GitOps aqui é: JSON no repo + apply idempotente via recipe.
# A senha SASL é injetada do 1Password no apply (o Git guarda o placeholder);
# ela fica visível na API/UI do Pinot -- aceito no homelab, documentado.

@apply-schema:
    curl -sf -X POST "{{CONTROLLER}}/schemas" -H "Content-Type: application/json" \
      -d @{{TABLES_DIR}}/accounts.schema.json && echo "schema accounts OK"

@update-schema:
    curl -sf -X PUT "{{CONTROLLER}}/schemas/accounts" -H "Content-Type: application/json" \
      -d @{{TABLES_DIR}}/accounts.schema.json && echo "schema accounts atualizado"

@apply-table:
    #!/usr/bin/env bash
    set -euo pipefail
    PASS=$(op read "op://the-lab-zone/redpanda-pinot/password")
    sed "s|\${KAFKA_PASSWORD}|${PASS}|" {{TABLES_DIR}}/accounts.table.json \
      | curl -sf --max-time 90 -X POST "{{CONTROLLER}}/tables" -H "Content-Type: application/json" -d @- \
      && echo "" && echo "tabela accounts_REALTIME OK"

@update-table:
    #!/usr/bin/env bash
    set -euo pipefail
    PASS=$(op read "op://the-lab-zone/redpanda-pinot/password")
    sed "s|\${KAFKA_PASSWORD}|${PASS}|" {{TABLES_DIR}}/accounts.table.json \
      | curl -sf -X PUT "{{CONTROLLER}}/tables/accounts" -H "Content-Type: application/json" -d @- \
      && echo "" && echo "tabela accounts_REALTIME atualizada"

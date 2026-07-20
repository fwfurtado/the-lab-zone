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

validation:
    @ echo "Medição $(date)"
    @ echo 'RCLONE_CONFIG_GARAGE_ACCESS_KEY_ID="op://the-lab-zone/garage-spark/accessKeyId"' >> .env.tpl
    @ echo 'RCLONE_CONFIG_GARAGE_SECRET_ACCESS_KEY="op://the-lab-zone/garage-spark/secretKey"' >> .env.tpl
    op run --env-file .env.tpl -- rclone size garage:lakehouse --config ""        # Delta: dados + _delta_log + _change_data + checkpoints
    @ git restore .env.tpl
    @ echo "--- --- ---"
    @ echo 'RCLONE_CONFIG_GARAGE_ACCESS_KEY_ID="op://the-lab-zone/garage-pinot/accessKeyId"' >> .env.tpl
    @ echo 'RCLONE_CONFIG_GARAGE_SECRET_ACCESS_KEY="op://the-lab-zone/garage-pinot/secretKey"' >> .env.tpl
    op run --env-file .env.tpl -- rclone size garage:pinot --config ""            # deep store: segmentos selados
    @ git restore .env.tpl
    @ echo "--- --- ---"
    kubectl -n data exec redpanda-0 -c redpanda -- rpk topic describe-storage accounts.cdf \
        -X user=$(op read "op://the-lab-zone/redpanda/superuser-username") -X pass=$(op read "op://the-lab-zone/redpanda/superuser-password") -X sasl.mechanism=SCRAM-SHA-512 -X tls.enabled=true -X tls.insecure_skip_verify=true
    @ echo "--- --- ---"
    kubectl -n data exec pinot-server-0 -- df -h /var/pinot/server/data | tail -1
    @echo "--- END ---"

# infra/prod/authentik/sso/mod.just
# Mesmo padrão do vm/mod.just: op run + .env.tpl central (4 níveis acima).

@tf-init:
    op run --env-file=../../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../../.env.tpl -- terraform plan

@tf-apply:
    op run --env-file=../../../../.env.tpl -- terraform apply

@tf-destroy:
    op run --env-file=../../../../.env.tpl -- terraform destroy

@fmt:
    terraform fmt

# ── Geração dos client_secrets (1Password = fonte única) ────────────────────
# Cria/atualiza o item oidc-<app> no vault the-lab-zone com client_id + client_secret.
# O MESMO item é lido pelo TF (tf-apply) e pelo ESO no cluster.
# Uso: just gen-secret argocd
@gen-secret app:
    #!/usr/bin/env bash
    set -euo pipefail
    cid="{{ app }}"
    csec="$(openssl rand -hex 32)"
    item="oidc-{{ app }}"
    if op item get "$item" --vault the-lab-zone >/dev/null 2>&1; then
      op item edit "$item" --vault the-lab-zone "client_id=$cid" "client_secret=$csec"
      echo "atualizado: $item"
    else
      op item create --category "API Credential" --vault the-lab-zone \
        --title "$item" "client_id=$cid" "client_secret=$csec"
      echo "criado: $item"
    fi

# Gera os secrets de todos os apps OIDC de uma vez.
@gen-all-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    for app in argocd grafana open-webui langfuse harbor forgejo; do
      just gen-secret "$app"
    done

# Pega os issuers pra colar no values de cada app do lado-cluster.
@issuers:
    op run --env-file=../../../../.env.tpl -- terraform output -json issuers

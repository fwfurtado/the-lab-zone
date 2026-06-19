harbor_url := "https://harbor.mgmt.the-lab.zone"

@tf-init:
    op run --env-file=../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../.env.tpl -- terraform plan

@tf-apply:
    op run --env-file=../../../.env.tpl -- terraform apply -auto-approve

@tf-destroy:
    op run --env-file=../../../.env.tpl -- terraform destroy

# Cria os endpoints de registry upstream + os projetos proxy cache.
# Rode UMA vez depois que o Harbor estiver de pe (e sempre que faltar algum).
# Idempotente: ignora 409 (ja existe). Le segredos via op.
@proxy-init:
    op run --env-file=../../../.env.tpl -- bash proxy-init.sh

@check:
    @echo "==> health"
    curl -fsS {{harbor_url}}/api/v2.0/health | jq '.status'
    @echo "==> registries"
    curl -fsS -u "admin:$(op read 'op://homelab/Harbor/admin-password')" {{harbor_url}}/api/v2.0/registries | jq -r '.[].name'
    @echo "==> projects"
    curl -fsS -u "admin:$(op read 'op://homelab/Harbor/admin-password')" {{harbor_url}}/api/v2.0/projects | jq -r '.[].name'

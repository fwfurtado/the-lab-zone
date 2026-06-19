forgejo_url := "https://git.mgmt.the-lab.zone"

@tf-init:
    op run --env-file=../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../.env.tpl -- terraform plan

@tf-apply:
    op run --env-file=../../../.env.tpl -- terraform apply

@tf-destroy:
    op run --env-file=../../../.env.tpl -- terraform destroy

@check:
    @echo "==> versao/health"
    curl -fsS {{forgejo_url}}/api/v1/version | jq .
    @echo "==> SSH"
    nc -vz git.mgmt.the-lab.zone 2222

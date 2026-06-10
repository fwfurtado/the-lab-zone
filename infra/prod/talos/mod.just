@init:
    op run --env-file=../../../.env.tpl -- terraform init

@plan:
    op run --env-file=../../../.env.tpl -- terraform plan

@apply:
    op run --env-file=../../../.env.tpl -- terraform apply

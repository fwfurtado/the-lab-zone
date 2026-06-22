@tf-init:
    op run --env-file=../../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../../.env.tpl -- terraform plan

@tf-apply:
    op run --env-file=../../../../.env.tpl -- terraform apply

@tf-destroy:
    op run --env-file=../../../../.env.tpl -- terraform destroy

# Lista nome -> bucket_id (o id ajuda a escopar a app key de backup no console).
@buckets:
    op run --env-file=../../../../.env.tpl -- terraform output -json buckets | jq .

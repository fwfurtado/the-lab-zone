export AWS_DEFAULT_REGION := "garage"
@tf-init:
    op run --env-file=../../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../../.env.tpl -- terraform plan

@tf-apply:
    op run --env-file=../../../../.env.tpl -- terraform apply

@tf-destroy:
    op run --env-file=../../../../.env.tpl -- terraform destroy

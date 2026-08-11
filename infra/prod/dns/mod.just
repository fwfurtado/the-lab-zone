@tf-init:
    op run --env-file=../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../.env.tpl -- terraform plan

@tf-apply:
    echo "==> [1/3] Applying Terraform to create DNS container..."
    op run --env-file=../../../.env.tpl -- terraform apply \
    -target=proxmox_virtual_environment_container.dns \
    -target=terraform_data.pdns_provision

    echo "==> [2/3] Checking PDNS API..."
    op run --env-file=../../../.env.tpl -- curl -s http://10.40.1.53:8081/api/v1/servers -H "X-API-Key: ${TF_VAR_pdns_api_key}" | head

    echo "==> [3/3] Applying Terraform to configure PDNS..."
    op run --env-file=../../../.env.tpl -- terraform apply

@tf-destroy:
    op run --env-file=../../../.env.tpl -- terraform destroy

@check:
    dig @10.40.1.53 hubble.lab.the-lab.zone +short
    dig @10.40.1.53 nas.mgmt.the-lab.zone +short
    curl -s http://10.40.1.53:8081/metrics | head -5

# Instala o zonefile de break-glass no pdns-recursor LOCAL desta maquina
@breakglass-install:
    test -f out/mgmt.the-lab.zone.zone || { echo "==> rode 'just tf-apply' antes"; exit 1; }
    sudo install -o pdns -g pdns -m 0644 out/mgmt.the-lab.zone.zone /etc/powerdns/zones/mgmt.the-lab.zone.zone
    sudo rec_control reload-zones
    dig @127.0.0.1 idrac.mgmt.the-lab.zone +short

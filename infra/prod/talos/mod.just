@tf-init:
    op run --env-file=../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../.env.tpl -- terraform plan

@tf-apply:
    op run --env-file=../../../.env.tpl -- terraform apply

@tf-destroy:
    op run --env-file=../../../.env.tpl -- terraform destroy

@gen: gensecret
    talhelper genconfig > /dev/null  2>&1
    talhelper gencommand apply --extra-flags --insecure
    echo "[WARNING] Change the node IP to the actual DHCP IP of the node"


@bootstrap:
    talosctl config endpoint --talosconfig=./clusterconfig/talosconfig 10.40.6.11 10.40.6.12 10.40.6.13
    talosctl bootstrap --talosconfig=./clusterconfig/talosconfig -n 10.40.6.11

@watch-health:
    talosctl health --talosconfig=./clusterconfig/talosconfig -n 10.40.6.11 --wait-timeout 10m

@kubeconfig:
    talosctl kubeconfig --talosconfig=./clusterconfig/talosconfig -n 10.40.6.11
    echo "Kubeconfig was written to ~/.kube/config"

[private]
@gensecret:
    if [ "{{path_exists('talsecret.yaml')}}" = "false" ]; then \
        talhelper gensecret > talsecret.yaml; \
        sops -e -i talsecret.yaml; \
    fi

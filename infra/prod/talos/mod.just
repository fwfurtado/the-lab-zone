PROXMOX_HOST := "root@10.40.0.200"
TALOS_CONTROL_PLANE_NODES := "10.40.6.11,10.40.6.12,10.40.6.13"
TALOS_ENDPOINT := "10.40.6.11"

@tf-init:
    op run --env-file=../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../.env.tpl -- terraform plan

@tf-apply:
    op run --env-file=../../../.env.tpl -- terraform apply

@tf-destroy:
    op run --env-file=../../../.env.tpl -- terraform destroy

@gen: gensecret
    talhelper genconfig
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

@proxmox-log-receiver-install:
    scp ../proxmox/talos-log-receiver.service {{PROXMOX_HOST}}:/etc/systemd/system/talos-log-receiver.service
    scp ../proxmox/talos-remote.logrotate {{PROXMOX_HOST}}:/etc/logrotate.d/talos-remote
    ssh {{PROXMOX_HOST}} -- systemctl daemon-reload
    ssh {{PROXMOX_HOST}} -- systemctl enable --now talos-log-receiver.service

@proxmox-log-receiver-status:
    ssh {{PROXMOX_HOST}} -- systemctl status talos-log-receiver.service --no-pager
    ssh {{PROXMOX_HOST}} -- ss -ltnp 'sport = :1514'
    ssh {{PROXMOX_HOST}} -- du -h /var/log/talos/control-plane.jsonl

[private]
@gensecret:
    if [ "{{path_exists('talsecret.yaml')}}" = "false" ]; then \
        talhelper gensecret > talsecret.yaml; \
        sops -e -i talsecret.yaml; \
    fi

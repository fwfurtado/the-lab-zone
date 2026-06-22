authentik_ip  := "10.40.1.12"
authentik_url := "https://auth.mgmt.the-lab.zone"

@tf-init:
    op run --env-file=../../../.env.tpl -- terraform init

@tf-plan:
    op run --env-file=../../../.env.tpl -- terraform plan

@tf-apply:
    op run --env-file=../../../.env.tpl -- terraform apply

@tf-destroy:
    op run --env-file=../../../.env.tpl -- terraform destroy

# Health do Authentik (live/ready). 'ready' só fica 200 depois das migrations.
@check:
    @echo "==> live"
    curl -fsS {{authentik_url}}/-/health/live/ -o /dev/null -w '%{http_code}\n'
    @echo "==> ready"
    curl -fsS {{authentik_url}}/-/health/ready/ -o /dev/null -w '%{http_code}\n'

# Dispara um backup AGORA e mostra o resultado (valida o caminho pg_dump -> B2).
@backup-now:
    ssh root@{{authentik_ip}} 'systemctl start authentik-backup.service && journalctl -u authentik-backup.service -n 25 --no-pager'

# Logs dos containers.
@logs:
    ssh root@{{authentik_ip}} 'cd /opt/authentik && docker compose logs --tail 60'

# Log do provisionamento (debug da 1a subida).
@provision-log:
    ssh root@{{authentik_ip}} 'tail -n 60 /var/log/authentik-provision.log'

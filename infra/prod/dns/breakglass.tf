# Hosts file de break-glass do plano de GESTAO.
#
# Renderizado a partir da MESMA fonte de verdade dos registros publicados no PDNS
# (var.mgmt_records), para ser consumido pelo sing-box como servidor DNS do tipo
# "hosts". Objetivo: resolver idrac/pve/nas mesmo com o T630 - e portanto a LXC de
# DNS - fora do ar, sem duplicar os IPs a mao.
#
# A regra de sufixo .mgmt.the-lab.zone no sing-box aponta pra esse arquivo e vem
# ANTES da regra .the-lab.zone; *.lab.the-lab.zone continua indo pro 10.40.1.53.

resource "local_file" "mgmt_breakglass_hosts" {
  filename        = "${path.module}/out/hosts.mgmt"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/hosts.mgmt.tftpl", {
    domain  = "mgmt.the-lab.zone"
    records = var.mgmt_records
  })
}

output "mgmt_breakglass_hosts_path" {
  description = "Hosts file renderizado; instalar na workstation com `just breakglass-install`"
  value       = local_file.mgmt_breakglass_hosts.filename
}

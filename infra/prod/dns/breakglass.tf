# Zonefile de break-glass do plano de GESTAO.
#
# Renderizado a partir da MESMA fonte de verdade dos registros publicados no PDNS
# (var.mgmt_records), para ser servido como auth-zone pelo pdns-recursor local da
# workstation. Objetivo: resolver idrac/pve/nas mesmo com o T630 - e portanto a
# LXC de DNS - fora do ar, sem duplicar os IPs a mao no /etc/hosts.
#
# auth_zones tem precedencia sobre forward_zones no recursor, entao mgmt.the-lab.zone
# passa a ser servido local; *.lab.the-lab.zone continua indo pro 10.40.1.53.

resource "local_file" "mgmt_breakglass_zone" {
  filename        = "${path.module}/out/mgmt.the-lab.zone.zone"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/mgmt.zone.tftpl", {
    origin  = "mgmt.the-lab.zone."
    records = var.mgmt_records
  })
}

output "mgmt_breakglass_zone_path" {
  description = "Zonefile renderizado; instalar na workstation com `just breakglass-install`"
  value       = local_file.mgmt_breakglass_zone.filename
}

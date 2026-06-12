resource "powerdns_zone" "the_lab_zone" {
  depends_on  = [terraform_data.pdns_provision]
  name        = "the-lab.zone."
  kind        = "Native"
  nameservers = ["dns.mgmt.the-lab.zone."]
}

# Plano de APLICAÇÃO: wildcard → Gateway pinado
resource "powerdns_record" "lab_wildcard" {
  zone    = powerdns_zone.the_lab_zone.name
  name    = "*.lab.the-lab.zone."
  type    = "A"
  ttl     = 300
  records = [var.lab_gateway_lb_ip]
}

# Plano de GESTÃO: 1:1 estáticos
resource "powerdns_record" "mgmt" {
  for_each = var.mgmt_records
  zone     = powerdns_zone.the_lab_zone.name
  name     = "${each.key}.mgmt.the-lab.zone."
  type     = "A"
  ttl      = 300
  records  = [each.value]
}

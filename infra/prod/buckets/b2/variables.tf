# Buckets B2 gerenciados por este módulo. Genérico de propósito: backups offsite
# de outros serviços no futuro entram como novas entradas no map — um lugar só
# pra todo bucket B2, simétrico ao módulo `buckets` (que cuida do Garage).
#
# NÃO gerencie aqui o bucket de state (`the-lab-zone-tf-state`): ele é bootstrap
# e o próprio state deste módulo vive nele (chicken-and-egg).
#
# retention_days = backstop server-side. O B2 ESCONDE o objeto N dias após o
# upload e DELETA 1 dia depois (~N+1 até sumir de vez). É cinto-e-suspensório:
# a poda explícita (keep N) vive no script de backup de cada serviço; este
# lifecycle só atua se o script parar de rodar. Deixe-o MAIS FROUXO que o keep
# do script (ex.: script mantém 14 diários, backstop em 30 dias).
variable "buckets" {
  type = map(object({
    retention_days = number
  }))

  default = {
    "the-lab-zone-authentik-backup" = {
      retention_days = 30 # script do Authentik mantém 14; isto é só o backstop
    }
  }
}

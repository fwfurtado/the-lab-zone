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
    # --- Fase 10 (DR) -----------------------------------------------------
    # Espelho offsite de TODOS os backups que hoje só vivem no Garage (on-site,
    # no próprio T630). O CronWorkflow `offsite-sync` faz `rclone copy/sync`
    # Garage -> b2:the-lab-zone-dr/<bucket>, preservando o layout 1:1 (o path
    # interno é idêntico ao do Garage; só muda o endpoint no restore).
    #
    # 60d > poda do Garage (cnpg-wal 7d): de propósito. O off-site guarda MAIS
    # histórico que o tier on-site — é a tábua de salvação do D4b/D4c.
    "the-lab-zone-dr" = {
      retention_days = 60
    }

    # Bucket dedicado do Velero (o BSL gerencia o próprio layout: backups/,
    # restores/, kopia/...). Separado do espelho pra não misturar dono de path.
    "the-lab-zone-velero" = {
      retention_days = 60
    }
  }
}

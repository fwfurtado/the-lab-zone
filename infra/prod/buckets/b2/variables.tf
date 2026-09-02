# Buckets B2 gerenciados por este módulo. Genérico de propósito: backups offsite
# de outros serviços no futuro entram como novas entradas no map — um lugar só
# pra todo bucket B2, simétrico ao módulo `buckets` (que cuida do Garage).
#
# NÃO gerencie aqui o bucket de state (`the-lab-zone-tf-state`): ele é bootstrap
# e o próprio state deste módulo vive nele (chicken-and-egg).
#
# lifecycle_rules define backstop server-side por prefix. O B2 ESCONDE o objeto
# N dias após o upload e DELETA 1 dia depois (~N+1 até sumir de vez). É
# cinto-e-suspensório: a poda explícita (keep N) vive no script de backup de
# cada serviço; este lifecycle só atua se o script parar de rodar. Deixe-o MAIS
# FROUXO que o keep do script.
variable "buckets" {
  type = map(object({
    lifecycle_rules = list(object({
      prefix         = string
      retention_days = number
    }))
  }))

  default = {
    "the-lab-zone-authentik-backup" = {
      lifecycle_rules = [
        {
          prefix         = ""
          retention_days = 30
        } # script mantém 14; backstop em 30
      ]
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
      lifecycle_rules = [
        {
          prefix         = ""
          retention_days = 60
        }
      ]
    }

    # Bucket dedicado do Velero. Só backups/ e restores/ são metadata
    # descartável; kopia/ é repositório de longa duração e fica sem regra.
    "the-lab-zone-velero" = {
      lifecycle_rules = [
        {
          prefix         = "backups/"
          retention_days = 60
        },
        {
          prefix         = "restores/"
          retention_days = 60
        }
      ]
    }

    "the-lab-zone-haos-backup" = {
      lifecycle_rules = [
        {
          prefix         = ""
          retention_days = 60
        }
      ]
    }
  }
}

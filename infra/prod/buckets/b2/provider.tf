terraform {
  required_version = "1.15.8"

  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "0.10.0"
    }
  }
}

# Credenciais via env (injetadas pelo `op run`): B2_APPLICATION_KEY_ID e
# B2_APPLICATION_KEY. Aqui usamos a MASTER key do B2 — ela precisa de capability
# pra criar/alterar buckets e lifecycle.
#
# A app key ESCOPADA do backup (writeFiles/listFiles/deleteFiles num único
# bucket) NÃO é gerenciada aqui de propósito (abordagem "b"): ela é criada à mão
# no console do B2 e guardada no 1Password, preservando o fluxo one-way
# `op -> script` do repo e mantendo o material de chave fora do state.
provider "b2" {}

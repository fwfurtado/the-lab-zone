---
tipo: runbook
componente: secrets-eso
tags: [1password-connect, external-secrets, replica-stale, connect-sync, force-sync]
fases: [2]
---

# 1Password Connect + ESO: réplica stale

## Réplica do 1Password Connect congelada (stale)

**Sintoma:** ExternalSecret em `SecretSyncedError` com
`key not found in 1Password Vaults: test-secret in: map[the-lab-zone:1]`, mas
`op read "op://the-lab-zone/test-secret/password"` funciona na CLI.

**Armadilha do diagnóstico:** a CLI autentica como o **operador** (vê a cloud); o ESO
pergunta ao **Connect**, que serve uma **réplica local**. A CLI funcionando não prova nada
sobre a visão do Connect.

**Diagnóstico definitivo — perguntar diretamente ao Connect:**
```bash
TOKEN=$(kubectl -n external-secrets get secret op-connect-token -o jsonpath='{.data.token}' | base64 -d)
# pod curl efêmero →
curl -s -H "Authorization: Bearer $TOKEN" http://onepassword-connect:8080/v1/vaults
# vault presente com "items": 0 + logs do connect-sync mostrando SÓ /health e
# /heartbeat (zero atividade de sync) = réplica congelada
```

**Causa raiz:** o container `connect-sync` mantém sessão de longa duração com a cloud por
onde chegam eventos; a sessão pode **estagnar silenciosamente** (o health check mede
"processo responde", não "dados frescos"). Vault/item recém-criados próximos à criação do
server agravam.

**Fix:**
```bash
kubectl -n external-secrets rollout restart deploy/onepassword-connect
kubectl -n default annotate externalsecret <nome> force-sync=$(date +%s)
```

**Nota de segurança:** o output de pods de debug fica nos logs (incluindo o Bearer token).
Pra token de smoke-test, ok; rotacionar via `op connect token` se for o caso.

**Lição:** o que a CLI `op` vê ≠ o que o Connect serve. Diagnosticar a cadeia de secrets
sempre perguntando ao Connect (réplica local), não à cloud. Item no vault errado é
invisível pro ESO — o Connect server tem acesso **apenas** ao vault `the-lab-zone`.

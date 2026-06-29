---
tipo: runbook
componente: gateway-dns
tags: [gateway-api, cert-manager, lb-ipam, vap, powerdns, split-horizon, recursor, terraform, remote-exec]
fases: [3, 9]
relacionado: [runbooks/cilium-rede]
---

# Gateway API, cert-manager e DNS split-horizon

Plano de ingress TLS: Gateway wildcard (Cilium), cert wildcard (cert-manager/Cloudflare) e
nomes (PowerDNS auth + recursor).

## VAP `safe-upgrades` bloqueia CRDs experimental

**Sintoma:** `kubectl apply` dos CRDs experimental falha em vários: `ValidatingAdmissionPolicy
'safe-upgrades' ... Installing experimental CRDs on top of standard channel CRDs is
prohibited`. E `apiVersion not set, kind not set` no `kustomization.yaml`.
**Causa:** o próprio Gateway API instala uma VAP que proíbe trocar CRDs standard→experimental
in-place. E o `apply -f <dir>/` tentava aplicar o `kustomization.yaml` como manifesto.
**Diagnóstico:** `tcproutes`/`udproutes` passaram (sem contraparte standard); os que falharam
(`gateways`, `httproutes`, `tlsroutes`) já existiam como standard.
**Fix:** deletar a VAP e o binding (`kubectl delete validatingadmissionpolicy[binding]
safe-upgrades.gateway.networking.k8s.io`), vendorizar **só os 9 CRDs** num `manifests/` plano
(sem `kustomization.yaml`, sem VAP, sem mesh). **Não** versionar a VAP — ela reintroduz o
bloqueio na reconciliação do ArgoCD.

## cert-manager: namespace não encontrado

**Sintoma:** app `Failed`: `namespaces "cert-manager" not found, error running rbacReconcile`.
**Causa:** o chart **não cria o próprio namespace**; o `destination.namespace` só diz onde
colocar os recursos. O `kubectl auth reconcile` dos RBACs falha sem o namespace.
**Fix:** `CreateNamespace=true` no `syncPolicy.syncOptions` (ou Namespace explícito com
`sync-wave: "-1"`).

## Gateway degraded: `InvalidCertificateRef` (enableGatewayAPI)

**Sintoma:** Gateway `Degraded`, listener com `Invalid CertificateRef, Secret
"wildcard-lab-tls" not found`.
**Causa:** a integração Gateway API do cert-manager vem **desligada** por padrão (≥1.15). A
annotation `cert-manager.io/cluster-issuer` no Gateway é ignorada, o Certificate não é criado.
**Fix:** `config.enableGatewayAPI: true` no values. O cert-manager checa o suporte **só no
boot** — o sync rola o Deployment e ele pega o flag. Garantir que os CRDs do Gateway API já
existam quando ele reinicia.

## Gateway recebe `.0` em vez do IP fixo (pin no lugar errado)

**Sintoma:** `cilium-gateway-main` com EXTERNAL-IP `10.40.7.0`; `arping`/`curl` no `.10` falham.
**Causa:** o pin `lbipam.cilium.io/ips` estava em `metadata.annotations`, que o Cilium **não
propaga** pro Service derivado. O LB-IPAM ignorou e atribuiu o primeiro IP do pool (`.0` — que
ainda por cima é o endereço de rede, reservado).
**Fix:** mover o pin para `spec.infrastructure.annotations`. O Cilium só propaga annotations de
`spec.infrastructure` pro Service derivado.

## `curl` não resolve via Cloudflare (comportamento esperado do split-horizon)

**Sintoma:** `curl https://hubble.lab.the-lab.zone` → "could not resolve host", mesmo com
`dig @10.40.1.53` funcionando.
**Causa:** esperado. O `*.lab → 10.40.7.10` existe só no PowerDNS interno; o Cloudflare
hospeda só a zona pública (pro DNS-01 do ACME) e não tem registro `lab.` (nem deveria — IP
privado). A máquina ainda usava resolver público.
**Fix (teste):** `curl --resolve hubble.lab.the-lab.zone:443:10.40.7.10 ...`. **Fix
(definitivo):** apontar os clientes da LAN pro PowerDNS.

## PowerDNS auth-only não pode ser o resolver da LAN

**Sintoma:** apontar a máquina pra `10.40.1.53` quebraria a internet — `dig google.com
@10.40.1.53` → `REFUSED`.
**Causa:** rodando só o `pdns` (Authoritative), que não recursa. A lista de DNS do SO não faz
failover num REFUSED (só num no-response).
**Fix:** adicionar o `pdns-recursor` na frente (recursor na :53, auth em `127.0.0.1:5300`,
forward de `the-lab.zone` pro auth, recursão raiz pro resto). Apontar a máquina **só** pra
`10.40.1.53`.

## `remote-exec` não re-roda; `local-port` e config do Recursor

Três tropeços ao adicionar o recursor via Terraform:
- **(a) Provisioner não re-roda.** `remote-exec` só dispara na criação. O `terraform_data`
  com `triggers_replace = [api_key, dns_ip]` não muda ao editar o script. **Fix:** extrair o
  `inline` pra um `local` e `triggers_replace = [sha1(join("\n", local.pdns_script))]` —
  re-roda quando o script muda, contra o mesmo LXC, sem recriar.
- **(b) `pdns` não sobe.** PowerDNS auth recente rejeita `local-port` separado. **Fix:**
  `local-address=127.0.0.1:5300` (porta embutida).
- **(c) `pdns-recursor` não sobe.** Recursor 5.x não aceita mais old-style `key=value`. **Fix:**
  escrever `/etc/powerdns/recursor.yml` em YAML (`incoming.listen`, `incoming.allow_from`,
  `recursor.forward_zones`) e remover o `recursor.conf` antigo.
- **Lição:** o auth continua old-style; **só o Recursor** virou YAML. Pra ver o fatal real do
  recursor (journal vazio por `--disable-syslog`), rodar em foreground:
  `pdns_recursor --daemon=no --write-pid=no --config-dir=/etc/powerdns`.

## DNS split-horizon + wildcard catch-all mascarando NXDOMAIN (Harbor/VM mgmt)

**Sintoma:** "failed to verify connection"; `getent` resolvia `auth.mgmt.the-lab.zone` pra IP
errado, cert não batia.
**Causa:** a VM usava a UDR como DNS, que não resolve `*.mgmt`. NXDOMAIN + append do search
domain + um **wildcard catch-all** apontou o nome inventado pro IP errado.
**Fix:** apontar `dns.servers` da VM pro PowerDNS (10.40.1.53) — quem tem a verdade do
split-horizon.
**Lição:** wildcard catch-all é perigoso — mascara NXDOMAIN com IP/cert errados em vez de
falhar limpo. **Erro de TLS pode ser sintoma de DNS, não de certificado.**

## Lição transversal

O `issuer` do discovery e o IP do Gateway têm que casar com o que **cada componente** espera
e propaga. Annotations do Cilium: pin de IP em `spec.infrastructure`, issuer em `metadata`.
cert-manager checa suporte só no boot. Split-horizon: recursor na frente, auth atrás.

---
tipo: setup
fase: 3
titulo: Ingress TLS — cert-manager, Gateway API, DNS split-horizon
relacionado: [decisions/0004-gateway-api-canal-experimental, decisions/0005-split-horizon-powerdns, decisions/0006-cert-wildcard-dns01-cloudflare]
---

# Setup Fase 3 — Ingress TLS

Objetivo: expor serviços em `https://<svc>.lab.the-lab.zone` com cert válido, sem port-forward.
Critério de saída da fase: `https://hubble.lab.the-lab.zone` abre com cadeado verde (cert de
produção), pelo DNS interno.

Ordem de aplicação (importa): CRDs do Gateway API **antes** do cert-manager bootar e **antes**
do Cilium operator registrar o controller de Gateway.

## 3.1 CRDs do Gateway API (canal experimental)
Vendorizar os 9 CRDs experimental da v1.5.1 em `apps/core/gateway-api-crds/manifests/` (sem
`kustomization.yaml`, sem VAP, sem mesh).
```bash
kubectl apply --server-side --force-conflicts -f apps/core/gateway-api-crds/manifests/
```
Exit: `tlsroutes` lista `v1alpha2 served=true`; GatewayClass `cilium` Accepted=True; operator
sai do CrashLoop.

## 3.2 cert-manager + issuers + token Cloudflare
`config.enableGatewayAPI: true` no values; app com `CreateNamespace=true`; ExternalSecret do
token Cloudflare no ns `cert-manager`; dois ClusterIssuers (staging + prod).
Exit: cert-manager Synced/Healthy, ambos issuers Ready, secret do token presente.

## 3.3 Gateway wildcard
Gateway `main` no ns `gateway`, listener HTTPS wildcard `*.lab.the-lab.zone`. Pin do IP em
`spec.infrastructure.annotations` (`lbipam.cilium.io/ips: 10.40.7.10`); annotation do issuer
(começar em staging) em `metadata.annotations`.
Exit: `cilium-gateway-main` com EXTERNAL-IP `10.40.7.10`, Gateway Programmed=True, secret
`wildcard-lab-tls` presente (staging).

## 3.4 L2 announcement
`CiliumL2AnnouncementPolicy` casando o device real (`^ens[0-9]+$`); o lease nasce quando há um
Service LB com IP. Exit: lease com holder + `arping 10.40.7.10` responde na LAN.

## 3.5 HTTPRoute do Hubble (smoke test)
HTTPRoute no ns `kube-system` (mesmo do hubble-ui), anexando ao Gateway via parentRefs
cross-namespace. Exit: `attachedRoutes: 1`, `curl --resolve` responde.

## 3.6 DNS split-horizon (PowerDNS auth + recursor)
LXC Debian 13 (`10.40.1.53`). Auth serve `the-lab.zone` em `127.0.0.1:5300`; Recursor 5.x (YAML)
na :53 forward pro auth + recursão raiz. Zona wildcard `*.lab.the-lab.zone → 10.40.7.10`. Exit:
os três `dig` respondem; apontar o cliente só pra `10.40.1.53`.

## 3.7 Flip para produção
Trocar a annotation do Gateway de `letsencrypt-staging` pra `letsencrypt-prod`, commitar. O
cert-manager reemite sozinho. **Exit da fase:** cadeado verde, sem port-forward.

---
tipo: runbook
componente: cilium-rede
tags: [mtu, vxlan, l2-announcement, gateway-api, crashloop, regex-interface]
fases: [3, 5]
relacionado: [runbooks/gateway-dns, runbooks/network-policies]
---

# Cilium: MTU do overlay, L2 announcement e Gateway API

Incidentes do plano de rede (Cilium) que não são de network policy — esses estão em
`runbooks/network-policies/`.

## MTU do overlay VXLAN: resposta grande black-holed cross-node

**Sintoma:** target DOWN com `context deadline exceeded (Client.Timeout exceeded while
awaiting headers)`, `never scraped`, 0 samples. De um pod, `curl` cross-node no `/health`
(payload 2 bytes) responde instantâneo, mas o `/metrics` conecta (`connect=0.001`) e morre
com `0 bytes received`. **"Pequeno passa, grande trava."**

**Causa:** Cilium em `Tunnel [vxlan]` não descontou os ~50 bytes de overhead do
encapsulamento. O auto-detect pegou MTU 1500 do `ens18` e repassou inteiro pro overlay —
`cilium_host`, `cilium_vxlan` e todos os `lxc*` em 1500. Pod emite frame de 1500 →
encapsulado vira ~1550 → estoura os 1500 do underlay (1GbE sem jumbo) → dropado. **Afeta
todo tráfego cross-node com payload grande, não só métricas.**

**Diagnóstico:**
- Endpoint pequeno vs grande, mesmo nó, direto no pod IP: `/health` passa, `/metrics` trava
  no `ttfb` (`curl -w 'connect=%{time_connect} ttfb=%{time_starttransfer}'`).
- Underlay nó-a-nó limpo em 1500 via netshoot `hostNetwork` no `kube-system`
  (`ping -M do -s 1472` passa = 1472+28=1500).
- `kubectl -n kube-system exec ds/cilium -- ip link show | grep -E 'lxc.*mtu'` → todos 1500
  = overhead não descontado.

**Fix:** `MTU: 1450` explícito (chave top-level) em `apps/core/cilium/values.yaml`. Após o
sync (`rollOutCiliumPods: true` rola o DaemonSet), **recriar os pods existentes** — o veth
só pega o MTU novo ao recriar:
```bash
kubectl -n observability rollout restart deploy/<consumidores-cross-node>
kubectl -n kube-system exec ds/cilium -- ip -d link show cilium_host | grep -oE 'mtu [0-9]+'  # 1450
```
**Lição:** Cilium VXLAN sobre underlay 1500 sem jumbo exige `MTU` explícito quando o
auto-detect não desconta overhead. Assinatura clássica: "pequeno passa, grande trava",
`awaiting headers` com TCP conectando. É cluster-wide — provavelmente explica timeouts
intermitentes não relacionados. Alternativa: jumbo end-to-end (exige NIC + switch coerentes).

## Cilium operator em CrashLoop após habilitar Gateway API

**Sintoma:** ao ligar `gatewayAPI.enabled: true`, o `cilium-operator` entra em
CrashLoopBackOff. Em cascata: agentes travam em `0/1` ("Still waiting for Cilium Operator to
register CRDs: ciliumenvoyconfigs"), taint `node.cilium.io/agent-not-ready` volta,
repo-server não agenda, ArgoCD paralisa.
**Causa:** operator com fatal `failed to setup field indexer "backendServiceTLSRouteIndex":
no matches for kind "TLSRoute" in version "gateway.networking.k8s.io/v1alpha2"`. O Cilium
1.19 indexa `TLSRoute` em `v1alpha2`, que **só existe no canal experimental** do Gateway
API. Os CRDs vendorizados eram do canal **standard** (TLSRoute só em `v1`).
**Diagnóstico:** `kubectl -n kube-system logs -l io.cilium/app=operator` mostra o fatal do
field indexer. Os agentes são vítimas (esperam os CRDs de Envoy que o operator morto deveria
registrar), não a causa.
**Fix:** vendorizar os CRDs do canal **experimental** (TLSRoute serve `v1alpha2`). Aplicar
direto (`kubectl apply --server-side`) já que o ArgoCD está paralisado; o operator recupera,
registra os CRDs de Envoy, agentes ficam Ready, taints caem, ArgoCD volta.
**Lição:** Cilium 1.19 Gateway API exige o canal `experimental`. (Detalhes da vendorização e
da VAP `safe-upgrades` em `runbooks/gateway-dns/`.)

## L2 announcement: regex de interface e lease

**Sintoma:** `db/show l2-announce` vazio, sem lease, `arping <VIP>` sem resposta.
**Causa (dupla):** (a) o lease é **por serviço anunciado** — sem um Service LB com IP, não
nasce lease; (b) a regex `^eth[0-9]+` não casa o device real `ens18` (o alias Talos `ethSel0`
na coluna ALIAS não é o que o Cilium casa — ele usa o nome primário do kernel).
**Fix:** regex `^ens[0-9]+$`; o lease aparece quando o Gateway (primeiro Service LB) recebe
IP. Validar com `arping` de um host na LAN e `ip neigh` (sai de `FAILED` para um MAC).
**Lição:** `db/show l2-announce` só popula no nó que segura o lease — `exec` no pod do
worker-holder, não num pod aleatório do `ds/cilium`. Nó heterogêneo (`enp7s0` no GPU) quebra
a seleção por nome — ver incidente do anunciante-fantasma em `runbooks/backup-dr/`.

## Lição transversal

Cilium tem três planos que falham diferente: overlay (MTU), L2/LB-IPAM (anúncio do VIP) e
Gateway API (operator/CRDs). Status verde do recurso não prova caminho de rede — a prova é
`arping`/`curl` no destino real, não o CR `Programmed=True`.

---
tipo: runbook
componente: talos
tags: [control-plane, etcd, bind-address, gpu, taint, nodelabels, metrics]
fases: [1, 5, 7, 9]
---

# Talos: control plane, etcd, taints de nó e métricas

Incidentes do plano do OS (Talos) — control plane não observável, etcd que não
hot-reload, e armadilhas de taint/label em nó já joinado.

## Control plane não expõe métricas (kube-controller-manager / kube-scheduler / etcd)

**Sintoma:** `ScrapePoolHasNoTargets` / targets DOWN em `kube-controller-manager`,
`kube-scheduler`, `kube-etcd` com "0 discovered targets" (ou `connection refused` nas
portas 10257/10259). Em paralelo, `TooManyScrapeErrors`/`TooManyLogs` do vmagent como
ruído downstream.

**Causa:** no Talos, por padrão CM e scheduler fazem bind das métricas em `127.0.0.1`
(service discovery não acha endpoint) e o etcd não expõe listener de métricas dedicado.
O control plane roda como static pod em host-network, sem Service/labels que deem match.

**Fix (machine config dos 3 CPs):**
```yaml
cluster:
  controllerManager: { extraArgs: { bind-address: 0.0.0.0 } }
  scheduler:         { extraArgs: { bind-address: 0.0.0.0 } }
  etcd:              { extraArgs: { listen-metrics-urls: http://0.0.0.0:2381 } }
```
Scrapes via **VMStaticScrape** (não Service+Endpoints — `Endpoints` está excluído no
`argocd-cm resource.exclusions`, então o ArgoCD não aplica Service/Endpoints manuais).
CM/scheduler em `https` + `insecureSkipVerify: true` (cert Talos vale só p/ localhost,
não p/ IP do nó); etcd em `http://0.0.0.0:2381` (sem auth/TLS). Desabilitar os scrapes
do chart (`kubeControllerManager/kubeScheduler/kubeEtcd: { enabled: false }`) pra não
brigar com os customizados.

**Lição:**
- Control plane no Talos não é observável out-of-the-box — expor métrica é decisão
  explícita de machine config, não de chart.
- **etcd NÃO é hot-reload.** Static pods (CM/scheduler) o Talos recria na hora ao mudar
  o config — por isso pegam `bind-address` sozinhos. O etcd é serviço gerenciado, só relê
  `extraArgs` num restart, e `talosctl service etcd restart` é **bloqueado por design**
  (guard anti-perda-de-quórum). Caminho: `talosctl reboot --mode=default`, **um CP por
  vez**, confirmando `etcd status` Healthy entre cada (quórum = 2 de 3).

## `machine.nodeTaints` é armadilha em nó já joinado (GPU)

**Sintoma:** aplicar taint via `machine.nodeTaints` falha em worker já no cluster; em
cascata, os `nodeLabels` somem.

**Causa:** o `NodeRestriction` admission bloqueia o kubelet alterando taints de nó já
joinado; e o bug talos#8193 derruba os `nodeLabels` junto.

**Fix:** `nodeLabels` ficam em `machine.nodeLabels`; o taint vai via
`machine.kubelet.extraConfig.registerWithTaints` (vale só no registro) + um
`kubectl taint` imperativo como bridge único. Rebuilds ficam cobertos pelo config.

**Lição:** taint de nó existente no Talos = imperativo; `registerWithTaints` só pra
novos registros. Nunca `machine.nodeTaints` em worker joinado.

## Lição transversal

No Talos, mudança de runtime do control plane (métricas, taint) é sempre via machine
config + (às vezes) ação imperativa pontual. Static pods recriam na hora; etcd e nó
joinado exigem reboot/imperativo. Diagnóstico sem SSH: `talosctl dashboard/dmesg/services/
logs/get`.

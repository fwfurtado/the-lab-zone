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

## etcd com leader changes recorrentes e health checks falhando

**Sintoma:** `etcd` nos 3 control planes (`cp-1`, `cp-2`, `cp-3`) alterna entre
`Health check failed: context deadline exceeded` e `Health check successful`; no
VictoriaMetrics, `etcd_server_leader_changes_seen_total` cresce continuamente e
`min_over_time(etcd_server_has_leader[5m])` cai para `0` em várias janelas. No log
do etcd aparecem `slow fdatasync`, `waiting for ReadIndex response took too long`,
`apply request took too long` e `etcdserver: leader changed`.

**Causa (mais provável):** latência **intermitente** no backend de storage que
suporta os discos dos control planes no Proxmox. A evidência principal foi:
- `histogram_quantile(0.99, ... etcd_disk_backend_commit_duration_seconds_bucket ...)`
  com picos recorrentes entre ~`1s` e `8s`;
- `histogram_quantile(0.99, ... etcd_network_peer_round_trip_time_seconds_bucket ...)`
  em dezenas de ms, ruim mas insuficiente para explicar commits em segundos;
- os 3 membros afetados ao mesmo tempo, todos no mesmo pool `local-nvme`.

**Diagnóstico:**
- Talos:
  - `talosctl service etcd` mostrou falhas recorrentes desde `2026-06-26`;
  - `talosctl etcd members/status` confirmou 3 membros, sem learners, líder variando,
    cluster saudável **no momento** da coleta e sem alarmes;
  - `talosctl dmesg` **não** mostrou `I/O error`, erro de XFS ou corrupção local.
- VictoriaMetrics:
  - `increase(etcd_server_leader_changes_seen_total[1h])` com bursts frequentes;
  - `max_over_time(etcd_server_proposals_pending[5m])` subindo nos mesmos períodos;
  - `rate(etcd_server_proposals_failed_total[5m])` com falhas distribuídas nos 3 nós;
  - `histogram_quantile(0.50, ... etcd_disk_backend_commit_duration_seconds_bucket ...)`
    baixo na maior parte do tempo, indicando problema de **pico**, não degradação constante.
- Proxmox:
  - VMs `100/101/102` (`talos-cp-1/2/3`) usam `virtio0` em `local-nvme` com
    `cache=none`, `aio=io_uring`, `iothread=1`;
  - `pvesm status` mostrou `local-nvme` com muita folga (`~2.11%` usado);
  - `iostat -xz 1 10`, `zpool iostat -v 1 10` e `pveperf` estavam saudáveis **na hora
    da coleta** (latência sub-ms, baixo `%util`, baixo `iowait`), reforçando a hipótese
    de latência intermitente que não estava ocorrendo naquele instante.

**Fix / mitigação:**
- operacional:
  - tratar como incidente de infraestrutura compartilhada, não como falha isolada do guest;
  - durante o incidente, coletar **no host Proxmox**: `iostat -xz 1`, `zpool iostat -v 1`,
    `zpool status -v local-nvme`, `zpool events -v`, `journalctl -k | grep -Ei 'nvme|zfs|timeout|reset|abort|I/O'`;
  - correlacionar com as queries do VictoriaMetrics no mesmo recorte.
- investigação:
  - verificar firmware/saúde dos NVMes (`smartctl -a /dev/nvme0n1`, `smartctl -a /dev/nvme1n1`);
  - verificar bursts de sync/write no pool `local-nvme` e contenda externa no host;
  - só manter rede como hipótese secundária se o RTT entre peers subir junto dos leader changes.

**Lição:**
- Em etcd, `leader_changes_seen_total` crescendo junto com `backend_commit_duration`
  em segundos pesa mais para **storage backend** do que para rede.
- Snapshot saudável do Proxmox **não inocenta** o storage: se o P99 histórico do etcd
  vai a segundos e o host está normal agora, o problema é intermitente.
- Quando os 3 control planes compartilham o mesmo pool, erro sistêmico do etcd tende a
  ser investigado primeiro no backend compartilhado, não dentro das VMs.

## Cascata no GitOps/data plane: `Unable to create Service resource`, scheduler flapping, webhook/operator caindo

**Sintoma:** durante a migracao dos stores para `openebs-hostpath-ssd`, o ArgoCD mostrou
apps `Degraded`/`Unknown` e o Gateway apareceu como degradado com `Unable to create Service resource`.
No mesmo periodo, pods do CNPG ficaram `Pending` sem evento, o `cnpg-operator` e o
`kube-scheduler` entraram em `CrashLoopBackOff`, e webhooks (`cnpg-webhook-service`,
Kyverno) alternaram entre `connection refused`, `no route to host`, `etcdserver: leader changed`
e `context deadline exceeded`.

**Causa:** a falha primaria continuou sendo a mesma classe do incidente acima: oscilacao do
control plane por perda de lease/latencia no apiserver-etcd. Os sintomas no plano de apps
foram secundarios:
- scheduler perde lease -> pod fica `Pending` sem `FailedScheduling`;
- operator perde lease -> webhook fica sem endpoint pronto;
- mutating/validating webhooks indisponiveis -> updates/creates falham no Argo;
- controllers de apps reportam degradacao que parece local, mas a raiz e o control plane.

**Diagnostico prático:**
- `kubectl -n kube-system get pod -l component=kube-scheduler -o wide`
- `kubectl -n kube-system logs kube-scheduler-<cp> --previous`
- `kubectl -n cnpg-system get deploy,pod,svc,endpoints`
- `kubectl -n cnpg-system logs deploy/cnpg-operator-cloudnative-pg --since=5m`
- `kubectl -n argocd get applications.argoproj.io`

Sinais fortes desta classe:
- `Leaderelection lost` em scheduler/operator;
- Service de webhook com apenas `notReadyAddresses`;
- pod `Pending` com PVC `Bound` e sem evento de scheduling;
- retries do Argo com erro de webhook, nao de spec invalida.

**Mitigacao usada no incidente real (2026-07-01):**
- tratar primeiro como incidente de control plane, nao como bug isolado do app;
- pausar autosync/self-heal dos apps mais sensiveis enquanto o webhook estava flapping;
- so usar patch/delete pontual em pods/jobs quando a raiz era conhecida e o runtime precisava
  destravar;
- retomar reconciliacao so depois de:
  - schedulers `1/1 Running`;
  - operator/webhook com endpoint pronto;
  - apps do Argo voltando para `Synced`/`Healthy`.

**Licao:** `Unable to create Service resource` no Argo, sozinho, e diagnostico fraco. Quando vier
junto de `leader changed`, `context deadline exceeded`, webhook `connection refused` e
operators/schedulers reiniciando, a raiz esta no control plane ate prova em contrario.

## Lição transversal

No Talos, mudança de runtime do control plane (métricas, taint) é sempre via machine
config + (às vezes) ação imperativa pontual. Static pods recriam na hora; etcd e nó
joinado exigem reboot/imperativo. Diagnóstico sem SSH: `talosctl dashboard/dmesg/services/
logs/get`.

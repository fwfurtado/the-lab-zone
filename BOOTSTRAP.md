# Bootstrap - The Lab Zone

Runbook de reconstrução total: do T630 vazio até o cluster operacional.

**Regra deste documento:** 
* Todo comando executado manualmente durante o bootstrap **DEVE** estar registrado aqui. Se não está aqui, não aconteceu.
* Este documento é testado contra o cluster lab — se um passo falhar lá, o documento está errado, não o executor.

---

## 0. Pré-requisitos (fora do T630)

Coisas que precisam existir **ANTES** de iniciar o bootstrap:
- [ ] **1Password** — vault `homelab`, accecível via CLI (`op`). Fonte da verdade de todas as credenciais.
- [ ] **Backblaze B2** — Conta ativa com os seguintes Buckets: 
  - `the-lab-zone-tf-state` — Bucket para armazenamento do estado do Terraform.
  - `the-lab-zone-backup` — Bucket de destino do Cloud Sync do TrueNAS.
- [ ] **GitHub** — Repositório `the-lab-zone`(este repo). Fonte da verdade do GitOps/IaC.
- [ ] **Workstation** com: `mise`, `op` e `git` instalados. Todas as demais ferramentas necessárias devem ser instaladas via `mise`.

```bash
git clone git@github.com:fwfurtado/the-lab-zone.git && cd the-lab-zone && mise install
```


### Itens esperados no vaul `homelab` (1Password)
| Item | Campos | Criado em |
|------|-------|-----------|
| `proxmox-terraform` | `api-token`, `admin console URL` |  Fase 1.1 |
| `Backblaze` | `Terraform Key/key-id`, `Terraform Key/application-key` |  Fase 1.2 |
| `sops-age` | `private-key` |  Fase 1.0 |


## 1. Fase 1 — Infraestrutura Base

### 1.0 Chave SOPS/Age (primeira execução apenas)
```bash
age-keygen 
# Publica -> .soap.yaml (commitada no repositório)
# Privada -> 1Password: item `sops-age`
# Para usar localmente:
mkdir -p ~/.config/sops/keys
op read op://homelab/sops-age/private-key -o ~/.config/sops/ages/keys.txt
```

### 1.1 Proxmox — token de API para o Terraform

Pré-condições: Proxmox VE instalado no T630. No shell do Proxmox (console):
```bash
pvemu user add terraform@pve
pvemu aclmod / -user terraform@pve -role Administrator
pvemu user token add terraform@pve provisioner --privsep=0
```

-> Salvar o token no 1Password: item `proxmox-terraform`.

### 1.2 Backblaze B2 — credenciais para o Terraform

No console do B2: criar application key restrita ao bucket `the-lab-zone-tf-state`.

-> Salvar as credenciais no 1Password: item `Backblaze`.

### 1.3 Image Talos (Image Factory)

Schematic com extensions: `siderolabs/qemu-guest-agent`.

- **Schematic ID:** `ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`
- **Versão:** `v1.13.4`
- Gerado em: [https://factory.talos.dev/](https://factory.talos.dev/)
- A ISO é baixada pelo próprio Terraform.

> Nota: o node GPU (3090) usará **OUTRO** schematic (extensions NVIDIA).
> Documentado na Fase 5.

### 1.4 Provisionar as VMs

Plano de rede (decisões registradas no [README](./README.md))

| Recurso | Valor |
|---------|-------|
| Subnet VMs | 10.10.30.0/24 |
| Pool LB (Cilium) | 10.10.50.0/24 |
| VMs | 3x CP (4c/8GB/60GB) + 2x workers (8c/32GB/100GB) |

```bash
just talos tf-init
just talos tf-plan
just talos tf-apply
```

### ✅ Critério de saída da etapa 1.4

As 5 VMs visíveis no Proxmox, bootadas na ISO, em **maintenance mode**
do Talos (dashboard no console da VM mostrando IP obtido via DHCP).
Sem SSH, sem login — comportamento esperado.

Anotar os IPs DHCP exibidos (necessários para o `apply-config` da
etapa 1.5):

| VM | IP DHCP (efemero) |
|----|---------|
| talos-cp-1 | Preencher manualmente após boot da VM |
| talos-cp-2 | Preencher manualmente após boot da VM |
| talos-cp-3 | Preencher manualmente após boot da VM |
| talos-worker-1 | Preencher manualmente após boot da VM |
| talos-worker-2 | Preencher manualmente após boot da VM |

### 1.5 Talos — talhelper genconfig + apply-config

Utilize o comando `just talos gen` para gerar o diretório de configuração do cluster e imprimir os commandos de `apply-config` individualmente.

```bash
just talos gen
```

O output esperado é o seguinte:
```bash
talosctl apply-config --talosconfig=./clusterconfig/talosconfig --nodes=10.40.6.11 --file=./clusterconfig/lab-zone-cp-1.yaml --insecure;
talosctl apply-config --talosconfig=./clusterconfig/talosconfig --nodes=10.40.6.12 --file=./clusterconfig/lab-zone-cp-2.yaml --insecure;
talosctl apply-config --talosconfig=./clusterconfig/talosconfig --nodes=10.40.6.13 --file=./clusterconfig/lab-zone-cp-3.yaml --insecure;
talosctl apply-config --talosconfig=./clusterconfig/talosconfig --nodes=10.40.6.21 --file=./clusterconfig/lab-zone-worker-1.yaml --insecure;
talosctl apply-config --talosconfig=./clusterconfig/talosconfig --nodes=10.40.6.22 --file=./clusterconfig/lab-zone-worker-2.yaml --insecure;
```

Substitua o `--nodes` para o IP que foi atribuido a VM via DHCP (vide tabela 1.4). 
Substitua o prefixo `./clusterconfig/` pelo caminho absoluto `infra/prod/talos/clusterconfig/` nos parâmetros `--file` e `--talosconfig`.
Execute os comandos com as devidas substituições e acompanhe no console do Proxmox o progresso.

### ✅ Critério de saída da etapa 1.5
Todos os nodes devem estar em estado `running` e o IP estático deve estar atribuído corretamente. 

| VM | IP ESTÁTICO |
|----|---------|
| talos-cp-1 | 10.40.6.11 |
| talos-cp-2 | 10.40.6.12 |
| talos-cp-3 | 10.40.6.13 |
| talos-worker-1 | 10.40.6.21 |
| talos-worker-2 | 10.40.6.22 |

### 1.6 Talos — Bootstrap do Etcd + kubeconfig

Utilize o comando `just talos bootstrap` para iniciar o bootstrap do Etcd.

```bash
just talos bootstrap
```

Regra mnemônica: kubectl fala com o VIP; talosctl fala com os nós.
O VIP depende do quorum do etcd — no desastre ele some junto; a API do Talos (porta 50000) nos IPs reais é o canal de socorro.

Para acompanhar o progresso, utilize o comando: 

```bash
just talos watch-health
```

Interpretação do output:

* As linhas de "erro" iniciais são um watch loop mostrando o etcd
  convergindo (Preparing → Running → healthy). Não são falhas.
* Deve terminar com OK em: etcd healthy, members consistent, apid,
  static pods e control plane components.
* SKIP em "nodes ready", "kube-proxy" e "coredns" é o resultado
  correto — são as consequências diretas do cni: none e do
  proxy.disabled: true. Se kube-proxy aparecer como check ativo, o
  patch não foi aplicado.

Após o bootstrap, é preciso gerar o kubeconfig para interagir com o cluster. 
```bash
just talos kubeconfig
```

O kubeconfig será salvo no diretório `~/.kube/config`.

Com o kubeconfig gerado, você pode interagir com o cluster utilizando `kubectl`.

```bash
kubectl get nodes -o wide
```

### ✅ Critério de saída da etapa 1.6

**5 nós listados, todos NotReady, INTERNAL-IP 10.40.6.x corretos.**
CoreDNS Pending em kube-system. O cluster está vivo (API em HA via VIP, etcd com quorum 3/3) e parado aguardando o CNI.
NotReady aqui é sucesso, não falha. Quem o resolve é a Fase 2.


Resultado registrado em 11/06/2026:
```
NAME       STATUS     ROLES           VERSION   INTERNAL-IP   OS-IMAGE          KERNEL
cp-1       NotReady   control-plane   v1.33.1   10.40.6.11    Talos (v1.13.4)   6.18.34-talos
cp-2       NotReady   control-plane   v1.33.1   10.40.6.12    Talos (v1.13.4)   6.18.34-talos
cp-3       NotReady   control-plane   v1.33.1   10.40.6.13    Talos (v1.13.4)   6.18.34-talos
worker-1   NotReady   <none>          v1.33.1   10.40.6.21    Talos (v1.13.4)   6.18.34-talos
worker-2   NotReady   <none>          v1.33.1   10.40.6.22    Talos (v1.13.4)   6.18.34-talos
```

---

## Apêndice A — Rollback da fase 1

`just talos tf-destroy` remove as 5 VMs e a ISO. Estado externo criado e que
pode permanecer: token do Proxmox, key do B2, bucket de tfstate, chave
age, talsecret.yaml no repo.

Para recriar o cluster do zero SEM trocar os certificados raiz:
manter o talsecret.yaml e repetir 1.4 → 1.6.
Para um cluster criptograficamente novo: apagar o talsecret.yaml e
repetir desde 1.5.


## Apêndice B — Comandos de diagnóstico (Talos sem SSH)
```bash
talosctl -n <IP> dashboard          # console do nó
talosctl -n <IP> dmesg              # kernel log
talosctl -n <IP> services           # estado dos serviços (etcd, kubelet...)
talosctl -n <IP> logs etcd          # log de um serviço
talosctl -n <IP> get members        # membros do cluster vistos pelo nó
```

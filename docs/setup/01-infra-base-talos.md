---
tipo: setup
fase: 1
titulo: Infraestrutura base — Talos no Proxmox
---

# Setup Fase 1 — Infraestrutura base

## 1.0 Chave SOPS/Age (primeira execução apenas)
```bash
age-keygen   # Publica → .sops.yaml (commitada); Privada → 1Password item `sops-age`
mkdir -p ~/.config/sops/age/
op read op://homelab/sops-age/private-key -o ~/.config/sops/age/keys.txt
```

## 1.1 Proxmox — token de API para o Terraform
No shell do Proxmox:
```bash
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve provisioner --privsep=0
```
→ Salvar no 1Password: item `Proxmox Terraform Token`.

## 1.2 Backblaze B2 — credenciais
No console do B2: application key restrita ao bucket `the-lab-zone-tf-state`. → Item
`Backblaze`.

## 1.3 Image Talos (Image Factory)
Schematic com extension `siderolabs/qemu-guest-agent`. Schematic ID
`ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`, versão `v1.13.4`. A ISO é
baixada pelo Terraform. (O nó GPU usa OUTRO schematic — extensions NVIDIA, Fase 7.)

## 1.4 Provisionar as VMs
Rede: subnet VMs `10.40.0.x`, pool LB (Cilium) `10.40.7.0/24`. VMs: 3x CP (4c/8GB/60GB) + 2x
workers (8c/32GB/100GB).
```bash
just talos tf-init && just talos tf-plan && just talos tf-apply
```
**Critério de saída:** 5 VMs no Proxmox, bootadas na ISO, em maintenance mode (dashboard com
IP via DHCP). Sem SSH, sem login — esperado. Anotar os IPs DHCP (necessários pro apply-config).

## 1.5 Talos — talhelper genconfig + apply-config
```bash
just talos gen   # imprime os comandos apply-config por nó
```
Substituir `--nodes` pelo IP DHCP de cada VM e o prefixo `./clusterconfig/` pelo caminho
absoluto. Executar e acompanhar no console do Proxmox.
**Critério de saída:** todos os nodes `running` com IP estático correto (cp-1/2/3 =
10.40.6.11/12/13; worker-1/2 = 10.40.6.21/22).

## 1.6 Talos — Bootstrap do Etcd + kubeconfig
```bash
just talos bootstrap
just talos watch-health
just talos kubeconfig   # salva em ~/.kube/config
kubectl get nodes -o wide
```
Mnemônico: kubectl fala com o VIP; talosctl fala com os nós. O VIP depende do quorum do etcd —
no desastre some junto; a API do Talos (50000) nos IPs reais é o canal de socorro. As linhas de
"erro" iniciais são o etcd convergindo (não falhas). SKIP em "nodes ready"/"kube-proxy"/
"coredns" é correto (consequência de `cni: none` + `proxy.disabled: true`).
**Critério de saída:** 5 nós listados, todos **NotReady** (sucesso — aguardando o CNI da Fase
2), INTERNAL-IP corretos, CoreDNS Pending.

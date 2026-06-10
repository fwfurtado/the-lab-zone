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
just talos init
just talos plan
just talos apply
```

### ✅ Critério de saída da etapa 1.4

As 5 VMs visíveis no Proxmox, bootadas na ISO, em **maintenance mode**
do Talos (dashboard no console da VM mostrando IP obtido via DHCP).
Sem SSH, sem login — comportamento esperado.

Anotar os IPs DHCP exibidos (necessários para o `apply-config` da
etapa 1.5):

| VM | IP DHCP (efemero) |
|----|---------|
| talos-cp-1 |  |
| talos-cp-2 |  |
| talos-cp-3 |  |
| talos-worker-1 |  |
| talos-worker-2 |  |

### 1.5 Talos — talhelper genconfig + bootstrap

_(pendente — próxima etapa)_

---

## Apêndice A — Rollback desta fase

`just talos destroy` remove as 5 VMs e a ISO. Nenhum estado externo ao
Terraform foi criado até aqui. O token do Proxmox e a key do B2 podem
permanecer.

---
tipo: setup
fase: 0
titulo: Pré-requisitos (fora do T630)
---

# Setup Fase 0 — Pré-requisitos

Coisas que precisam existir **ANTES** de iniciar o bootstrap:
- **1Password** — vault `homelab`, acessível via CLI (`op`). Fonte da verdade de todas as
  credenciais.
- **Backblaze B2** — conta ativa com os buckets: `the-lab-zone-tf-state` (estado do
  Terraform) e `the-lab-zone-backup` (destino do Cloud Sync do TrueNAS).
- **GitHub** — repositório `the-lab-zone` (fonte da verdade do GitOps/IaC).
- **Workstation** com `mise`, `op` e `git`. Demais ferramentas via `mise`.

```bash
git clone git@github.com:fwfurtado/the-lab-zone.git && cd the-lab-zone && mise install
```

## Itens esperados no vault `homelab` (1Password)
| Item | Campos | Criado em |
|------|-------|-----------|
| `Proxmox Terraform Token` | `api-token`, `admin console URL` | Fase 1.1 |
| `Backblaze` | `Terraform Key/key-id`, `Terraform Key/application-key` | Fase 1.2 |
| `sops-age` | `private-key` | Fase 1.0 |

> Regra do runbook de bootstrap: todo comando executado manualmente DEVE estar registrado.
> Se não está, não aconteceu. O documento é testado contra o cluster lab — se um passo falha
> lá, o documento está errado, não o executor.

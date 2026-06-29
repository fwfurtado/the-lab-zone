---
tipo: setup
fase: 2
titulo: GitOps core — Cilium, ArgoCD, 1Password Connect + ESO
relacionado: [decisions/0001-gitops-puro-argocd-app-of-apps, decisions/0003-divisao-vaults-1password]
---

# Setup Fase 2 — GitOps core

Objetivo: rede (Cilium), governo (ArgoCD) e secrets (1Password Connect + ESO). Ao final, nada
mais é instalado manualmente.

## 2.0 1Password Connect server (primeira execução apenas)
```bash
just bootstrap connect-server-create
```
Cria o server com grant SOMENTE ao vault `the-lab-zone`, salva credentials/token no vault
`homelab`, remove o arquivo local. **Executar UMA vez** (recriar invalida as credenciais).

## 2.1 Executar o bootstrap
```bash
just bootstrap run
```
Ordem: [1/4] Cilium (`helm template | kubectl apply --server-side --force-conflicts` + wait
nodes Ready) → [2/4] ArgoCD (mesmo padrão) → [3/4] secrets de bootstrap do Connect (os únicos
manuais) → [4/4] root app (ponto de não-retorno do GitOps).
- `helm template | kubectl apply` (não `helm install`): o ArgoCD não usa Helm releases; um
  release viraria estado órfão.
- `--server-side --force-conflicts` obrigatório (CRDs grandes estouram o client-side).

**Critério de saída:**
```bash
just bootstrap check-cilium    # cilium 1/1 nos 5 nós, coredns Running
just bootstrap check-argocd    # root e core: Synced / Healthy
kubectl get nodes              # 5x Ready
```
CoreDNS com IPs `10.245.x.x` confirma o pod CIDR novo. O app `core` sincroniza vazio (ainda sem
`app.yaml` em `apps/core/`) — esperado.

## 2.2 Commit 1 — Adoção do Cilium e ArgoCD pelo GitOps
Estrutura por componente (contrato `app.yaml`): `apps/core/cilium/` e `apps/core/argocd/`, cada
um com `app.yaml` (Application multi-source) + `values.yaml` (o MESMO do bootstrap). O
ApplicationSet descobre via `directory.recurse: true` + `include: '*/app.yaml'`.
**Momento de maior risco: é ADOÇÃO, não instalação.** O ArgoCD compara o que renderiza contra o
que o bootstrap aplicou.
**Critério de saída:** `cilium` e `argocd` Synced/Healthy sem OutOfSync com mudanças reais. Se
houver diff, investigar ANTES (`argocd app diff cilium`). Testar o loop: mudar algo trivial no
`cilium/values.yaml` → push → ArgoCD aplica → reverter.

## 2.3 Commit 2 — 1Password Connect + ESO
`apps/core/onepassword-connect/` (chart connect, ns external-secrets, wave 1) +
`apps/core/external-secrets/` (chart ESO + ClusterSecretStore no MESMO app, 3 sources).
Decisões: ClusterSecretStore (operador único, vault único); store no mesmo Application do
operator (wave por recurso garante operator healthy antes do store);
`SkipDryRunOnMissingResource=true` (tolera a corrida do DR); AppProject `core` whitelista
`sourceRepos`.
**Critério de saída:** `+onepassword-connect`, `+external-secrets` Synced/Healthy; connect (2/2)
e ESO Running; `clustersecretstore onepassword` READY=True.

## 2.4 Smoke test — cadeia de secrets ponta a ponta
Criar item `test-secret` no vault `the-lab-zone` (campo `password`), aplicar um ExternalSecret
descartável (ver BOOTSTRAP original), verificar e limpar:
```bash
kubectl -n default get secret smoke-test -o jsonpath='{.data.password}' | base64 -d
kubectl -n default delete externalsecret smoke-test
```
**Critério de saída da Fase 2:** o valor aparece no terminal — cadeia 1Password cloud → Connect
(réplica local) → ESO → Secret fechada. A partir daqui, todo componente novo entra só via commit.

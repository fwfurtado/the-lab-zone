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


### Itens esperados no vault `homelab` (1Password)
| Item | Campos | Criado em |
|------|-------|-----------|
| `Proxmox Terraform Token` | `api-token`, `admin console URL` |  Fase 1.1 |
| `Backblaze` | `Terraform Key/key-id`, `Terraform Key/application-key` |  Fase 1.2 |
| `sops-age` | `private-key` |  Fase 1.0 |


## 1. Fase 1 — Infraestrutura Base

### 1.0 Chave SOPS/Age (primeira execução apenas)
```bash
age-keygen 
# Publica -> .sops.yaml (commitada no repositório)
# Privada -> 1Password: item `sops-age`
# Para usar localmente:
mkdir -p ~/.config/sops/age/
op read op://homelab/sops-age/private-key -o ~/.config/sops/age/keys.txt
```

### 1.1 Proxmox — token de API para o Terraform

Pré-condições: Proxmox VE instalado no T630. No shell do Proxmox (console):
```bash
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve provisioner --privsep=0
```

-> Salvar o token no 1Password: item `Proxmox Terraform Token`.

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
| Subnet VMs | 10.40.0.x |
| Pool LB (Cilium) | 10.40.7.0/24 |
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

## 2. Fase 2 — GitOps Core

Objetivo: rede (Cilium), governo (ArgoCD) e secrets (1Password Connect + ESO).
Ao final desta fase, **nada mais é instalado manualmente** — todo componente
novo entra via commit.

### Princípios estabelecidos nesta fase

1. **O DR aplica o estado final, não reexecuta a história.** Toda config
   commitada deve ser auto-consistente sob convergência fora de ordem:
   componentes toleram dependências ainda-não-prontas (retry, degradar)
   em vez de falhar fatalmente.
2. **Admin local do ArgoCD permanece habilitado para sempre.** Quando o SSO
   (Authentik, fase futura) existir, ele é conveniência; o admin local é a
   porta de emergência do DR.
3. **Bootstrap e ArgoCD usam os mesmos insumos.** Mesmo chart, mesma versão,
   mesmo `values.yaml`, mesmo `releaseName`, mesmo server-side apply —
   é isso que garante adoção com diff zero.
4. **Contrato de descoberta:** todo arquivo `apps/<domínio>/<componente>/app.yaml`
   é um Application do ArgoCD; todo o resto (values, manifests) é material
   referenciado pelos Applications, invisível ao discovery.

### Divisão de vaults no 1Password (registro de decisão)

| Vault | Papel | Quem acessa |
|-------|-------|-------------|
| `homelab` | Secrets de bootstrap/humano (age, tokens TF, credenciais do Connect) | Operador via `op` CLI |
| `the-lab-zone` | Secrets consumidos pelo cluster em runtime | ESO, via Connect server |

O Connect server tem acesso **apenas** ao vault `the-lab-zone`. Um item no
vault errado é invisível para o ESO (vide Incidente 2.4).

### 2.0 Pré-requisito: 1Password Connect server (primeira execução apenas)

```bash
just bootstrap connect-server-create
```

O recipe executa:
1. `op connect server create the-lab-zone --vaults the-lab-zone` — cria o
   server com grant SOMENTE ao vault `the-lab-zone` e gera o
   `1password-credentials.json`
2. Salva o credentials como documento `1password-connect-credentials` no
   vault `homelab`
3. Cria o token (`op connect token create eso-token`) e salva no item
   `1password-connect` (campo `token`) no vault `homelab`
4. Remove o arquivo local

> ⚠️ **Executar UMA vez.** Recriar o server invalida as credenciais
> anteriores — se isso acontecer, reexecutar o passo [3/4] do bootstrap
> (idempotente) e dar restart no deploy do Connect.

Itens adicionados ao vault `homelab`:

| Item | Conteúdo | Criado em |
|------|----------|-----------|
| `1password-connect-credentials` | documento (1password-credentials.json) | Fase 2.0 |
| `1password-connect` | campo `token` | Fase 2.0 |

### 2.1 Executar o bootstrap

```bash
just bootstrap run
```

O recipe executa, em ordem:

| Passo | O quê | Como |
|-------|-------|------|
| [1/4] | Cilium | `helm template \| kubectl apply --server-side --force-conflicts` + wait nodes Ready |
| [2/4] | ArgoCD | mesmo padrão + wait deployments Available |
| [3/4] | Secrets de bootstrap | `op` → secrets `op-connect-credentials` e `op-connect-token` no ns `external-secrets` |
| [4/4] | Root app | `kubectl apply -f root.yaml` — ponto de não-retorno do GitOps |

Notas de design do script:

- **`helm template \| kubectl apply` em vez de `helm install`:** o ArgoCD não
  usa Helm releases (ele mesmo faz template+apply). Um release criado no
  bootstrap viraria estado órfão que ninguém gerencia.
- **`--server-side --force-conflicts` é obrigatório:** CRDs grandes
  (ArgoCD ApplicationSet, Cilium) estouram o limite de 256KB da annotation
  `last-applied-configuration` do client-side apply (vide Incidente 2.1).
  O server-side também é o que o ArgoCD usa (`ServerSideApply=true` nos
  Applications) — mesmo mecanismo nas duas eras do cluster.
- **O passo [3/4] injeta os ÚNICOS secrets manuais do sistema** — as
  credenciais do Connect, que não podem vir do ESO porque SÃO a porta do ESO.

### ✅ Critério de saída da etapa 2.1

```bash
just bootstrap check-cilium    # cilium 1/1 nos 5 nós, coredns Running
just bootstrap check-argocd    # root e core: Synced / Healthy
kubectl get nodes              # 5x Ready
```

- CoreDNS com IPs `10.245.x.x` confirma o pod CIDR novo em uso.
- O app `core` sincroniza **vazio** neste ponto (ainda não há `app.yaml`
  em `apps/core/`) — **esperado**.

Resultado registrado em 11/06/2026: 5 nós Ready; cilium + cilium-envoy +
operator(2) + hubble-relay + hubble-ui Running; `root` e `core`
Synced/Healthy na mesma revision.

### 2.2 Commit 1 — Adoção do Cilium e ArgoCD pelo GitOps

Estrutura por componente (contrato `app.yaml`):

```
apps/core/
├── cilium/
│   ├── app.yaml        # Application multi-source: chart helm.cilium.io + $values do Git
│   └── values.yaml     # MESMO arquivo usado pelo bootstrap
└── argocd/
    ├── app.yaml
    └── values.yaml
```

O ApplicationSet (`projects/appset.yaml`) descobre via
`directory.recurse: true` + `include: '*/app.yaml'`.

**Este é o momento de maior risco da fase: não é instalação, é ADOÇÃO.**
O ArgoCD compara o que renderiza contra o que o bootstrap aplicou.

### ✅ Critério de saída da etapa 2.2

`kubectl -n argocd get applications` → `cilium` e `argocd` **Synced/Healthy
sem passar por OutOfSync com mudanças reais**. Se houver diff na adoção,
investigar ANTES de deixar o sync rodar (`argocd app diff cilium` /
UI via `just bootstrap argocd-port-forward`): diff em DaemonSet/ConfigMap
do Cilium = values ou versão divergente do bootstrap.

Teste do loop completo: mudar algo trivial no `cilium/values.yaml` → push →
ArgoCD aplica → reverter.

### 2.3 Commit 2 — 1Password Connect + External Secrets Operator

Componentes adicionados (primeira instalação 100% GitOps — nenhum comando
além do push):

```
apps/core/
├── onepassword-connect/        # chart connect, ns external-secrets, wave 1
│   ├── app.yaml
│   └── values.yaml             # credentialsName/Key → secrets do bootstrap
└── external-secrets/           # chart ESO + ClusterSecretStore no MESMO app
    ├── app.yaml                # 3 sources: chart + ref values + path manifests/
    ├── values.yaml
    └── manifests/
        └── cluster-secret-store.yaml   # wave 1 (recurso), após operator healthy
```

Decisões registradas:

- **ClusterSecretStore (e não SecretStore):** operador único, vault único —
  store cluster-scoped com credencial centralizada. `spec.conditions` com
  namespaceSelector existe como restrição futura se necessário.
- **Store no mesmo Application do operator** (multi-source com 3 sources):
  coesão > granularidade num cluster solo. Wave por RECURSO no
  ClusterSecretStore garante operator healthy antes do store.
- **`SkipDryRunOnMissingResource=true`** no app: no DR, o dry-run do store
  acontece antes do CRD do ESO existir — a opção tolera a corrida.
- **AppProject `core` faz whitelist de `sourceRepos`** — todo chart novo
  exige adicionar o repo Helm à lista (vide Incidente 2.3).

### ✅ Critério de saída da etapa 2.3

```bash
kubectl -n argocd get applications              # +onepassword-connect, +external-secrets — Synced/Healthy
kubectl -n external-secrets get pods            # connect (2/2) e ESO Running
kubectl get clustersecretstore onepassword      # READY: True
```

### 2.4 Smoke test — a cadeia de secrets ponta a ponta

1. Criar item `test-secret` no vault **`the-lab-zone`** com campo `password`
2. Aplicar (descartável, sem commit):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: smoke-test
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: onepassword
    kind: ClusterSecretStore
  target:
    name: smoke-test
  data:
    - secretKey: password        # nome da chave no Secret do K8s (livre)
      remoteRef:
        key: test-secret         # TÍTULO do item no 1Password
        property: password       # nome do CAMPO no item
```

3. Verificar e limpar:

```bash
kubectl -n default get secret smoke-test -o jsonpath='{.data.password}' | base64 -d
kubectl -n default delete externalsecret smoke-test
```

### ✅ Critério de saída da Fase 2

O valor do campo aparece no terminal — cadeia
**1Password cloud → Connect (réplica local) → ESO → Secret** fechada.
A partir daqui, todo componente novo entra exclusivamente via commit.

---

## Incidentes da Fase 2 (registrados em 11/06/2026)

### Incidente 2.1 — CRD estoura o client-side apply

- **Sintoma:** `The CustomResourceDefinition "applicationsets.argoproj.io"
  is invalid: metadata.annotations: Too long: may not be more than 262144 bytes`
- **Causa:** `kubectl apply` client-side grava o manifest inteiro na
  annotation `last-applied-configuration` (limite 256KB); o schema do CRD
  sozinho estoura.
- **Fix:** `kubectl apply --server-side --force-conflicts` nos pipes do
  bootstrap. `--force-conflicts` necessário porque recursos já tinham sido
  criados via client-side na execução interrompida (transferência de
  field ownership).
- **Estado parcial é inofensivo:** o apply é incremental; re-executar o
  `run` completa o que falta (idempotente).

### Incidente 2.2 — `app.yaml` inválido falha SILENCIOSAMENTE

- **Sintoma:** o app `external-secrets` simplesmente não aparece na lista —
  nada vermelho, só uma ausência.
- **Causa:** arquivo `app.yaml` commitado sem `apiVersion`/`kind`/`metadata`
  (fragmento começando em `spec:`). O discovery o encontra, o parse falha,
  nenhum Application nasce.
- **Diagnóstico:** `kubectl -n argocd get app core -o jsonpath='{.status.conditions}'`
  (o app PAI acusa o erro de parse).
- **Lição:** após todo commit estrutural, conferir não só o que está verde,
  mas **o que era esperado e não apareceu** — e as conditions do app pai
  quando a resposta for estranha.

### Incidente 2.3 — Chart barrado pelo AppProject

- **Sintoma (prevenido, não ocorrido):** Application com erro
  "repository not permitted in project".
- **Causa:** o AppProject `core` faz whitelist de `sourceRepos`; chart de
  repo Helm não listado é rejeitado.
- **Procedimento:** todo componente novo de chart externo = adicionar o
  repo Helm ao `projects/<domínio>.yaml` ANTES do app.yaml.

### Incidente 2.4 — Réplica do 1Password Connect stale

- **Sintoma:** ExternalSecret em `SecretSyncedError` com
  `key not found in 1Password Vaults: test-secret in: map[the-lab-zone:1]`,
  mas `op read "op://the-lab-zone/test-secret/password"` funciona na CLI.
- **Armadilha do diagnóstico:** a CLI autentica como o OPERADOR (vê a
  cloud); o ESO pergunta ao CONNECT, que serve uma RÉPLICA local. A CLI
  funcionando não prova nada sobre a visão do Connect.
- **Diagnóstico definitivo:** perguntar diretamente ao Connect:

```bash
TOKEN=$(kubectl -n external-secrets get secret op-connect-token -o jsonpath='{.data.token}' | base64 -d)
# pod curl efêmero (ver recipe debug-pod) →
curl -s -H "Authorization: Bearer $TOKEN" http://onepassword-connect:8080/v1/vaults
# vault presente com "items": 0 + logs do connect-sync mostrando SÓ
# /health e /heartbeat (zero atividade de sync) = réplica congelada
```

- **Causa raiz:** o container `connect-sync` mantém sessão de longa duração
  com a cloud por onde chegam eventos; a sessão pode ESTAGNAR silenciosamente
  (health check mede "processo responde", não "dados frescos"). Vault/item
  recém-criados próximos à criação do server agravam.
- **Fix:**

```bash
kubectl -n external-secrets rollout restart deploy/onepassword-connect
kubectl -n default annotate externalsecret <nome> force-sync=$(date +%s)
```

- **Nota de segurança:** o output de pods de debug fica nos logs do
  container (incluindo o Bearer token). Para token de smoke-test, ok;
  rotacionar via `op connect token` se for o caso.

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

## Apêndice C — Comandos de diagnóstico (GitOps/secrets)

```bash
just bootstrap check-cilium                  # pods de rede
just bootstrap check-argocd                  # estado dos Applications
just bootstrap argocd-port-forward           # UI em localhost:8080
kubectl -n argocd get app <X> -o jsonpath='{.status.conditions}'   # erros de parse/sync
argocd app diff <X>                          # diff antes de adoção/sync
kubectl get clustersecretstore onepassword   # saúde do canal de secrets
kubectl -n external-secrets logs deploy/onepassword-connect -c connect-sync --tail=30
kubectl -n default describe externalsecret <X>   # events com o erro real
```

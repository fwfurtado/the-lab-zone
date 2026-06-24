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

# Fase 3 — Ingress TLS: cert-manager, Gateway API e DNS split-horizon

> Seção para append no `BOOTSTRAP.md`. Continua a numeração de incidentes das fases anteriores.

## Objetivo

Expor serviços do cluster em `https://<svc>.lab.the-lab.zone` com certificado válido e sem
port-forward. Três planos se encontram aqui:

- **Plano de tráfego (cluster):** Gateway API servido pelo Cilium, com um Gateway wildcard
  terminando TLS, IP fixo via LB-IPAM e anúncio na LAN via L2.
- **Plano de certificado:** cert-manager emitindo um wildcard `*.lab.the-lab.zone` via ACME
  DNS-01 no Cloudflare, consumido automaticamente pelo Gateway.
- **Plano de nome (DNS):** split-horizon — PowerDNS interno resolve `*.lab` para o IP do
  Gateway; o resto recursa normalmente.

**Critério de saída da fase:** `https://hubble.lab.the-lab.zone` abre no browser com cadeado
verde (cert de produção), sem port-forward, resolvendo pelo DNS interno.

---

## Decisões (Fase 3)

| Decisão | Escolha | Porquê |
|---|---|---|
| Canal dos CRDs do Gateway API | **experimental** (v1.5.1), vendorizado no repo | Cilium 1.19 indexa `TLSRoute` em `gateway.networking.k8s.io/v1alpha2`, que **só existe no canal experimental**. O `standard`, mesmo na v1.5.1, traz `TLSRoute` só em `v1`. Vendorizar evita tanto o timeout de clone do repo gigante quanto o erro de versão. |
| VAP `safe-upgrades` no Git | **Não vendorizar** | Ela bloqueia a transição standard→experimental e quebraria a reconciliação do ArgoCD a cada troca de canal. Com tudo em experimental, não há o que proteger. |
| Integração Gateway API no cert-manager | `config.enableGatewayAPI: true` | Desligada por padrão em todas as versões ≥1.15. Sem isso, a annotation no Gateway é ignorada e o secret TLS nunca é criado. |
| ClusterIssuers | **Dois** (`letsencrypt-staging` + `letsencrypt-prod`), account keys separadas | Flip declarativo via annotation (muda `issuerRef` → reemite sozinho, sem deletar secret), staging permanente para validar serviços futuros, e key por server (prática recomendada). |
| Desafio ACME | DNS-01 via Cloudflare, cert **wildcard** | Wildcard cobre todos os `*.lab` com um cert só; DNS-01 não exige expor HTTP-01 na borda. Token Cloudflare via ESO, no namespace `cert-manager` (cluster resource namespace). |
| Pin do IP do Gateway | `spec.infrastructure.annotations` (**não** `metadata.annotations`) | O Cilium só propaga annotations de `spec.infrastructure` para o Service derivado. Em `metadata` a annotation é ignorada e o LB-IPAM atribui o primeiro IP do pool. |
| Regex da L2AnnouncementPolicy | `^ens[0-9]+$` | O matcher casa o **nome real do kernel** (`ens18`), não o alias do Talos (`ethSel0`). O `^eth[0-9]+` dos blogs não casa nem o nome nem o alias. |
| Topologia do PowerDNS | **Recursor na frente do Authoritative** | Auth não recursa; apontar a LAN só pra ele quebraria a internet. Recursor na :53 (LAN), auth em `127.0.0.1:5300`, forward de `the-lab.zone` pro auth, recursão raiz pro resto. |
| Upstream da recursão | **Recursão raiz** (sem forwarder) | Mais privado (queries direto aos autoritativos) e sem dependência de terceiro. Trocável por forward pra 1.1.1.1/Quad9 com uma zona `.` + `recurse: true`. |
| Re-provisionamento do LXC DNS | `terraform_data` com `triggers_replace` por **hash do script** | `remote-exec` não re-roda em recurso já existente. Hashear o script faz o provisioner re-rodar contra o mesmo LXC quando a config muda, sem recriar o container. |

---

## Componentes e ordem de aplicação

```
apps/core/gateway-api-crds/   # CRDs experimental vendorizados (manifests/)
apps/core/cert-manager/       # chart + values (enableGatewayAPI) + issuers + token ESO
apps/core/gateway/            # Namespace + Gateway main (wildcard, pin IP, annotation issuer)
apps/core/hubble-route/       # HTTPRoute de smoke test (em kube-system)
infra/prod/dns/               # LXC PowerDNS (auth + recursor) via Terraform
```

Ordem importa: **CRDs do Gateway API antes do cert-manator bootar** (ele só checa o suporte no
startup), e **antes do Cilium operator** registrar o controller de Gateway.

---

## Passo a passo

### 3.1 — CRDs do Gateway API (canal experimental)

Vendorizar no `apps/core/gateway-api-crds/manifests/` os 9 CRDs do canal **experimental** da
v1.5.1 (`gatewayclasses`, `gateways`, `httproutes`, `grpcroutes`, `referencegrants`,
`tlsroutes`, `tcproutes`, `udproutes`, `backendtlspolicies`). **Não** copiar o
`kustomization.yaml`, a VAP `safe-upgrades`, nem os CRDs de mesh (`xmeshes`,
`xbackendtrafficpolicies`).

```bash
kubectl apply --server-side --force-conflicts -f apps/core/gateway-api-crds/manifests/
kubectl get crd tlsroutes.gateway.networking.k8s.io \
  -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{"\n"}{end}'
```

**Exit:** `tlsroutes` lista `v1alpha2 served=true`. GatewayClass `cilium` fica `Accepted=True`
e o `cilium-operator` sai do CrashLoop.

### 3.2 — cert-manager + issuers + token Cloudflare

No `values.yaml` do chart, habilitar a integração Gateway API:

```yaml
config:
  apiVersion: controller.config.cert-manager.io/v1alpha1
  kind: ControllerConfiguration
  enableGatewayAPI: true
```

App com `CreateNamespace=true` (o chart não cria o próprio namespace). ExternalSecret do token
Cloudflare (`Zone:DNS:Edit` + `Zone:Read`) materializando o secret `cloudflare-dns-token` **no
namespace `cert-manager`** (é o cluster resource namespace que o ClusterIssuer consulta). Dois
ClusterIssuers (staging + prod), cada um com seu `privateKeySecretRef`.

```bash
kubectl -n cert-manager rollout status deploy/cert-manager
kubectl -n cert-manager get secret cloudflare-dns-token
kubectl get clusterissuer        # ambos READY=True
```

**Exit:** cert-manager `Synced/Healthy`, os dois issuers `Ready` (o Ready só registra a conta
ACME; não depende do token ainda), e o secret do token presente em `cert-manager`.

### 3.3 — Gateway wildcard

Gateway `main` no namespace `gateway`, GatewayClass `cilium`, listener HTTPS wildcard,
`allowedRoutes.from: All`. **Pin do IP em `spec.infrastructure.annotations`** e annotation do
issuer (começar em **staging**) em `metadata.annotations`:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging   # cert-manager lê de metadata
spec:
  infrastructure:
    annotations:
      lbipam.cilium.io/ips: "10.40.7.10"                   # LB-IPAM lê de spec.infrastructure
  listeners:
    - name: https-wildcard
      hostname: "*.lab.the-lab.zone"
      port: 443
      protocol: HTTPS
      allowedRoutes: { namespaces: { from: All } }
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: wildcard-lab-tls    # criado AUTOMATICAMENTE pelo cert-manager
```

O cert-manager (gateway-shim) lê a annotation, cria um `Certificate` com
`secretName: wildcard-lab-tls`, emite via DNS-01, e o secret materializa.

```bash
kubectl -n gateway get certificate,certificaterequest,order,challenge
kubectl -n gateway get svc cilium-gateway-main -o wide   # EXTERNAL-IP = 10.40.7.10
kubectl -n gateway get gateway main -o wide              # PROGRAMMED=True
```

**Exit:** Service `cilium-gateway-main` com EXTERNAL-IP `10.40.7.10`, Gateway `Programmed=True`,
secret `wildcard-lab-tls` presente (cert de staging).

### 3.4 — L2 announcement do IP do Gateway

A `CiliumL2AnnouncementPolicy` precisa casar o device real (`ens18`) e o lease só nasce quando
há um Service LB com IP — o Gateway é esse Service.

```bash
kubectl get ciliuml2announcementpolicy -o yaml | grep -A2 interfaces   # ^ens[0-9]+$
kubectl -n kube-system get lease | grep cilium-l2announce               # holder = worker-N
# de um host na LAN:
arping -c3 10.40.7.10                                                    # responde
```

**Exit:** lease `cilium-l2announce-gateway-cilium-gateway-main` com holder, e o `10.40.7.10`
responde ARP na LAN.

### 3.5 — HTTPRoute do Hubble (smoke test)

HTTPRoute **no namespace `kube-system`** (mesmo do `hubble-ui`, evita ReferenceGrant),
anexando ao Gateway via `parentRefs` cross-namespace:

```yaml
spec:
  parentRefs:
    - name: main
      namespace: gateway
      sectionName: https-wildcard
  hostnames: ["hubble.lab.the-lab.zone"]
  rules:
    - matches: [{ path: { type: PathPrefix, value: / } }]
      backendRefs: [{ name: hubble-ui, port: 80 }]
```

```bash
kubectl -n gateway get gateway main -o wide            # attachedRoutes vira 1
kubectl -n kube-system describe httproute hubble-ui    # Accepted=True, ResolvedRefs=True
curl -k -I --resolve hubble.lab.the-lab.zone:443:10.40.7.10 https://hubble.lab.the-lab.zone/
```

**Exit:** `attachedRoutes: 1`, e o `curl --resolve` responde 200/redirect (cert de staging =
warning esperado).

### 3.6 — DNS split-horizon (PowerDNS auth + recursor)

LXC unprivileged Debian 13 (`10.40.1.53`). PowerDNS **Authoritative** serve `the-lab.zone`;
**Recursor** na frente resolve interno (forward pro auth) e externo (recursão raiz).

`/etc/powerdns/pdns.conf` (auth — old-style ainda suportado):

```ini
launch=gsqlite3
gsqlite3-database=/var/lib/powerdns/pdns.sqlite3
local-address=127.0.0.1:5300     # auth sai da :53; porta embutida no address (não local-port)
api=yes
api-key=<...>
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=10.40.0.0/21
```

`/etc/powerdns/recursor.yml` (Recursor 5.x exige **YAML**):

```yaml
incoming:
  listen:
    - 10.40.1.53
  allow_from:
    - 10.40.0.0/21
recursor:
  forward_zones:
    - zone: the-lab.zone
      forwarders:
        - 127.0.0.1:5300
```

Zona wildcard no PowerDNS: `*.lab.the-lab.zone → 10.40.7.10` (pin do Gateway).

```bash
dig the-lab.zone SOA @127.0.0.1 -p 5300        # auth direto
dig google.com @10.40.1.53                      # recursor recursa (flag 'ra')
dig hubble.lab.the-lab.zone @10.40.1.53          # forward → 10.40.7.10
```

**Exit:** os três `dig` respondem. Apontar a máquina cliente **só** para `10.40.1.53` (sem
secundário público) e abrir `https://hubble.lab.the-lab.zone`.

### 3.7 — Flip para produção

Validado o acesso com o cert de staging, trocar a annotation do Gateway de
`letsencrypt-staging` para `letsencrypt-prod`, commitar e sincronizar. O `issuerRef` do
Certificate muda → cert-manager **reemite sozinho** (sem deletar secret).

**Exit da Fase 3:** `https://hubble.lab.the-lab.zone` abre com cadeado verde, sem port-forward.

---

## Incidentes

### Incidente 3.1 — Cilium operator em CrashLoop após habilitar Gateway API

- **Sintoma:** ao ligar `gatewayAPI.enabled: true` no Cilium, o `cilium-operator` entra em
  CrashLoopBackOff. Em cascata: agentes dos workers travam em `0/1` ("Still waiting for Cilium
  Operator to register CRDs: ciliumenvoyconfigs / ciliumclusterwideenvoyconfigs"), taint
  `node.cilium.io/agent-not-ready` volta, repo-server não agenda, ArgoCD paralisa.
- **Causa:** operator com fatal `failed to setup field indexer "backendServiceTLSRouteIndex":
  no matches for kind "TLSRoute" in version "gateway.networking.k8s.io/v1alpha2"`. O Cilium 1.19
  indexa `TLSRoute` em `v1alpha2`, que **só existe no canal experimental** do Gateway API. Os
  CRDs vendorizados eram do canal **standard** (TLSRoute só em `v1`).
- **Diagnóstico:** `kubectl -n kube-system logs -l io.cilium/app=operator` mostra o fatal do
  field indexer. Os agentes só esperam os CRDs de Envoy que o operator (morto) deveria
  registrar — são vítimas, não a causa.
- **Fix:** vendorizar os CRDs do canal **experimental** (TLSRoute serve `v1alpha2`). Aplicar
  direto (`kubectl apply --server-side`) já que o ArgoCD estava paralisado; o operator recupera,
  registra os CRDs de Envoy, os agentes ficam Ready, os taints caem, o ArgoCD volta.
- **Lição:** Cilium 1.19 Gateway API exige o canal `experimental`. O `standard`, mesmo na
  versão mais nova, tem TLSRoute na versão errada para o field indexer.

### Incidente 3.2 — VAP `safe-upgrades` bloqueia CRDs experimental

- **Sintoma:** `kubectl apply` dos CRDs experimental falha em vários:
  `ValidatingAdmissionPolicy 'safe-upgrades' ... denied request: Installing experimental CRDs on
  top of standard channel CRDs is prohibited by default`. Além disso, erro
  `apiVersion not set, kind not set` no `kustomization.yaml`.
- **Causa:** o próprio Gateway API instala uma VAP que proíbe trocar CRDs standard→experimental
  in-place. E o `apply -f <dir>/` tentava aplicar o `kustomization.yaml` como manifesto.
- **Diagnóstico:** `tcproutes`/`udproutes` passaram (não têm contraparte standard); os que
  falharam (`gateways`, `httproutes`, `tlsroutes`...) são os que já existiam como standard.
- **Fix:** deletar a VAP e o binding
  (`kubectl delete validatingadmissionpolicy[binding] safe-upgrades.gateway.networking.k8s.io`),
  e vendorizar **só os 9 CRDs** num `manifests/` plano (sem `kustomization.yaml`, sem VAP, sem
  mesh). **Não** versionar a VAP — ela reintroduz o bloqueio na reconciliação do ArgoCD.

### Incidente 3.3 — cert-manager: namespace não encontrado

- **Sintoma:** app do cert-manager `Failed`: `namespaces "cert-manager" not found, error running
  rbacReconcile: ... error getting namespace cert-manager (retried 5 times)`.
- **Causa:** o chart do cert-manager **não cria o próprio namespace**; o `destination.namespace`
  só diz onde colocar os recursos. O `kubectl auth reconcile` dos RBACs falha sem o namespace.
- **Fix:** `CreateNamespace=true` no `syncPolicy.syncOptions` (ou um Namespace explícito com
  `sync-wave: "-1"`). Padronizar com os outros apps.

### Incidente 3.4 — Gateway degraded: `InvalidCertificateRef`

- **Sintoma:** Gateway `Degraded`, listener com
  `Invalid CertificateRef, Secret "wildcard-lab-tls" not found`.
- **Causa:** a integração Gateway API do cert-manager vem **desligada** por padrão (≥1.15). A
  annotation `cert-manager.io/cluster-issuer` no Gateway é ignorada, o Certificate não é criado,
  e o secret nunca aparece.
- **Diagnóstico:** `kubectl -n gateway get certificate` vazio = gateway-shim não está agindo.
- **Fix:** `config.enableGatewayAPI: true` no values. O cert-manager checa o suporte (e a
  presença dos CRDs Gateway API) **só no boot** — o sync do ArgoCD rola o Deployment e ele pega
  o flag. Garantir que os CRDs do Gateway API já existam quando ele reinicia.

### Incidente 3.5 — L2 announcement não funciona / regex e lease

- **Sintoma:** `db/show l2-announce` vazio, sem lease, `arping 10.40.7.10` sem resposta.
- **Causa (dupla):** (a) o lease é **por serviço anunciado** — sem um Service LB com IP, não
  nasce lease; (b) a regex `^eth[0-9]+` não casa o device real `ens18` (o alias Talos `ethSel0`
  na coluna ALIAS **não** é o que o Cilium casa — ele usa o nome primário do kernel).
- **Fix:** regex `^ens[0-9]+$`; e o lease aparece quando o Gateway (primeiro Service LB) recebe
  IP. Validar com `arping` de um host na LAN e `ip neigh` (sai de `FAILED` para um MAC).
- **Lição:** `db/show l2-announce` só popula no nó que segura o lease — `exec` no pod do
  worker-holder, não num pod aleatório do `ds/cilium`.

### Incidente 3.6 — Gateway recebe `10.40.7.0` em vez de `10.40.7.10`

- **Sintoma:** `cilium-gateway-main` com EXTERNAL-IP `10.40.7.0`; `arping`/`curl` no `.10`
  falham (nada anuncia o `.10`).
- **Causa:** o pin `lbipam.cilium.io/ips` estava em `metadata.annotations`, que o Cilium **não
  propaga** para o Service derivado. O LB-IPAM ignorou e atribuiu o primeiro IP do pool (`.0` —
  que ainda por cima é o endereço de rede, reservado).
- **Fix:** mover o pin para `spec.infrastructure.annotations`. O Service passa a receber o
  `10.40.7.10` e o L2 anuncia o IP correto.

### Incidente 3.7 — `curl` não resolve via Cloudflare (split-horizon)

- **Sintoma:** `curl https://hubble.lab.the-lab.zone` → "could not resolve host", mesmo com o
  `dig @10.40.1.53` funcionando.
- **Causa:** comportamento **esperado** do split-horizon. O `*.lab → 10.40.7.10` existe só no
  PowerDNS interno; o Cloudflare hospeda só a zona pública (para o DNS-01 do ACME) e não tem
  registro `lab.` (nem deveria — IP privado). A máquina ainda usava resolver público.
- **Fix (teste):** `curl --resolve hubble.lab.the-lab.zone:443:10.40.7.10 ...` bypassa o DNS.
  **Fix (definitivo):** apontar os clientes da LAN para o PowerDNS.

### Incidente 3.8 — PowerDNS auth-only não pode ser o resolver da LAN

- **Sintoma:** apontar a máquina para `10.40.1.53` quebraria a internet —
  `dig google.com @10.40.1.53` → `REFUSED`, "recursion requested but not available".
- **Causa:** rodando só o `pdns` (Authoritative), que não recursa. Lista de DNS no SO não faz
  failover num REFUSED (só num no-response), então não cai para um secundário.
- **Fix:** adicionar o `pdns-recursor` na frente (recursor na :53, auth em `127.0.0.1:5300`,
  forward de `the-lab.zone` pro auth, recursão raiz pro resto). Apontar a máquina **só** para o
  `10.40.1.53` (sem secundário público).

### Incidente 3.9 — `remote-exec` não re-roda; `local-port` e config do Recursor

Três tropeços encadeados ao adicionar o recursor pela Terraform:

- **(a) Provisioner não re-roda.** `remote-exec` só dispara na criação do recurso. O
  `terraform_data` tinha `triggers_replace = [var.pdns_api_key, var.dns_ip]`, que não muda
  quando o script é editado. **Fix:** extrair o `inline` para um `local` e usar
  `triggers_replace = [sha1(join("\n", local.pdns_script))]` — re-roda quando qualquer coisa no
  script muda, contra o mesmo LXC, sem recriar o container.
- **(b) `pdns` não sobe.** PowerDNS auth recente rejeita o `local-port` separado (falha hard em
  setting desconhecido). **Fix:** `local-address=127.0.0.1:5300` (porta embutida, sem
  `local-port`).
- **(c) `pdns-recursor` não sobe.** Recursor **5.x** não aceita mais o formato old-style
  `key=value` por padrão (`Old-style settings syntax not enabled by default anymore. Use YAML`).
  **Fix:** escrever `/etc/powerdns/recursor.yml` em YAML (`incoming.listen`,
  `incoming.allow_from`, `recursor.forward_zones`) e remover o `recursor.conf` antigo.
- **Lição:** o auth continua old-style; **só o Recursor** virou YAML. Para ver o fatal real do
  recursor (journal vazio por causa do `--disable-syslog`), rodar em foreground:
  `pdns_recursor --daemon=no --write-pid=no --config-dir=/etc/powerdns`.

# Fase 4 — Fundação de Storage (LocalPV Hostpath)

## Objetivo

Entregar o **tier quente RWO** do cluster: uma StorageClass `openebs-hostpath` cujos
PVs caem num **disco dedicado por worker** (`/dev/vdb` → `/var/mnt/pv-data`), separado
do disco de OS/efêmero pra isolamento de IO no NVMe. É a fundação que todo store
stateful da Fase 6 (Garage, CNPG, Valkey, ClickHouse, Qdrant, Memgraph) vai consumir.

A fase atravessa **dois planos** que não se misturam:

- **Plano do OS (Talos):** anexa o disco (Terraform) e o formata/monta (Talos user
  volume). Aplicado por `tf-apply` + `talosctl apply-config`, fora do Kubernetes.
- **Plano do cluster (ArgoCD):** sobe o provisioner OpenEBS e a StorageClass, que
  adotam o mount já existente como `BasePath`.

A ordem importa e não pode inverter: **disco → user volume → app de storage**.

## Decisões

| Decisão | Escolha | Porquê |
|---|---|---|
| Engine de storage | **LocalPV hostpath** | node-local, durabilidade no nível da app; sem replicação |
| Mayastor (replicated PV) | **descartado** | replicar entre worker-1/2 no mesmo NVMe físico do T630 único é fake-HA; não sobrevive à falha que importa (o host) |
| Disco de PV | **disco dedicado `virtio1` por worker**, no NVMe, separado do OS | isolamento de IO real pro tier quente (bancos com fsync pesado) |
| Onde mora o user volume | **plano do OS** (Talos `UserVolumeConfig`), via overlay `worker:` do talhelper | layout de disco é responsabilidade do OS, não do cluster; ArgoCD nunca encosta |
| Seleção do disco | `match: '!system_disk'` | blinda contra pegar o disco de boot; o único não-system é o de PV (200G) |
| StorageClass | **gerenciada por nós** (chart `hostpathClass` off), default, `WaitForFirstConsumer` | controle determinístico do `BasePath`; PV nasce no nó onde o pod agenda, pod fica pinado junto do dado |
| Engines desligados | lvm, zfs, rawfile, mayastor | só hostpath; evita Mayastor (etcd/hugepages) e CRDs inúteis |
| Logging do Mayastor (loki/alloy/minio) | **desligado** (chaves top-level) | observam um Mayastor que não existe — puro overhead |
| Backup do disco de PV | `backup = false` no vzdump | DR desse dado é app-level (pgBackRest, snapshot Qdrant → Garage → B2), não snapshot crash-consistent de banco vivo |
| Tier RWX | **adiado** (democratic-csi → NFS do TrueNAS) | nenhum workload RWX ainda; entra quando o primeiro surgir |

---

## 4.1 — Proxmox: disco de PV dedicado nos workers

Segundo disco (`virtio1` → `/dev/vdb`) emitido condicionalmente só pros nós que têm
`pv_disk_size` no `var.nodes` — ou seja, só os workers. Os CPs ficam com o boot apenas.

`infra/prod/talos/main.tf`:
```hcl
resource "proxmox_virtual_environment_vm" "talos" {
  for_each  = var.nodes
  # ... boot disk virtio0 (existente) ...

  dynamic "disk" {
    for_each = try(each.value.pv_disk_size, null) != null ? [1] : []
    content {
      datastore_id = "local-nvme"
      interface    = "virtio1"
      size         = each.value.pv_disk_size
      iothread     = true
      discard      = "on"
      backup       = false        # DR app-level, fora do vzdump
    }
  }
}
```

`infra/prod/talos/variables.tf` — `pv_disk_size = optional(number)` no tipo de
`var.nodes`; nos tfvars, `pv_disk_size = 200` só em worker-1 e worker-2.

**Exit:** `just talos tf-plan` mostra `0 to add, 2 to change, 0 to destroy` — disco
anexado in-place nos dois workers, CPs intocados (não aparecem no plano). Após o
apply, `talosctl -n 10.40.6.21 get disks` mostra `/dev/vdb` de 200G (cru) ao lado do
`/dev/vda` de boot.

---

## 4.2 — Talos: user volume (formata + monta)

`UserVolumeConfig` aplicado **só nos workers** via overlay `worker:` do talhelper. O
`talconfig.yaml` não usava `worker:`/`controlPlane:` antes (só `patches:` global + por
nó); o talhelper suporta esses overlays de role, e `worker.patches` mescla apenas nos
nós `controlPlane: false`.

`infra/prod/talos/talconfig.yaml` — nova chave de topo:
```yaml
worker:
  patches:
    - |-
      apiVersion: v1alpha1
      kind: UserVolumeConfig
      name: pv-data
      provisioning:
        diskSelector:
          match: '!system_disk'
        minSize: 100GiB
        grow: true
      filesystem:
        type: xfs
```

Aplicar:
```bash
talhelper genconfig
talosctl apply-config -n 10.40.6.21 -f clusterconfig/<cluster>-worker-1.yaml
talosctl apply-config -n 10.40.6.22 -f clusterconfig/<cluster>-worker-2.yaml
```

Monitorar (volume de runtime, sem reboot). O user volume vira o recurso com ID
`u-pv-data` (prefixo `u-`):
```bash
talosctl -n 10.40.6.21 get volumestatus --watch   # u-pv-data: waiting → provisioning → ready
talosctl -n 10.40.6.21 df | grep pv-data           # /var/mnt/pv-data ~200G
```

**Exit:** `u-pv-data` em `PHASE=ready` e `/var/mnt/pv-data` montado (~200G) nos dois
workers. O `installDiskSelector` dos workers (`>= 90GB`, acha o boot) e o `!system_disk`
(acha o disco de PV) não colidem. CPs não recebem o documento.

---

## 4.3 — ArgoCD: whitelist do repo OpenEBS

Sem o repo do chart no AppProject, o ArgoCD recusa a source ("repo not permitted").

`projects/core.yaml`:
```yaml
spec:
  sourceRepos:
    # ... existentes ...
    - https://openebs.github.io/openebs
```

**Exit:** AppProject `core` aceita a source do chart OpenEBS.

---

## 4.4 — OpenEBS LocalPV hostpath (ArgoCD)

App multi-source no padrão dos demais componentes de `apps/core/`. Chart umbrella
`openebs` **4.5.0**, com **só o engine hostpath** ligado e o stack de logging do
Mayastor desligado.

```
apps/core/storage/
├── app.yaml              # multi-source: chart + ref:values + manifests
├── values.yaml           # hostpath-only
└── manifests/
    ├── namespace.yaml    # openebs ns + PSA privileged (sync-wave -1)
    └── storageclass.yaml # openebs-hostpath, default, BasePath=/var/mnt/pv-data/openebs
```

`values.yaml` (estado final, já com as limpezas):
```yaml
# Só LocalPV hostpath. Desliga lvm/zfs/mayastor e o logging do Mayastor.
engines:
  local:
    lvm:
      enabled: false
    zfs:
      enabled: false
  replicated:
    mayastor:
      enabled: false

# loki/alloy/minio são chaves TOP-LEVEL (logging do Mayastor) e vêm enabled por
# default independente do engine — precisam ser desligados explicitamente.
loki:
  enabled: false
alloy:
  enabled: false

localpv-provisioner:
  hostpathClass:
    enabled: false        # SC gerenciada por nós em manifests/

# hostpath não usa VolumeSnapshot; evita disputa de ownership desses CRDs quando
# democratic-csi/Velero entrarem depois.
openebs-crds:
  csi:
    volumeSnapshots:
      enabled: false

# só serve pra upgrade v3→v4; em instalação nova é no-op.
preUpgradeHook:
  enabled: false
```

O `namespace.yaml` rotula o ns `openebs` com `pod-security.kubernetes.io/enforce:
privileged` (os helper pods do provisioner montam hostPath e rodam privilegiados) e
usa `sync-wave: "-1"` pra nascer antes do chart. A StorageClass aponta `BasePath` pro
mount do user volume:
```yaml
cas.openebs.io/config: |
  - name: StorageType
    value: "hostpath"
  - name: BasePath
    value: "/var/mnt/pv-data/openebs"
```

**Exit:**
```bash
kubectl -n openebs get pods         # só openebs-localpv-provisioner Running
kubectl get storageclass            # openebs-hostpath (default)
```
Sem pods de mayastor/lvm/zfs/loki/alloy/minio.

---

## 4.5 — Validação ponta a ponta

```bash
kubectl apply -f test/pv-smoke.yaml
kubectl get pvc -n default pv-smoke                       # Bound
kubectl get pv -o wide                                     # NODE onde caiu
talosctl -n <worker-do-pod> ls /var/mnt/pv-data/openebs    # diretório do PV criado
kubectl delete -f test/pv-smoke.yaml
```

**Exit:** PVC `Bound`, e o dado materializado em `/var/mnt/pv-data/openebs/<pvc>` no
worker — ou seja, no disco dedicado, não no `/var` de boot. Fase 4 fechada.

---

## Incidentes

### 1. Stack de logging do Mayastor (loki + alloy + minio) provisionada sem o engine

- **Sintoma:** após o sync, o namespace `openebs` ganhou pods/recursos de **MinIO,
  Alloy e Loki**, mesmo com o engine Mayastor desligado.
- **Causa:** esse trio é o stack de logging do subchart do Mayastor (Loki guarda,
  Alloy coleta, MinIO é o storage do Loki). No umbrella 4.5.0 os flags `loki:` e
  `alloy:` são **chaves top-level** com `enabled: true` próprio, **não atrelados** a
  `engines.replicated.mayastor.enabled`. Desligar o engine mata o data plane do
  Mayastor (io-engine, etcd), mas não cascateia pros subcharts de logging.
- **Diagnóstico:** ler os defaults do chart 4.5.0 confirmou que `loki`/`alloy` estão
  na coluna 0 (top-level), e que `mayastor.loki`/`mayastor.alloy` já vêm `false` (são
  os do subchart, diferentes dos top-level). O MinIO não é chave de topo — é storage
  interno do Loki, então cai junto ao desligar o Loki.
- **Correção:** `loki.enabled: false` + `alloy.enabled: false` no `values.yaml`. Com
  `prune: true` no app, o ArgoCD removeu os recursos sozinho.

### 2. Chaves vestigiais do localpv-provisioner

- **Sintoma:** `localpv-provisioner.openebsNDM.enabled` e `deviceClass.enabled` no
  values não surtiam efeito.
- **Causa:** o `localpv-provisioner` v4 **removeu o device mode e o NDM**; essas
  chaves não existem mais e o Helm simplesmente as ignora (no-op).
- **Correção:** removidas do values. Sobra só `hostpathClass.enabled: false`, que é a
  que importa (desliga a StorageClass default do chart, já que usamos a nossa).

### 3. (Verificação, não falha) Plano do Terraform podia recriar a VM

- **Sintoma potencial:** anexar disco poderia disparar `-/+ replace` e destruir o nó
  Talos.
- **Diagnóstico:** o `tf-plan` mostrou `0 to destroy` / `2 to change` (update
  in-place) — disco anexado a quente (virtio hot-plug), sem reboot dos workers.
- **Nota:** sempre conferir o plano antes do apply; nesse ponto da fase ainda não há
  dado no disco de PV, então mesmo um recreate de worker seria recuperável.

---

## Fora de escopo (de propósito)

O tier **RWX** (democratic-csi → NFS do TrueNAS) fica pra quando aparecer o primeiro
workload que precise dele. A Fase 4 entrega só o tier quente RWO. A próxima fase
(observabilidade) é o primeiro consumidor real: a VictoriaMetrics vai pedir
`openebs-hostpath` e validar o tier com um workload de verdade.

# Fase 5 — Observabilidade

**Objetivo:** métricas, logs e alertas. Primeiro consumidor real do tier
`openebs-hostpath` entregue na Fase 4. A partir desta fase, tudo que
nasce no cluster já nasce monitorado.

**Critério de saída:** `https://grafana.lab.the-lab.zone` abre com cadeado
verde mostrando métricas do cluster e logs dos pods. VMAlert avaliando
regras base do K8s com Alertmanager recebendo.

---

## Decisões de arquitetura

| Decisão | Escolha | Porquê |
|---|---|---|
| Métricas | VictoriaMetrics Single | Homelab single-node; HA seria fake-HA no mesmo disco. |
| Logs | VictoriaLogs | Sem dependência de object storage externo. Loki exige MinIO/Garage que só chega na Fase 6. |
| Coleta de logs de container | OTel Collector (preset `logsCollection`) | Fluent Bit foi removido como subchart do victoria-logs nas versões recentes do chart. OTel coleta via `filelog` receiver no DaemonSet. |
| Alertas | VMAlert + Alertmanager integrado ao `victoria-metrics` chart | O chart valida em `helm template` que VMAlert tem notifier — Alertmanager interno resolve isso sem configuração extra. |
| Traces | Descartados nesta fase | Só viram relevantes quando LiteLLM e Langfuse chegarem na Fase 7. OTel Collector aceita OTLP traces mas descarta via `debug` exporter. VictoriaTraces entra na Fase 7. |
| OTel Collector | DaemonSet + `otelcol-k8s` | Cada nó tem seu coletor local. `otelcol-k8s` é a distribuição slim recomendada para Kubernetes — não inclui `prometheusremotewrite`, usa `otlphttp` para tudo. |
| Protocolo de ingestão | OTLP over HTTP para VMSingle e VictoriaLogs | VMSingle expõe `/opentelemetry` nativamente. Consistente com ingestão de logs. Sem dependência de exporter extra. |
| Grafana | App separado (não embutido no vm-stack) | Controle independente de versão e config. |
| Secret Grafana | ESO → 1Password vault `the-lab-zone` item `grafana` | Mesma cadeia dos outros componentes. |
| StorageClass | `openebs-hostpath` para VMSingle, VictoriaLogs e Grafana | Primeiro workload stateful real no tier quente. |

---

## Service names reais (pós-deploy)

Descobertos via `kubectl get svc -n observability`. Usar estes nos exporters:

| Componente | Service | Porta |
|---|---|---|
| VMSingle | `vmsingle-victoria-metrics-vmks` | 8428 |
| VMAgent | `vmagent-victoria-metrics-vmks` | — |
| VMAlertmanager | `vmalertmanager-victoria-metrics-vmks` | 9093 |
| VictoriaLogs | `victoria-logs-vls-server` | 9428 |

---

## Estrutura de arquivos

```
projects/
└── observability.yaml

apps/observability/
├── victoria-metrics/
│   ├── app.yaml              # wave 1, chart victoria-metrics-k8s-stack 0.83.0
│   ├── values.yaml
│   └── manifests/
│       └── namespace.yaml    # wave -1, labels pod-security privileged
├── victoria-logs/
│   ├── app.yaml              # wave 1, chart victoria-logs-single 0.13.7
│   └── values.yaml
├── grafana/
│   ├── app.yaml              # wave 2, chart grafana 10.5.15
│   ├── values.yaml
│   └── manifests/
│       ├── grafana-secret.yaml   # ExternalSecret → 1Password
│       └── http-route.yaml       # HTTPRoute → grafana.lab.the-lab.zone
└── otel-collector/
    ├── app.yaml              # wave 2, chart opentelemetry-collector 0.158.1
    └── values.yaml
```

> **Nota:** `apps/observability/alertmanager/` não existe como app separado.
> O Alertmanager está integrado ao chart `victoria-metrics` via `alertmanager.enabled: true`.

---

## Pré-requisito: secret no 1Password

Antes de qualquer push, criar no vault **`the-lab-zone`**:

| Item | Campo | Valor |
|---|---|---|
| `grafana` | `username` | `admin` |
| `grafana` | `password` | senha forte aleatória |

---

## Ordem de aplicação

```bash
# 1. AppProject primeiro (sem ele os Apps são rejeitados)
kubectl apply -f projects/observability.yaml

# 2. Push dos apps — ArgoCD sincroniza em ordem de wave:
# wave -1: namespace.yaml (dentro do app victoria-metrics)
# wave  1: victoria-metrics, victoria-logs
# wave  2: grafana, otel-collector
git add apps/observability/ projects/observability.yaml
git commit -m "feat(observability): fase 5 — vm stack, vlogs, grafana, otel"
git push
```

---

## Validação por componente

### VMSingle — métricas

```bash
kubectl -n observability port-forward svc/vmsingle-victoria-metrics-vmks 8428:8428 &
curl -s 'http://localhost:8428/api/v1/query?query=up' | jq '.data.result | length'
# > 0
```

### VictoriaLogs — logs

```bash
kubectl -n observability port-forward svc/victoria-logs-vls-server 9428:9428 &
curl -s 'http://localhost:9428/select/logsql/query?query=*&limit=5'
# Linhas de log dos pods do cluster
```

### OTel Collector — DaemonSet

```bash
kubectl -n observability get pods -o wide | grep otel
# Um pod por nó, todos Running
```

### Grafana

```bash
kubectl -n observability describe httproute grafana | grep "Accepted"
# Accepted: True
```

Abrir `https://grafana.lab.the-lab.zone`:
- Datasource VictoriaMetrics → Test → OK
- Datasource VictoriaLogs → Test → OK
- Dashboard "Kubernetes Cluster" (gnetId 15661) com dados reais
- Dashboard "Node Exporter Full" (gnetId 1860) com dados reais

---

## Critério de saída da Fase 5 ✅

```bash
kubectl -n argocd get applications | grep -E "victoria-metrics|victoria-logs|grafana|otel-collector"
# Todos: Synced / Healthy

kubectl -n observability get pods
# Todos: Running

kubectl get pvc -n observability
# vmsingle-..., victoria-logs-vls-server-..., grafana-... → Bound
```

---

## Incidentes documentados

### 1. CRDs bloqueados pelo AppProject

- **Sintoma:** ArgoCD recusa sync dos charts com `resource ... is not permitted in project`.
- **Causa:** `clusterResourceWhitelist` no AppProject não incluía `apiextensions.k8s.io/CustomResourceDefinition` nem os CRDs do operator VictoriaMetrics (`operator.victoriametrics.com/*`).
- **Fix:** expandir `clusterResourceWhitelist` no `projects/observability.yaml`.

---

### 2. node-exporter FailedCreate por PodSecurity

- **Sintoma:** pods do node-exporter ficam em `Pending` / `FailedCreate` com erro de PodSecurity admission.
- **Causa:** o namespace `observability` com policy `baseline` bloqueia `hostNetwork`, `hostPID` e `hostPath` — que o node-exporter exige.
- **Fix:** labels no `namespace.yaml`:
  ```yaml
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
  ```

---

### 3. VMAlert falha no `helm template` sem notifier

- **Sintoma:** `helm template` falha com `Neither notifier, notifiers nor notifierConfigRef is set for vmalert`.
- **Causa:** o chart `victoria-metrics-k8s-stack 0.83.0` valida em template time que o VMAlert tem ao menos um notifier. Com `alertmanager.enabled: false` o deploy falha completamente.
- **Fix:** `alertmanager.enabled: true` no `values.yaml`. O Alertmanager interno passa a ser o notifier padrão automaticamente.

---

### 4. VictoriaLogs ficou Headless (sem ClusterIP)

- **Sintoma:** `kubectl get svc victoria-logs-vls-server` mostra `ClusterIP: None`. OTel Collector não consegue resolver o endpoint.
- **Causa:** o chart `victoria-logs-single` defaulta `clusterIP: None` (Headless StatefulSet). A key `service.clusterIP: ""` na **raiz** do values é ignorada — a key correta é `server.service.clusterIP`.
- **Fix:** no `values.yaml`:
  ```yaml
  server:
    service:
      clusterIP: ""   # string vazia → K8s atribui ClusterIP normal
  ```
- **Atenção:** mudar `clusterIP` em Service existente é operação imutável. Exige:
  ```bash
  kubectl delete svc victoria-logs-vls-server -n observability
  # ArgoCD recria automaticamente no próximo sync
  ```

---

### 5. Grafana Deployment OutOfSync após mudança de strategy

- **Sintoma:** ArgoCD em retry loop com `spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy type is 'Recreate'`.
- **Causa:** Kubernetes não aceita patch em `spec.strategy` quando o Deployment já existe com `type: RollingUpdate`. A mudança de tipo é imutável via patch.
- **Fix:**
  ```bash
  kubectl delete deployment grafana -n observability
  # No ArgoCD: Terminate o sync em andamento
  # Sync novamente com prune habilitado
  ```
- **Prevenção:** qualquer Deployment com PVC `ReadWriteOnce` deve ter `deploymentStrategy.type: Recreate` + `rollingUpdate: null` **desde o primeiro deploy**. Mudar depois sempre exige delete manual.

---

### 6. Grafana datasource com DNS errado

- **Sintoma:** datasources de VictoriaMetrics e VictoriaLogs falham em Test com "connection refused" ou "no such host".
- **Causa:** service names gerados pelo Helm com `nameOverride: vmks` são diferentes dos nomes sem override. Os names corretos só ficam conhecidos após o primeiro deploy.
- **Fix:** service names reais (ver tabela no início deste documento). Atualizar `values.yaml` do Grafana com os FQDNs corretos.

---

### 7. OTel Collector — `image.repository` obrigatório (chart ≥ 0.127.x)

- **Sintoma:** ArgoCD falha com `[ERROR] 'image.repository' must be set`.
- **Causa:** breaking change — o chart parou de ter default para `image.repository` por suportar múltiplas distribuições.
- **Fix:** declarar explicitamente no `values.yaml`:
  ```yaml
  image:
    repository: ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s
  command:
    name: otelcol-k8s
  ```

---

### 8. OTel Collector — `prometheusremotewrite` não disponível no `otelcol-k8s`

- **Sintoma:** pods em CrashLoopBackOff com `unknown type: "prometheusremotewrite"`.
- **Causa:** `otelcol-k8s` é uma distribuição slim que não inclui o exporter `prometheusremotewrite`. Os exporters disponíveis são: `otlp`, `otlphttp`, `debug`, `file`, `loadbalancing`, `otelarrow`.
- **Fix:** trocar para `otlphttp` apontando para o endpoint OTLP nativo do VMSingle:
  ```yaml
  exporters:
    otlphttp/metrics:
      endpoint: http://vmsingle-victoria-metrics-vmks.observability.svc.cluster.local:8428/opentelemetry
  ```
  O VMSingle aceita ingestão OTLP em `/opentelemetry` nativamente — sem necessidade de RemoteWrite.

---

## Decisões adiadas para fases futuras

| Item | Fase | Motivo |
|---|---|---|
| VictoriaTraces | 7 | Sem apps instrumentadas agora. Entra junto com LiteLLM/Langfuse. |
| Canal de alertas (Slack/PagerDuty) | 9 | Alertmanager configurado mas sem roteamento real. |
| `opentelemetry-ebpf` / `ebpf-instrumentation` | Opcional | eBPF para auto-instrumentação de apps — só vale quando houver serviços Go/Rust na Fase 7+. Cilium já expõe métricas nativas sem isso. |
---

## Incidentes pós-fase — targets DOWN no VMAgent
 
### kube-controller-manager e kube-scheduler não acessíveis
 
- **Sintoma:** targets DOWN com `connection refused` na porta 10257/10259.
- **Causa:** no Talos os componentes do control plane fazem bind apenas em `127.0.0.1` por padrão — não acessíveis externamente.
- **Fix:** adicionar no `talconfig.yaml` via `controlPlane.patches`:
```yaml
  controlPlane:
    patches:
      - |-
        cluster:
          controllerManager:
            extraArgs:
              bind-address: 0.0.0.0
          scheduler:
            extraArgs:
              bind-address: 0.0.0.0
```
  Regenerar configs com `talhelper genconfig` e aplicar nos nós control plane com `talosctl apply-config`. Não requer reboot.
 
### kube-controller-manager e kube-scheduler — TLS inválido após bind-address
 
- **Sintoma:** após configurar `bind-address: 0.0.0.0`, targets passam a `connection refused` para TLS error: `certificate is valid for localhost, not <NODE_IP>`.
- **Causa:** o certificado TLS desses componentes só tem `localhost` como SAN — não inclui o IP do nó. O VMServiceScrape gerado pelo chart usa `serverName: kubernetes` que também falha.
- **Fix:** desabilitar os VMServiceScrapes gerados pelo chart e criar VMServiceScrapes customizados com `insecureSkipVerify: true` em `manifests/vmservicescrapes-control-plane.yaml`:
```yaml
  # values.yaml
  kubeControllerManager:
    enabled: false
  kubeScheduler:
    enabled: false
```
```yaml
  # manifests/vmservicescrapes-control-plane.yaml
  apiVersion: operator.victoriametrics.com/v1beta1
  kind: VMServiceScrape
  metadata:
    name: kube-controller-manager
    namespace: observability
  spec:
    endpoints:
      - port: http-metrics
        scheme: https
        tlsConfig:
          insecureSkipVerify: true
```

### MTU do overlay Cilium: resposta grande de scrape sendo black-holed cross-node
 
- **Sintoma:** target `serviceScrape/observability/victoria-metrics-victoria-metrics-operator` DOWN com `cannot perform request ... context deadline exceeded (Client.Timeout exceeded while awaiting headers)`, `duration 10001ms`, `never scraped`, 0 samples. Selectors corretos e endpoint descoberto (o target aparece, só não coleta). De um pod no worker-1, `curl` cross-node no `/health` (porta 8081) respondia instantâneo, mas o `/metrics` (8080) conectava (`connect=0.001`) e morria com `0 bytes received`.
- **Causa:** Cilium em `Tunnel [vxlan]` não descontou os ~50 bytes de overhead do encapsulamento. O auto-detect pegou o MTU 1500 do `ens18` e repassou inteiro pro overlay — `cilium_host`, `cilium_vxlan` e **todos** os `lxc*` ficaram em 1500. Pod emite frame de 1500 → encapsulado vira ~1550 → estoura os 1500 do underlay (1GbE onboard, sem jumbo) → dropado. Pacote pequeno (`/health`, 2 bytes) passa; resposta grande (`/metrics`) morre. **Afeta todo tráfego cross-node com payload grande, não só o VM.**
- **Diagnóstico:**
  - Endpoint pequeno vs grande, do mesmo nó, direto no pod IP — o `/health` passa, o `/metrics` trava no `ttfb`:
```bash
    curl -sv --max-time 15 -o /dev/null -w 'connect=%{time_connect} ttfb=%{time_starttransfer}\n' \
      http://<pod-ip>:8080/metrics
```
  - Underlay nó-a-nó **está limpo** em 1500 (descarta rede física), via netshoot `hostNetwork` no `kube-system` (o `default` recusa `hostNetwork` por PodSecurity baseline):
```bash
    kubectl -n kube-system run dbg-host --rm -it --restart=Never \
      --overrides='{"spec":{"hostNetwork":true,"nodeName":"worker-1"}}' \
      --image=nicolaka/netshoot -- ping -M do -s 1472 10.40.6.22   # passa (1472+28=1500)
```
  - O agente do Cilium roda em `hostNetwork`, então `ip -d link` lá dentro mostra as interfaces do nó — `cilium_host`/`cilium_vxlan`/`lxc*` todos em `mtu 1500` = overhead não descontado:
```bash
    kubectl -n kube-system exec ds/cilium -- ip link show | grep -E 'lxc.*mtu'
```
- **Fix:** `MTU: 1450` explícito (chave top-level) em `apps/core/cilium/values.yaml`. Neste cluster o Cilium usa esse valor direto como MTU de pod (não subtrai outro overhead), então pods ficam em 1450, encapsulado bate 1500 e cabe. Após o sync (`rollOutCiliumPods: true` rola o DaemonSet sozinho), **recriar os pods existentes** — o veth só pega o MTU novo ao recriar:
```bash
  kubectl -n observability rollout restart deploy/victoria-metrics-victoria-metrics-operator
  kubectl -n observability rollout restart deploy/vmagent-victoria-metrics-vmks
  # confere: cilium_host deve cair pra 1450
  kubectl -n kube-system exec ds/cilium -- ip -d link show cilium_host | grep -oE 'mtu [0-9]+'
```
- **Lição:** Cilium VXLAN sobre underlay 1500 sem jumbo exige `MTU` explícito quando o auto-detect não desconta o overhead. Assinatura clássica: "pequeno passa, grande trava", `awaiting headers` com TCP conectando. É cluster-wide — provavelmente explica timeouts intermitentes não relacionados ao VM. Subir o MTU no underlay (jumbo end-to-end) seria a alternativa, mas exige NIC + switch coerentes.
---
 
### Webhook cert do VM Operator em churn sob ArgoCD (`bad certificate` + `FailedMount`)
 
- **Sintoma:** bursts intermitentes (~a cada sync) de `http: TLS handshake error from <IP>: remote error: tls: bad certificate` nos logs do operator, vindos de IPs nos CIDRs de pod dos três control-planes (`10.245.0.x`/`1.x`/`2.x`), cada burst seguido de `certwatcher Updated current TLS certificate`. Em paralelo, eventos `MountVolume.SetUp failed for volume "cert" : secret "victoria-metrics-victoria-metrics-operator-validation" not found` no pod do operator, com restarts.
- **Causa:** o cert do webhook era **Helm-generated**, que usa a função `lookup` do Helm pra reaproveitar o cert já existente no secret. O ArgoCD renderiza com `helm template` e **não respeita `lookup`** — a cada sync gera cert + caBundle novos. Com `prune: true`, o secret é recriado, abrindo uma janela em que ele não existe → `FailedMount` → restart do operator → reabre a janela de `bad certificate`. Loop auto-sustentado. Os `bad certificate` são os **três apiservers** (hostNetwork, mascarados pro IP de `cilium_host` do seu nó — daí aparecerem como IP de pod-CIDR) rejeitando o cert servido enquanto o `caBundle` no `ValidatingWebhookConfiguration` está dessincronizado.
- **Diagnóstico:**
  - bursts sempre seguidos de `Updated current TLS certificate` = cert em rotação contínua.
  - `argocd app get victoria-metrics` mostrando o `Secret ...-validation` com status `Pruned`.
  - `Serving metrics server bindAddress=:8080 secure=false` no log confirma que as métricas são HTTP puro — descarta confusão com o problema de MTU acima.
- **Fix:** migrar o cert pro cert-manager (já rodando no cluster). Em `apps/observability/victoria-metrics/values.yaml`, sob `victoria-metrics-operator`:
```yaml
  admissionWebhooks:
    enabled: true
    certManager:
      enabled: true   # cria Issuer (selfSigned) + Certificate; cainjector mantém o caBundle
```
  E em `apps/observability/victoria-metrics/app.yaml`, ignorar o `caBundle` que o cainjector injeta (senão o app fica piscando OutOfSync):
```yaml
  spec:
    ignoreDifferences:
      - group: admissionregistration.k8s.io
        kind: ValidatingWebhookConfiguration
        jqPathExpressions:
          - '.webhooks[]?.clientConfig.caBundle'
```
- **Validação:**
```bash
  kubectl -n observability get certificate            # validation + root-ca → READY True
  kubectl -n observability get secret victoria-metrics-victoria-metrics-operator-validation \
    -o jsonpath='{.metadata.labels}'                  # só controller.cert-manager.io/fao
  kubectl -n observability logs deploy/victoria-metrics-victoria-metrics-operator \
    --since=3m | grep -c 'bad certificate'            # 0
```
  O secret ficar **sem** o label `app.kubernetes.io/instance` é o que garante que o ArgoCD não o reivindica nem pruna — é o cert-manager o dono, fora do desired-state do app.
- **Lição:** documentado pela própria VictoriaMetrics — k8s-stack via ArgoCD **sem** cert-manager churna o cert do webhook porque o `lookup` do Helm não é respeitado. Com cert-manager no cluster, `certManager.enabled: true` é a escolha certa e elimina o loop. Isso dá o fix **permanente** pro restart-paliativo registrado no Incidente 10 da Fase 6.

---

# Fase 6 — Plataforma de Dados

**Objetivo:** provisionar todos os backends stateful vazios e validados antes de
qualquer app de negócio. Falha de store nunca se confunde com falha de app nas
fases seguintes.

**Critério de saída:** 6 stores rodando, PVCs bound, smoke tests de
escrita/leitura passando, backups configurados, métricas chegando no Grafana.

---

## Decisões de arquitetura

| Decisão | Escolha | Porquê |
|---|---|---|
| Object storage | Garage v2.3.0 | S3-compatible, Rust, single-node honesto, sem dependências externas |
| PostgreSQL | CNPG 1.29 + PG18 | Operator maduro, WAL→Garage via barman, PITR real |
| Cache/fila | Valkey 9.0.2 | Redis-compatible, licença limpa, `noeviction` para queue do Langfuse |
| Analytics/eventos | ClickHouse 24.3 via Altinity operator | Backend nativo do Langfuse, reutilizado na Fase 8 |
| Vector store | Qdrant 1.18 | LightRAG (Fase 7), pipeline RAG |
| Graph store | Memgraph 3.10 + Lab UI | LightRAG híbrido (grafo + vetor) |
| Backup ClickHouse | Sidecar `clickhouse-backup` + CronJob | API REST na porta 7171, upload assíncrono para Garage |
| Backup Qdrant | CronJob (curlimages + rclone) | Snapshot via API REST → upload via rclone |
| Métricas | VMPodScrape por app | Cada app dono do seu scrape, sem orchestrador extra |
| Dashboard Garage | ConfigMap com label `grafana_dashboard: "1"` | Auto-provisioning via sidecar Grafana |

---

## AppProject `data`

Arquivo: `projects/data.yaml`

Operators vão para o AppProject `core` (mesmo namespace que os demais operators):
- `cnpg-operator` → `apps/core/cnpg-operator/`
- `clickhouse-operator` → `apps/core/clickhouse-operator/`

Workloads de dados vão para o AppProject `data`, namespace `data`:
- Garage, CNPG cluster, Valkey, ClickHouse, Qdrant, Memgraph

O AppProject `data` tem `observability` como destination adicional para os
`VMPodScrape` de cada app.

---

## Estrutura de arquivos

```
projects/
└── data.yaml

infra/prod/garage/
├── main.tf          # buckets S3 via provider AWS com endpoint Garage
├── variables.tf
└── outputs.tf

apps/core/
├── cnpg-operator/app.yaml          # wave 5
└── clickhouse-operator/
    ├── app.yaml                    # wave 6
    └── values.yaml                 # WATCH_NAMESPACES=data

apps/data/
├── garage/
│   ├── app.yaml                    # wave 1
│   ├── values.yaml
│   └── manifests/
│       ├── namespace.yaml          # wave -1
│       ├── externalsecret.yaml     # rpcSecret + adminToken
│       ├── httproute.yaml          # s3.lab.the-lab.zone
│       ├── vmpodscrape.yaml        # porta admin (3903)
│       └── grafana-dashboard.yaml  # dashboard Garage S3
├── cnpg-cluster/
│   ├── app.yaml                    # wave 2
│   ├── values.yaml
│   └── manifests/
│       ├── externalsecret.yaml     # app user, superuser, garage-cnpg
│       └── vmpodscrape.yaml
├── valkey/
│   ├── app.yaml                    # wave 2
│   ├── values.yaml
│   └── manifests/
│       ├── externalsecret.yaml
│       ├── redis-exporter.yaml     # Deployment + Service redis_exporter
│       └── vmpodscrape.yaml        # scrape do redis_exporter
├── clickhouse/
│   ├── app.yaml                    # wave 2
│   └── manifests/
│       ├── chi.yaml                # ClickHouseInstallation
│       ├── externalsecret.yaml     # admin + langfuse passwords
│       ├── externalsecret-backup.yaml
│       ├── cronjob-backup.yaml     # 03:00 UTC via API sidecar
│       ├── vmpodscrape.yaml        # porta metrics (9363)
│       └── grafana-dashboard.yaml  # (futuro)
├── qdrant/
│   ├── app.yaml                    # wave 2
│   ├── values.yaml
│   └── manifests/
│       ├── externalsecret.yaml     # apiKey
│       ├── externalsecret-backup.yaml
│       ├── cronjob-backup.yaml     # 03:00 UTC via API + rclone
│       └── vmpodscrape.yaml
└── memgraph/
    ├── app.yaml                    # wave 2
    ├── values.yaml
    └── manifests/
        └── externalsecret.yaml     # username + password

apps/data/memgraph-lab/
├── app.yaml                        # wave 3
├── values.yaml
└── manifests/
    └── httproute.yaml              # memgraph.lab.the-lab.zone
```

---

## Pré-requisitos: 1Password

Criar no vault `the-lab-zone` antes de qualquer push:

| Item | Campos |
|---|---|
| `garage` | `rpcSecret` (64 chars hex: `openssl rand -hex 32`), `adminToken` |
| `cnpg` | `appUsername`, `appPassword`, `superuserUsername`, `superuserPassword` |
| `valkey` | `password` |
| `clickhouse` | `adminPassword` (plaintext), `langfusePassword` (plaintext) |
| `qdrant` | `apiKey` |
| `memgraph` | `username`, `password` |
| `garage-cnpg` | `accessKeyId`, `secretKey` (key com acesso ao bucket `cnpg-wal`) |
| `garage-clickhouse` | `accessKeyId`, `secretKey` (key com acesso ao bucket `clickhouse-backup`) |
| `garage-qdrant` | `accessKeyId`, `secretKey` (key com acesso ao bucket `qdrant-snapshots`) |

---

## Ordem de deploy

```bash
# 1. AppProject data
kubectl apply -f projects/data.yaml

# 2. Operators no core (se ainda não deployados)
# ArgoCD synca cnpg-operator (wave 5) e clickhouse-operator (wave 6)

# 3. Terraform: buckets no Garage
just garage init-layout --id=<NODE_ID>   # aplicar layout antes dos buckets
just buckets tf-init
just buckets tf-plan
just buckets tf-apply

# 4. Aliases globais dos buckets (Terraform cria com alias local apenas)
just garage alias-buckets

# 5. Keys por serviço e permissões nos buckets
just garage generate-key --keyname=cnpg
just garage make-owner-of-bucket --keyid=<ID> --bucket=cnpg-wal

just garage generate-key --keyname=clickhouse
just garage make-owner-of-bucket --keyid=<ID> --bucket=clickhouse-backup

just garage generate-key --keyname=qdrant
just garage make-owner-of-bucket --keyid=<ID> --bucket=qdrant-snapshots

# 6. Push dos apps — ArgoCD synca em ordem de wave
git add apps/ projects/
git commit -m "feat(data): fase 6 — garage, cnpg, valkey, clickhouse, qdrant, memgraph"
git push
```

---

## Validações por componente

### Garage

```bash
just garage status
# Deve mostrar nó com role dc1, capacity 100G

# Smoke test S3
kubectl exec -n data garage-0 -- /garage bucket list
# Deve listar: cnpg-wal, clickhouse-backup, qdrant-snapshots, velero, langfuse
```

### CNPG

```bash
kubectl get cluster -n data
# STATUS: Cluster in healthy state

kubectl exec -n data \
  $(kubectl get pod -n data -l cnpg.io/cluster=cnpg-cluster -o name | head -1) \
  -- psql -U postgres -c "SELECT version();"
```

### Valkey

```bash
kubectl exec -n data \
  $(kubectl get pod -n data -l app.kubernetes.io/name=valkey -o name) \
  -- valkey-cli -a <password> ping
# PONG
```

### ClickHouse

```bash
kubectl exec -n data chi-clickhouse-default-0-0-0 -c clickhouse -- \
  clickhouse-client --user admin \
  --password "$(kubectl get secret clickhouse-credentials -n data \
    -o jsonpath='{.data.adminPassword}' | base64 -d)" \
  --query "SELECT 1"
# 1

# Teste backup manual
kubectl create job -n data clickhouse-backup-test \
  --from=cronjob/clickhouse-backup
kubectl logs -n data -l job-name=clickhouse-backup-test -f
```

### Qdrant

```bash
kubectl port-forward -n data svc/qdrant 6333:6333 &
curl -s -H "api-key: <apiKey>" http://localhost:6333/collections
# {"result":{"collections":[]},"status":"ok"}
```

### Memgraph

Acessa `https://memgraph.lab.the-lab.zone`:
- Host: `memgraph`, Port: `7687`
- Usuário e senha do 1Password item `memgraph`
- Query: `RETURN 1;`

---

## Observabilidade

### VMPodScrapes ativos

Cada app tem seu `VMPodScrape` em `manifests/vmpodscrape.yaml` no namespace
`observability`. Após deploy, verificar em `http://vmagent:8429/targets`:

| Job | Estado esperado |
|---|---|
| `podScrape/observability/cnpg-cluster` | UP |
| `podScrape/observability/clickhouse` | UP (porta `metrics` 9363) |
| `podScrape/observability/qdrant` | UP |
| `podScrape/observability/valkey-exporter` | UP |
| `podScrape/observability/garage` | UP (porta `admin` 3903) |

### Grafana dashboards

| Dashboard | Origem | gnetId/ConfigMap |
|---|---|---|
| CloudNativePG | Grafana.com | `20417` |
| ClickHouse | Grafana.com | `14192` |
| Qdrant | Grafana.com | `24603` |
| Valkey/Redis | Grafana.com | `763` |
| Garage S3 | ConfigMap custom | `grafana-dashboard-garage` no namespace `data` |

O sidecar `grafana-sc-dashboard` (habilitado no values do Grafana via
`sidecar.dashboards.enabled: true`) importa automaticamente qualquer ConfigMap
com label `grafana_dashboard: "1"` em qualquer namespace.

---

## Incidentes documentados

### 1. Garage — campo `environment` do chart não aceita objetos

- **Sintoma:** `ComparisonError: .spec.template.spec.containers[name="garage"].env: expected list, got &{map[...]}`
- **Causa:** o campo `environment` do chart Garage v2 só aceita dict de strings literais. Tentar passar `secretKeyRef` como valor quebra o template.
- **Fix:** usar `GARAGE_ALLOW_WORLD_READABLE_SECRETS: "true"` como string literal. Secrets montados via `extraVolumes` projected com `defaultMode: 0600` e `subPath`.

### 2. Garage — fsGroup do Kubernetes impede permissão 0600

- **Sintoma:** `File /etc/garage-secrets/rpcSecret is world-readable! (mode: 0100640, expected 0600)`
- **Causa:** o chart do Garage tem `fsGroup: 1000` hardcodado no podSecurityContext. O Kubernetes aplica o fsGroup nos volumes montados, adicionando bit de leitura de grupo mesmo com `defaultMode: 0600`.
- **Fix:** `GARAGE_ALLOW_WORLD_READABLE_SECRETS: "true"` no campo `environment` do chart. O Garage documenta essa env var para ambientes container onde o fsGroup é inevitável.

### 3. Garage — buckets criados com alias local apenas

- **Sintoma:** `GetBucketInfo returned NoSuchBucket` ao tentar dar permissão via nome do bucket.
- **Causa:** o provider AWS cria buckets no Garage com alias local (vinculado à key de criação). O comando `garage bucket allow <nome>` requer alias global.
- **Fix:** após `just buckets tf-apply`, rodar `just garage alias-buckets` que adiciona alias global para cada bucket via `garage bucket alias --global <ID> <nome>`.

### 4. Garage — region na assinatura AWS4

- **Sintoma:** `authorization header malformed, unexpected scope: '20260615/us-east-1/s3/aws4_request', expected: '20260615/garage/s3/aws4_request'`
- **Causa:** o provider AWS valida a region como string AWS válida mas o Garage exige `garage` no scope da assinatura.
- **Fix:** `skip_region_validation = true` + `region = "garage"` no provider. Para rclone: `region = garage` no config.

### 5. ClickHouse operator — `watchNamespaces` via env var

- **Sintoma:** CHI criado no namespace `data` não é processado pelo operator. Logs param em "workers started" sem processar eventos.
- **Causa:** o Altinity operator por default só monitora o namespace onde está instalado. `watch.namespaces.include: []` no ConfigMap significa "nenhum namespace adicional", não "todos".
- **Fix:** `WATCH_NAMESPACES=data` via env var no values do operator:
  ```yaml
  operator:
    env:
      - name: WATCH_NAMESPACES
        value: "data"
  ```

### 6. ClickHouse — `passwordSecretRef` não relê Secret após criação

- **Sintoma:** após atualizar senha no 1Password e forçar reconcile, o hash no `chop-generated-users.xml` permanece o antigo.
- **Causa:** o Altinity operator cacheia o valor do Secret no momento da criação do CHI e não observa mudanças posteriores no Secret referenciado.
- **Fix:** usar `from_env` no XML de usuários via `configuration.files` no CHI spec. As env vars são injetadas via `valueFrom.secretKeyRef` no container do ClickHouse e o Garage expande `<password_sha256_hex from_env="VAR"/>` em runtime. O ExternalSecret gera os hashes SHA256 via template ESO.

### 7. ClickHouse — senha default ao invés da configurada

- **Sintoma:** autenticação falha com a senha do 1Password mas funciona com `default`.
- **Causa:** o `passwordSecretRef` estava usando o hash SHA256 como valor, não a senha plaintext. O ClickHouse faz SHA256 do valor recebido — SHA256(SHA256) resulta em hash diferente.
- **Fix:** garantir que o 1Password armazena a senha em **plaintext**. O ExternalSecret usa template ESO para calcular `sha256sum` do valor e gerar `adminPasswordSha256` e `langfusePasswordSha256` como campos separados.

### 8. ClickHouse — porta 9363 não exposta por padrão

- **Sintoma:** VMPodScrape com `port: "9363"` resulta em `connection refused`.
- **Causa:** o ClickHouse tem suporte nativo a Prometheus mas o endpoint não está habilitado por padrão. Precisa do bloco `<prometheus>` no config XML.
- **Fix:** adicionar via `configuration.files` no CHI:
  ```xml
  <clickhouse>
    <prometheus>
      <endpoint>/metrics</endpoint>
      <port>9363</port>
      <metrics>true</metrics>
      <events>true</events>
      <asynchronous_metrics>true</asynchronous_metrics>
    </prometheus>
  </clickhouse>
  ```

### 9. Memgraph — métricas requerem Enterprise License

- **Sintoma:** VMPodScrape retorna 400 com `Memgraph must have an Enterprise License for providing metrics!`
- **Causa:** a endpoint `/metrics` do Memgraph só está disponível na versão Enterprise.
- **Fix:** remover o VMPodScrape do Memgraph. Sem dashboard de métricas para o Memgraph na versão community.

### 10. VMPodScrape — VM Operator não processa após TLS mismatch

- **Sintoma:** VMPodScrapes criados ficam sem STATUS após restart do operator.
- **Causa:** o VM Operator estava com `tls: private key does not match public key` — cert-manager rotacionou o certificado do webhook mas o operator não recarregou corretamente.
- **Fix:** `kubectl rollout restart deployment -l app.kubernetes.io/name=victoria-metrics-operator -n observability`. Após reiniciar, os VMPodScrapes foram processados e ficaram `operational`.

### 11. VMPodScrape — selectors incorretos

- **Sintoma:** `podScrape/observability/clickhouse 0/0 up` — sem endpoints descobertos.
- **Causa:** labels usados nos selectors não batiam com os labels reais dos pods. O ClickHouse operator gera pods com labels próprios (`clickhouse.altinity.com/*`).
- **Fix:** verificar labels reais com `kubectl get pods -n data --show-labels` e ajustar os `matchLabels` nos VMPodScrapes. Garage usa `port: admin`, Memgraph usa `port: http`.

### 12. Grafana dashboard — datasource variável não resolvida via ConfigMap

- **Sintoma:** dashboard importado via ConfigMap mostra dropdown "Datasource" vazio.
- **Causa:** o mecanismo `__inputs` é para import manual. Ao provisionar via ConfigMap, a variável `${DS_VICTORIAMETRICS}` não é resolvida automaticamente.
- **Fix:** substituir `${DS_VICTORIAMETRICS}` pelo UID real do datasource (`P4169E866C3094E38`) diretamente no JSON do dashboard.

---

## Decisões adiadas

| Item | Fase | Motivo |
|---|---|---|
| VictoriaTraces | 7 | Sem apps instrumentadas. Entra com LiteLLM/Langfuse. |
| Valkey metrics (redis_exporter) | ✅ Feito | Deployment separado com `oliver006/redis_exporter` |
| Memgraph metrics | — | Requer Enterprise License |
| Redpanda/Debezium | 8 | CDC só se virar necessidade real |
| ClickHouse Fase 8 | 8 | Mesma instância reutilizada para analytics |
| kube-controller-manager/scheduler metrics | Infra | Requer mudança no Talos machine config (`bind-address: 0.0.0.0`) |

---

## Justfiles criados nesta fase

```
just garage status
just garage init-layout --id=<NODE_ID>
just garage generate-key --keyname=<name>
just garage make-owner-of-bucket --keyid=<id> --bucket=<name>
just garage set-global-alias

just buckets tf-init
just buckets tf-plan
just buckets tf-apply
just buckets tf-destroy
```

# Fase 7 — Stack de IA: MCP, GPU e Inferência Local

## Objetivo

Subir a camada de IA sobre o cluster já observável (Fase 5) e com data platform (Fase 6):
- **MCP servers** (via ToolHive operator) expondo ferramentas pro ecossistema agentic: `github`, `grafana`, `kubernetes`, `fastcrw`, `searxng`.
- **Kyverno** como policy engine (primeiro uso: contornar a incompatibilidade `sessionAffinity` do ToolHive com o Cilium).
- **GPU** no `worker-3-gpu` (RTX 3090): device plugin + RuntimeClass, inferência local com **Ollama** (`qwen3-coder:30b-a3b-q4_K_M`) e proxy **LiteLLM**.
- **Observabilidade da GPU**: DCGM exporter → VictoriaMetrics.

## Decisões (Fase 7)

- **ToolHive operator** (não MCP servers soltos): CRD `MCPServer` padroniza secret/RBAC/proxy. Namespace mode `allowedNamespaces: [ai, toolhive-system]`. Projeto `core` (instala cluster-scoped).
- **stdio + proxyMode streamable-http** para `github` e `fastcrw`: o modo http nativo desses servers exige OAuth de cliente que o proxy do ToolHive não fornece. stdio também é imune ao MTU/drop do Cilium.
- **Kyverno** em vez de patch manual recorrente para o `sessionAffinity`. Mutate idempotente com guards anti-loop.
- **GPU via device plugin standalone** (não o gpu-operator inteiro): lab enxuto, RuntimeClass `nvidia` mapeando o runtime registrado pela system extension do Talos.
- **Ollama com `qwen3-coder:30b-a3b-q4_K_M`** (MoE 30B total / 3B ativos, q4 = 19GB) — cabe nos 24GB da 3090, mais rápido E mais capaz que um denso 14B. Contexto capado em 32768 (peso + KV não estoura os 24GB).
- **`qwen3-embedding` no LiteLLM é alias FIXO** — nunca renomear (o LightRAG depende dele).
- **DCGM exporter no `kube-system`**: precisa de `SYS_ADMIN`+root; o Talos isenta o kube-system do PodSecurity por default.

## Componentes e ordem de aplicação

| Componente | Projeto | Namespace | sync-wave |
|---|---|---|---|
| RuntimeClass `nvidia` | core | (cluster) | -1 |
| nvidia-device-plugin | core | kube-system | 1 |
| kyverno | core | kyverno | 1 |
| dcgm-exporter | core | kube-system | 2 |
| toolhive operator | core | toolhive-system | (default) |
| MCP servers | ai | ai | (default) |
| ollama | ai | ai | 5 |

> Nunca antes do CNI (Cilium = wave 0).

## Passo a passo

### 7.1 — Talos: habilitar a GPU no worker-3-gpu

System extensions (no schematic do Image Factory): `nvidia-container-toolkit-production` + `nvidia-open-gpu-kernel-modules-production`.

**Labels e taint** (ver Incidente 7.10 — `machine.nodeTaints` é armadilha):
```yaml
# patch do worker-3-gpu
machine:
  nodeLabels:
    nvidia.com/gpu.present: "true"
  kubelet:
    extraConfig:
      registerWithTaints:
        - key: nvidia.com/gpu
          value: present
          effect: NoSchedule
```
`registerWithTaints` só vale no registro do nó. Em nó já joinado, aplicar o taint na mão (bridge único; o config cobre rebuilds):
```bash
kubectl taint node worker-3-gpu nvidia.com/gpu=present:NoSchedule
```

Smoke test:
```bash
kubectl run gpu-smoke --rm -it --restart=Never \
  --overrides='{"spec":{"runtimeClassName":"nvidia","nodeSelector":{"nvidia.com/gpu.present":"true"},"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]}}' \
  --image=nvidia/cuda:12.6.2-base-ubuntu24.04 -- nvidia-smi
kubectl delete pod gpu-smoke --ignore-not-found   # Completed != deletado; segura a GPU
```

### 7.2 — Ollama: pull do modelo e validação do offload
```bash
kubectl -n ai exec deploy/ollama -- ollama pull qwen3-coder:30b-a3b-q4_K_M
kubectl -n ai exec deploy/ollama -- ollama ps          # PROCESSOR = 100% GPU, CONTEXT = 32768
kubectl -n ai exec deploy/ollama -- nvidia-smi          # llama-server ocupando VRAM
```
Storage: o PVC `ollama-models` usa `openebs-hostpath`, cujo BasePath já é `/var/mnt/pv-data/openebs` (user volume Talos = WD Black 2TB no worker-3-gpu). Annotation `argocd.argoproj.io/sync-options: Prune=false` no PVC blinda os modelos contra prune acidental.

### 7.3 — LiteLLM: registrar o modelo local
Adicionar ao `model_list` (sem tocar no `qwen3-embedding`), depois `kubectl -n ai rollout restart deploy/litellm`:
```yaml
- model_name: qwen3-coder-30b-local
  litellm_params:
    model: ollama_chat/qwen3-coder:30b-a3b-q4_K_M
    api_base: http://ollama.ai.svc.cluster.local:11434
    num_ctx: 32768
  model_info:
    mode: chat
```

### 7.4 — MCP servers: smoke test
Cada `MCPServer` validado com um `initialize` retornando `serverInfo` (via proxy streamable-http). `searxng` consome o engine `searxng-engine` (renomeado — ver Incidente 7.7).

### 7.5 — DCGM exporter: ligar a observabilidade da GPU
Após o sync, se a métrica não aparecer no VM, ver Incidente 7.14 (scrape novo exige reload do vmagent):
```bash
kubectl -n observability port-forward svc/vmsingle-victoria-metrics-vmks 8428:8428 &
curl -s 'http://localhost:8428/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | jq '.data.result | length'
```
> Consumo de GPU por workload: filtrar `exported_namespace`/`exported_pod` (o `honor_labels` renomeia as labels do PodMapper; `namespace`/`pod` crus = o próprio exporter).

### ✅ Critério de saída da Fase 7
- [ ] Os 5 MCP servers respondem `initialize` via proxy.
- [ ] `ollama ps` mostra `100% GPU` no `qwen3-coder:30b-a3b-q4_K_M`.
- [ ] LiteLLM expõe `qwen3-coder-30b-local`; inferência ponta a ponta no Open WebUI.
- [ ] `DCGM_FI_DEV_GPU_UTIL` consultável no vmsingle, com labels `exported_*`.

---

## Incidentes

### Incidente 7.1 — `sessionAffinity: ClientIP` do ToolHive quebra com o Cilium

- **Sintoma:** o proxy do MCPServer não alcança o backend; conexões com `EHOSTUNREACH`. O Service de backend que o ToolHive cria vem com `sessionAffinity: ClientIP`.
- **Causa:** o KubeProxyReplacement do Cilium não lida bem com `sessionAffinity: ClientIP` nesse padrão de Service efêmero criado em runtime — o tracking de afinidade aponta pra um endpoint inalcançável.
- **Fix:** ClusterPolicy do Kyverno (`toolhive-backend-svc-session-affinity-none`) que faz mutate `spec.sessionAffinity: None` em Service no ns `ai` com label `toolhive: "true"`.
- **Por que não há loop (importante):** o Service de backend `mcp-<nome>` é criado pelo PROXY em runtime (não está no git → ArgoCD não faz diff dele); o proxy não reconcilia o Service continuamente; o operator gerencia só o Service do PROXY (`app=mcpserver`), que a policy EXCLUI via precondition. Guards: idempotência (`sessionAffinity == ClientIP`) + `metadata.labels.app != mcpserver`.
- **Lição:** mutate de admissão em recurso criado por controller-em-runtime é seguro desde que (a) o recurso não esteja sob reconciliação apertada e (b) a policy seja idempotente e exclua o que o controller-pai gerencia.

### Incidente 7.2 — Quirks do ToolHive operator v0.30.0

- **Sintoma:** mudanças no `MCPServer` não refletem; deletar o Service do backend não o recria; `rollout restart` no proxy é revertido.
- **Causa:** o operator (v0.30.0) não propaga `sessionAffinity` do CR pro Service, não recria Service deletado manualmente, e reverte rollout restart do Deployment do proxy.
- **Fix:** para reiniciar o proxy, **deletar o pod** (não `rollout restart`). Mudanças estruturais no backend = deletar o pod do proxy pra forçar recriação.
- **Lição:** operator imaturo — tratar o Service/Deployment do proxy como efêmero e reconciliado só na criação; intervir no pod, não no controller.

### Incidente 7.3 — github-mcp-server modo http exige OAuth de cliente

- **Sintoma:** o `github` MCPServer em streamable-http nativo falha a autenticação; o proxy não fornece o token que o server espera.
- **Causa:** o `github-mcp-server` v1.4.0 em modo http exige fluxo OAuth de cliente; o proxy do ToolHive não implementa isso.
- **Fix:** rodar em **stdio + `proxyMode: streamable-http`**, com PAT via secret (`GITHUB_PERSONAL_ACCESS_TOKEN` do 1Password `github-mcp/pat`). stdio é imune ao Cilium de quebra.
- **Lição:** quando o server http exige auth de cliente, stdio+proxy contorna e simplifica o secret.

### Incidente 7.4 — ServiceAccount do kubernetes-mcp precisa existir ANTES do MCPServer

- **Sintoma:** o pod do `kubernetes` MCPServer falha (`serviceaccount "kubernetes-mcp" not found`); o StatefulSet entra em backoff e não recupera sozinho mesmo após criar a SA.
- **Causa:** o ToolHive cria o workload referenciando a SA; sem ela na hora da criação, o StatefulSet barra. RBAC split: a SA mora no ns `ai` (App do MCPServer), o ClusterRoleBinding `kubernetes-mcp-view`→ClusterRole `view` mora no `core` (cluster-scoped).
- **Fix:** SA com `sync-wave: "-1"` no ns `ai`; binding no projeto `core`. Para destravar o StatefulSet já em backoff: **deletar o STS** (o operator recria limpo).
- **Lição:** dependência SA→workload precisa de ordering explícito (sync-wave); StatefulSet em backoff após falha de dependência precisa de um kick (delete), não espera.

### Incidente 7.5 — Instalação do Kyverno: drift eterno e CRDs grandes

- **Sintoma:** app do Kyverno fica `OutOfSync` pra sempre; CRDs grandes falham no apply.
- **Causa:** (a) o Helm renderiza `metadata.annotations`/`labels` como `{}` vazios em CRDs, que o k8s descarta → diff permanente; (b) `ClusterRole.rules` agregadas divergem; (c) CRDs grandes estouram o client-side apply.
- **Fix:** `ServerSideApply=true` (CRDs); `ignoreDifferences` em `ClusterRole.rules` e em CRD `.metadata.annotations`/`.metadata.labels` com **group `apiextensions.k8s.io` SEM `/v1`** (usar `/v1` era o bug); sync-wave `1` (pós-CNI). O `skipBackgroundRequests: true` que o Kyverno injeta na policy entra no `ignoreDifferences` ou no manifesto pra zerar o drift.
- **Lição:** `ignoreDifferences` de CRD usa o group puro (`apiextensions.k8s.io`), não `apiextensions.k8s.io/v1`.

### Incidente 7.6 — `enableServiceLinks` injeta env que colide com a config do SearXNG

- **Sintoma:** o engine SearXNG falha a subir / config corrompida; variável `SEARXNG_PORT` com valor `tcp://...`.
- **Causa:** o k8s injeta env vars de service discovery (`<SVC>_PORT=tcp://...`) por default. O Service chamado `searxng` gera `SEARXNG_PORT`, que colide com a env de configuração que o SearXNG espera.
- **Fix:** `enableServiceLinks: false` no pod do engine.
- **Lição:** Service cujo nome (uppercased) bate com uma env de config do app = `enableServiceLinks: false`.

### Incidente 7.7 — Colisão de nome: engine SearXNG × Service do proxy MCP

- **Sintoma:** o Deployment/Service do engine SearXNG conflita com o Service que o ToolHive cria pro MCPServer `searxng`.
- **Causa:** ambos queriam o nome `searxng` no ns `ai`.
- **Fix:** renomear o engine pra **`searxng-engine`** (Deployment, Service e label `app: searxng-engine`); o MCP aponta `SEARXNG_URL=http://searxng-engine.ai.svc.cluster.local:8080`.
- **Lição:** nome do MCPServer reserva o nome no namespace (o ToolHive cria objetos homônimos) — componentes auxiliares precisam de nome distinto.

### Incidente 7.8 — mcp-searxng escuta em 127.0.0.1 (inacessível cross-pod)

- **Sintoma:** o ToolHive marca o MCPServer `Ready`, mas o proxy recebe `connection refused` do backend.
- **Causa:** o `mcp-searxng` faz bind em `127.0.0.1` por default; de outro pod (o proxy) é inalcançável.
- **Fix:** `MCP_HTTP_HOST=0.0.0.0` (+ `MCP_HTTP_PORT=8080`).
- **Lição:** **`Ready` do ToolHive ≠ backend alcançável cross-pod.** Sempre confirmar o bind em `0.0.0.0` em server http nativo.

### Incidente 7.9 — Tag do Docker ≠ versão do app

- **Sintoma:** comportamento/versão do `mcp-searxng` não bate com a tag da imagem.
- **Causa:** a tag Docker (`0.8.0`) estava decoplada da versão interna do app (`1.7.0`).
- **Fix:** usar a tag correta (`1.7.0`) e **pinar por digest** após validar.
- **Lição:** tag não é contrato de versão; pinar digest após o primeiro deploy.

### Incidente 7.10 — `machine.nodeTaints` no Talos é armadilha em nó joinado

- **Sintoma:** aplicar taint via `machine.nodeTaints` falha em worker já no cluster; em cascata, os `nodeLabels` somem.
- **Causa:** o `NodeRestriction` admission bloqueia o kubelet alterando taints de um nó já joinado; e o bug talos#8193 derruba os `nodeLabels` junto.
- **Fix:** `nodeLabels` ficam no `machine.nodeLabels`; o taint vai via `machine.kubelet.extraConfig.registerWithTaints` (vale só no registro) + um `kubectl taint` imperativo como bridge único. Rebuilds ficam cobertos pelo config.
- **Lição:** taint de nó existente no Talos = imperativo; `registerWithTaints` só pra novos registros. Nunca `machine.nodeTaints` em worker joinado.

### Incidente 7.11 — RuntimeClass `scheduling` não basta para DaemonSet

- **Sintoma:** ao subir o DCGM exporter (DaemonSet) só com `runtimeClassName: nvidia`, pods nascem `Pending`/`Unschedulable` em nós sem GPU.
- **Causa:** a injeção de nodeSelector/toleration do bloco `scheduling` da RuntimeClass acontece na ADMISSÃO. O DaemonSet controller decide os nós lendo o TEMPLATE (antes da admissão) → cria pod em todo nó → os de não-GPU travam.
- **Fix:** declarar `nodeSelector` + `toleration` EXPLÍCITOS no template do DaemonSet. A injeção da RuntimeClass por cima é idempotente (mesma chave/valor).
- **Lição:** para DaemonSet, scheduling tem que estar no template — RuntimeClass `scheduling` é tarde demais pro controller.

### Incidente 7.12 — Tag da imagem DCGM: `-distroless`, não `-ubuntu22.04`

- **Sintoma:** pull de `nvcr.io/nvidia/k8s/dcgm-exporter:4.5.3-4.8.2-ubuntu22.04` falha (tag inexistente).
- **Causa:** as versões 4.x do DCGM exporter passaram a publicar `-distroless` como padrão; o sufixo `-ubuntu22.04` foi descontinuado nessa linha.
- **Fix:** usar `4.5.3-4.8.2-distroless`. Verificar tags com `skopeo list-tags docker://nvcr.io/nvidia/k8s/dcgm-exporter` ou `crane ls`.
- **Lição:** distroless não tem shell/curl — probes viram `tcpSocket` e o teste de `/metrics` é via port-forward, não `exec curl`.

### Incidente 7.13 — DCGM exporter em OOMKill com 256Mi

- **Sintoma:** o pod do DCGM exporter entra em OOMKill em loop.
- **Causa:** o DCGM roda o `nv-hostengine` EMBUTIDO no container; com `SYS_ADMIN` + métricas de profiling (`DCGM_FI_PROF_*`) o uso no boot passa dos 256Mi do manifesto oficial.
- **Fix:** subir o limit pra `1Gi` (request `256Mi`). Opcional: counters.csv curado (sem `DCGM_FI_PROF_*`) reduz o footprint e tira a dependência do profiling — recomendado em GPU de consumidor sem MIG.
- **Lição:** o `256Mi` do exemplo oficial é otimista pro hostengine embutido + profiling.

### Incidente 7.14 — Scrape novo invisível até o vmagent recarregar a config

- **Sintoma:** `VMServiceScrape` criado, endpoint do Service vivo, `selectAllByDefault: true`, sem selectors, sem erro no operator — mas a métrica não aparece no vmsingle (`result: []`) e o pool não consta nos `activeTargets` do vmagent.
- **Falso culpado:** discovery cross-namespace. Como o VMAgent tinha `selectAllByDefault: true` e selectors vazios, o namespace nunca foi o bloqueio (mover o scrape pra observability não mudou nada).
- **Diagnóstico:** os únicos pools ativos eram os que JÁ existiam quando o vmagent subiu; o scrape novo (e só ele) faltava → suspeita de config não recarregada.
- **Fix:** `kubectl -n observability rollout restart deploy/vmagent-victoria-metrics-vmks` (ou o operator, se o secret de config nem tiver sido regenerado). Após o restart, a métrica entra (`seriesFetched: 1`).
- **Lição:** scrape novo ausente, com tudo "certo" no diagnóstico estático, geralmente é o vmagent que não releu a config — restart resolve e confirma a causa.

### Incidente 7.15 — Ollama travado: Deployment `missing`/`OutOfSync` no ArgoCD

- **Sintoma:** o Deployment do Ollama não cria pod (`No resources found`); o app aparece com o Deployment `missing` e `OutOfSync`.
- **Causa:** estado de sync do ArgoCD preso (operação anterior não finalizou), impedindo a materialização do Deployment.
- **Fix:** `terminate` no sync preso, depois `sync` + `prune` no app. O Deployment nasce, o pod agenda no worker-3-gpu, o PVC `WaitForFirstConsumer` binda em seguida.
- **Lição:** Deployment `missing`/`OutOfSync` sem pod e sem erro de admissão = sync do Argo travado; `terminate` + `sync/prune` destrava. (O PVC `Pending` com `WaitForFirstConsumer` é consequência — binda quando o pod agenda, não antes.)

# Fase 8 — Analytics / ELT

Plataforma analítica sobre os dados de LLM do Langfuse (custo, latência, erros) + correlação RAG×custo. Batch ELT reusando a ClickHouse existente (Altinity/CHI), orquestrado por Argo Workflows, com migrations via goose e transformações via dbt. Tudo GitOps (ArgoCD app-of-apps), imagens genéricas + "código" (migrations/projeto dbt) entregue por **git artifact** em runtime.

## Decisões de arquitetura

- **Migration: goose** (não Atlas — o driver ClickHouse do Atlas é pago, e o operator da Altinity não gerencia GRANTs declarativamente).
- **Orquestrador: Argo Workflows** (cluster-scoped, `workflowNamespaces: [data]`).
- **Imagens genéricas + git artifact**: `goose-runner` e `dbt-runner` são engines puros (sem migrations/projeto baked). O código vem do repo por `inputs.artifacts: git:` a cada run, com `revision` pinável. Mudar model/seed/migration = só commit+push (sem rebuild de imagem); mudar dependência = rebuild da imagem.
- **ConfigMap só pra arquivos planos e estáticos**; **git artifact pra árvore que cresce** (dbt, e depois o goose também). Motivo de descartar ConfigMap pro dbt: chave de CM não aceita `/`, colisão de basename entre pastas, limite de 1MB.
- **RAG×custo (Nível B)**: 3 projetos no Langfuse logam a mesma chamada (chat→rag→gateway) e **não há elo cross-projeto** (session_id/metadata não compartilhados). Logo: custo = só `gateway` (LiteLLM, ledger com pricing real); `rag` = fronteira semântica. O mart reprecifica os tokens do rag pela taxa $/token do gateway, casando por `model_canonical`. Evita double-count; custo é estimado (taxa blended).

---

## Incidentes

### Orquestração (Argo Workflows)

**[A1] Workflow com `generateName` não é GitOps**
- **Sintoma:** ArgoCD falha o sync com erro de (server-side) apply num objeto com `generateName`.
- **Causa:** `apply` precisa de `name` fixo pra calcular o diff; um `Workflow` one-shot usa `generateName`.
- **Diagnóstico:** o `Workflow` de teste vazou pra um path sincronizado (`chart/templates/`).
- **Fix:** só `WorkflowTemplate`/`CronWorkflow` (nome fixo) vão pro Git. `Workflow` one-shot fica em `workflows/` (fora do `source.path`) e roda imperativo: `kubectl create -f` ou `argo submit --from workflowtemplate/...`.
- **Lição:** GitOps = nome fixo. `generateName` = imperativo. Não existe "Workflow one-shot versionado".

**[A2] `templateRef` não herda `spec.volumes`**
- **Sintoma:** `volume 'migrations' not found in workflow spec` no step `goose-up`, **só** quando rodado pela DAG `analytics-elt`; standalone funcionava.
- **Causa:** `workflowTemplateRef` (no Workflow) copia o spec inteiro da WT (com volumes); `templateRef` (dentro de DAG/steps) empresta **só o template**, não campos spec-level como `volumes`.
- **Diagnóstico:** Etapa 2 (standalone) passou; a DAG não.
- **Fix imediato:** declarar `spec.volumes` também no `analytics-elt`. **Fix definitivo:** migrar as migrations do goose de ConfigMap pra **git artifact** — `inputs.artifacts` É parte do template, então é herdado via `templateRef`. Matou o acoplamento e o volume de vez.
- **Lição:** o que é spec-level não viaja por `templateRef`; `inputs.artifacts` viaja. Git artifact > volume pra qualquer coisa chamada por `templateRef`.

**[A3] Argo 3.6+/v4: breaking changes de schema**
- **Sintoma:** sync failed — `spec.schedules: Required value` (CronWorkflow) e `spec.metrics.prometheus[0].gauge.realtime: Required value` (WorkflowTemplate).
- **Causa:** a 3.6 trocou `schedule` (singular) por `schedules` (lista) e tornou `gauge.realtime` obrigatório.
- **Fix:** `schedules: [ "<cron>" ]`; `realtime: false` no gauge (emite no fim do run, não ao vivo). Counter não precisa.
- **Lição:** ao subir de versão major, validar breaking changes de CRD antes de assumir compat.

### Observabilidade (VictoriaMetrics)

**[O1] Métricas custom do Argo ganham prefixo `argo_workflows_`**
- **Sintoma:** VMRule/queries com `analytics_elt_runs_total` nunca casam, mesmo com a métrica existindo.
- **Causa:** o controller prefixa as métricas custom de workflow com `argo_workflows_`.
- **Diagnóstico:** o nome real no `/metrics` é `argo_workflows_analytics_elt_runs_total`.
- **Fix:** usar o nome **com prefixo** no `expr` da VMRule e em painéis.
- **Lição:** confirmar o nome emitido no `/metrics`, não assumir o nome declarado no manifesto.

**[O2] Endpoint de métricas do Argo 3.6+ é HTTPS por default**
- **Sintoma:** `curl http://<controller>:9090/metrics` retorna vazio (`grep -c '^argo_'` = 0), apesar da porta `metrics=9090` existir.
- **Causa:** `metricsConfig.secure` passou a ter default **true** na 3.6 → o endpoint serve HTTPS com cert self-signed.
- **Diagnóstico:** `curl -sk https://<controller>:9090/metrics` retorna tudo.
- **Fix:** `metricsConfig.secure: false` no controller (configmap, chave única `config`) + **restart do controller** (não faz hot-reload do metricsConfig). VMPodScrape volta pra `scheme: http`. (Alternativa: manter HTTPS e pôr `scheme: https` + `tlsConfig.insecureSkipVerify` no scrape.)
- **Lição:** 3.6 mudou o default pra TLS; `metricsConfig` não recarrega quente.

**[O3] VMPodScrape em outra namespace precisa de `namespaceSelector`**
- **Sintoma:** o target nunca aparece no vmagent (série some na VM), mesmo com o VMPodScrape `operational` e a métrica presente na fonte.
- **Causa:** VMPodScrape em `observability`, sem `namespaceSelector`, só procura pods na **própria** ns; o controller está em `argo-workflows`.
- **Fix:** `spec.namespaceSelector.matchNames: [argo-workflows]`. (Padrão dos outros scrapes que vivem em observability e raspam pods em `data`.)
- **Lição:** scrape cross-namespace exige `namespaceSelector` explícito; `operational` ≠ target ativo.

**[O4] vmagent vs VMSingle pra query**
- **Sintoma:** `unsupported path requested: "/api/v1/query"` na 8429; depois, `result: []`.
- **Causa:** port-forward no **vmagent** (só ingest/buffer; o `/api/v1/query` dele reflete só o buffer local) em vez do **VMSingle** (8428, o storage).
- **Fix:** query no VMSingle (`svc/vmsingle-...:8428`).
- **Lição:** vmagent não é o storage. Query de verdade no VMSingle (ou Grafana Explore / vmui).

### Plataforma de dados (ClickHouse / dbt / goose)

**[D1] CHI da Altinity não cria database declarativamente**
- **Sintoma:** o database `analytics` precisa existir antes do goose (a version table do goose mora nele).
- **Causa:** o operator cobre users/profiles/quotas/topologia, mas não cria database de aplicação.
- **Fix:** step `ensure-db` no Workflow (`curl` no HTTP 8123, `CREATE DATABASE IF NOT EXISTS`), fora do goose.
- **Lição:** database de app no ClickHouse/Altinity = SQL/step, não CHI.

**[D2] `singleBranch: true` no git artifact exige branch explícito**
- **Sintoma:** `artifact repo failed to load: single branch mode without a branch specified`.
- **Causa:** `--single-branch` precisa do nome do branch; `revision` sozinho não basta.
- **Fix:** remover `singleBranch: true` — `depth: 1` já dá o clone raso.
- **Lição:** `singleBranch` só com `branch:` explícito; pra otimizar, `depth` basta.

**[D3] Seed do dbt é CSV puro (agate não suporta `#`)**
- **Sintoma:** `Row N has X values but Table only has 1 columns` + `RuntimeWarning: "<col>" does not match the name of any column`.
- **Causa:** o agate trata `#` como **dado**, não comentário; lê a 1ª linha (um comentário) como header (1 coluna), e estoura quando um comentário tem vírgula.
- **Fix:** CSV sem comentário. Documentação vai na `description` do schema yml.
- **Lição:** seed = CSV puro (header + dados), nada de `#`.

**[D4] Seed se documenta sob a chave `seeds:`, não `models:`**
- **Sintoma:** `WARNING: '<seed>' is a seed node, but it is specified in the models section`; testes do seed ficam **skipados**.
- **Causa:** seed documentado sob `models:` no property file.
- **Fix:** bloco `seeds:` (idealmente em `seeds/_seeds.yml`, co-locado com os CSVs).
- **Lição:** property file separa `models:` de `seeds:`; co-locar com o recurso.

**[D5] Mudar coluna de seed exige recriar a tabela**
- **Sintoma:** `NO_SUCH_COLUMN_IN_TABLE` (ex.: `No such column kind in table analytics.model_dim`).
- **Causa:** `dbt seed` faz **INSERT**, não **ALTER**; a tabela existente tem o schema antigo.
- **Fix:** `DROP TABLE` do seed (ou `dbt build --full-refresh`) **uma vez**; o steady-state segue com `dbt build` normal.
- **Lição:** mudança de coluna de seed = full-refresh pontual.

**[D6] ClickHouse dropa coluna homônima em JOIN**
- **Sintoma:** `UNKNOWN_IDENTIFIER: ... 'project_id' ... Maybe you meant: ['project_name']`; e `Missing columns: 'event_date'`.
- **Causa:** com colunas de mesmo nome nos dois lados do JOIN, o ClickHouse resolve o output como ambíguo e **dropa** a coluna. `t.*` perde a colidente, e **qualificar `o.col` no SELECT não basta** se o outro lado também tiver `col`.
- **Diagnóstico:** o `int_observations_model` (com `o.*` + join no `project_dim`, que tem `project_id`) saía sem `project_id`. Mesmo `o.project_id` explícito não sobreviveu enquanto o lado direito tinha `project_id`.
- **Fix:** renomear a colidente do lado direito num subselect (`project_id as pd_project_id`). No SELECT, usar colunas do lado **esquerdo** e, da direita, só nomes **únicos**. Evitar `*` em models com JOIN.
- **Lição:** em JOIN no ClickHouse, garanta nomes de coluna distintos entre os lados (renomear no subselect quando preciso).

---

## Estado final da app `dbt-analytics`

```
apps/data/dbt-analytics/
├── app.yaml                      # Application (source.path -> chart/), sync-wave 5
├── chart/                        # 1º chart local do repo
│   ├── Chart.yaml / values.yaml  # git (repo/revision/creds), imagens, clickhouse, schedule
│   ├── templates/
│   │   ├── external-secrets.yaml             # clickhouse-analytics (ESO -> 1Password)
│   │   ├── cronworkflow-analytics-elt.yaml   # schedules: [6h], workflowTemplateRef
│   │   ├── vmrule-analytics-elt.yaml         # alerta AnalyticsEltFailed (nome COM prefixo)
│   │   └── workflow-templates/
│   │       ├── clickhouse-migrate.yaml       # ensure-db -> goose-up (migrations via git artifact)
│   │       └── analytics-etl.yaml            # DAG migrate -> dbt-build + spec.metrics
│   └── (sem configmap de migrations — removido na limpeza da verruga)
├── migrations/clickhouse/        # migrations goose (fora do chart; git artifact)
├── dbt/                          # projeto dbt (git artifact)
│   ├── dbt_project.yml / profiles.yml
│   ├── seeds/  model_dim.csv (+ kind), project_dim.csv, _seeds.yml
│   └── models/
│       ├── staging/      stg_observations (+trace_id), stg_traces, _staging.yml
│       ├── intermediate/ int_observations_model (+kind/project, subselect anti-colisão),
│       │                  int_gateway_unit_cost
│       └── marts/        mart_llm_usage_daily, mart_llm_latency_daily, mart_unmapped_models,
│                         mart_rag_cost_daily, mart_rag_interactions
└── workflows/                    # Workflows run-once (generateName, fora do source.path)
```

Imagens (genéricas, `ofwfurtado/`, pin por digest): `goose-runner`, `dbt-runner` em `docker/`.

## Aberto / futuro (não bloqueia a Fase 8)

- **Atribuição exata de custo RAG**: hoje é reprecificação (Nível B) porque não há elo cross-projeto. Propagar um id único Open WebUI→LightRAG→LiteLLM (metadata/session) permitiria join exato e custo real por interação. É mudança nas apps, não no pipeline.
- **Taxa de custo blended**: `int_gateway_unit_cost` mistura input+output. Refinar via `cost_details` (preço de input vs output) se a precisão importar.
- **Alerta de staleness**: complementar o "falhou" com "não rodou em ~2 ciclos".

## Validação (run de fechamento)

`dbt build` → PASS=18, ERROR=0 (5 views, 4 tables, 2 seeds, 7 tests).

`mart_rag_cost_daily` (reprecificação funcionando — retrieval free, geração precificada via gateway):

| kind | model_canonical | tok | cost |
|---|---|---|---|
| completion | deepseek-v4-flash | 8424 | 0.001336 |
| embedding | qwen3-embedding-8b | 57 | 0 |

`mart_rag_interactions` (9 traces; cada trace é OU retrieval OU geração — LightRAG loga operações como traces separados, coerente com o no-link cross-projeto).


# Fase 9 — SSO (Authentik) + Network Policies default-deny

Consolidado dos incidentes e decisões da Fase 9. Formato por incidente:
**Sintoma → Causa → Diagnóstico → Fix → Lição.**

Estado final: SSO via Authentik em 6 apps (ArgoCD, Grafana, Open WebUI, Langfuse
in-cluster; Harbor, Forgejo em VM mgmt). Default-deny **ingress** em `data` e `ai`,
app por app, validado em Cilium Policy Audit Mode. Hubble forward-auth adiado p/ 1.20.

---

## Parte 1 — SSO via Authentik

### 1.1 `grant_types` vazio no Authentik 2026.5

- **Sintoma:** todos os apps OIDC falhavam o fluxo com `invalid_request`.
- **Causa:** o provider OAuth2 do Authentik 2026.5 não defaulta `grant_types`; sem
  ele o provider não anuncia `authorization_code`/`refresh_token`.
- **Diagnóstico:** erro no início do fluxo, antes de qualquer redirect, em todos os
  apps de uma vez → aponta pro IdP, não pro app.
- **Fix:** `grant_types = ["authorization_code", "refresh_token"]` no
  `authentik_provider_oauth2` (via `for_each`, corrigiu os 6 de uma vez).
- **Lição:** erro idêntico em todos os apps = problema no provider compartilhado.

### 1.2 `signing_key` ausente → HS256 vs RS256

- **Sintoma:** "failed to verify the token" nos apps mesmo com login OK no Authentik.
- **Causa:** sem `signing_key`, o Authentik assina o id_token em HS256; os clientes
  esperam RS256 validável via JWKS.
- **Diagnóstico:** discovery expõe `id_token_signing_alg_values_supported: [RS256]`,
  mas o token vinha HS256 (issue goauthentik/terraform-provider #501).
- **Fix:** `signing_key = data.authentik_certificate_key_pair.default.id`
  (`name = "authentik Self-signed Certificate"`).
- **Lição:** OIDC com validação por JWKS exige chave assimétrica; conferir o `alg`
  do token vs `*_signing_alg_values_supported` do discovery.

### 1.3 Recovery flow do Authentik não bound ao brand

- **Sintoma:** novo usuário SSO sem caminho de "esqueci a senha".
- **Causa:** recovery flow não vem vinculado ao brand por padrão.
- **Fix:** usar `password` write-only do 1Password ao criar usuários; akadmin reseta
  como break-glass.
- **Lição:** akadmin é o break-glass de identidade; documentar separado dos apps.

### 1.4 ArgoCD CLI gRPC-web atrás do Gateway — DESCARTADO

- **Sintoma:** `argocd` CLI falhava atrás do Cilium Gateway (Unimplemented →
  `--grpc-web` → timeout :80 → `--skip-test-tls` → 404).
- **Causa:** o Cilium Gateway/Envoy converte gRPC-web→gRPC nativo por padrão
  (`grpcWebTranslation`), e o argocd-server insecure não fala gRPC nativo.
- **Diagnóstico:** causa-raiz isolada, mas fix exigiria GatewayClass dedicada
  (`CiliumGatewayClassConfig{grpcWebTranslation.enabled:false}`).
- **Fix:** **não corrigido por decisão** — over-engineering p/ um lab. CLI fica no
  `argocd login --core`; UI+RBAC via SSO funcionam. Admin local de DR.
- **Lição:** nem todo problema isolado merece fix; registrar a não-decisão e o porquê.

### 1.5 Trailing slash no issuer — Langfuse vs Harbor (OPOSTOS)

- **Sintoma:** Langfuse dava 301 no discovery; Harbor dava "failed to verify
  connection". Mesmo IdP, sintomas diferentes.
- **Causa:** o Authentik emite `issuer` **com** barra final
  (`.../application/o/<slug>/`). As libs reagem ao contrário:
  - **Langfuse** (`openid-client`, Node): concatena a barra → `//.well-known` → 301.
    Precisa do endpoint **SEM** barra.
  - **Harbor** (`go-oidc`, Go): faz `TrimSuffix` pro discovery (200 OK), mas valida
    o `issuer` **literal** contra o do documento → mismatch sem a barra. Precisa
    **COM** barra.
- **Diagnóstico:** `curl` no `.well-known` de dentro do container (prova
  conectividade/cert) + comparar o campo `issuer` do JSON com o configurado.
- **Fix:** Langfuse `AUTH_AUTHENTIK_ISSUER` sem barra; Harbor "Endereço OIDC" com barra.
- **Lição:** o `issuer` do discovery é a autoridade; casar com o que **cada lib**
  espera. "Failed to verify connection" no Harbor com curl OK = mismatch de issuer,
  não conectividade.

### 1.6 Langfuse SSO não provisiona organização

- **Sintoma:** login SSO OK, mas org e projetos somem (visão vazia).
- **Causa:** SSO no Langfuse é **autenticação, não autorização**;
  `ALLOW_ACCOUNT_LINKING` só age na criação; o login gerou identidade sem membership.
- **Diagnóstico:** login local (email/senha) mostra org/projetos intactos → dados não
  sumiram, é a conta SSO sem vínculo.
- **Fix:** Org Settings → Members → Invite member com o email da conta SSO (Owner) →
  relogar.
- **Lição:** diferente de Grafana/Open WebUI (que mapeiam role pelo claim `groups`),
  Langfuse exige provisioning manual de org (Members) ou SCIM.

### 1.7 Harbor exige `offline_access` no scope

- **Sintoma:** login web OK, mas o CLI secret (`docker login`) não sobrevivia.
- **Causa:** o Harbor usa refresh token pra manter o CLI secret; sem `offline_access`
  disponível no provider, não há refresh.
- **Fix:** adicionar o scope mapping `offline_access` ao provider Authentik (lado-IdP,
  Terraform) + incluir no scope do Harbor. `grant_types` já tinha `refresh_token` (1.1).
- **Lição:** `property_mappings` só **disponibiliza** o scope; o app só recebe refresh
  se **pedir** `offline_access` — inócuo pros outros apps.

### 1.8 Harbor — campos da UI trocados

- **Sintoma:** login falhava após o "test OIDC" passar.
- **Causa:** "Atributo com nome do grupo (claim)" preenchido com `preferred_username`
  e "OIDC Group Filter" com `groups` (invertidos).
- **Fix:** Group Claim = `groups`; Group Filter = **vazio**; Username Claim =
  `preferred_username` (habilita só com auto-onboard ligado).
- **Lição:** o "test OIDC" valida só conexão/issuer, não os claims; campos de claim
  só quebram no login real.

### 1.9 Harbor — migração OIDC só sem usuários locais

- **Causa:** o Harbor só troca pra `oidc_auth` se não houver usuário local além do admin.
- **Lição:** conferir antes; usuário local (mesmo deletado) pode travar a migração.

### 1.10 Harbor — DNS split-horizon + wildcard catch-all mascarando NXDOMAIN

- **Sintoma:** "failed to verify connection"; `getent` resolvia
  `auth.mgmt.the-lab.zone` pra **10.40.2.1** (errado; Authentik é 10.40.1.12), cert
  `*.platform.the-lab.zone` não batia.
- **Causa:** a VM usava a UDR (10.40.0.1) como DNS, que não resolve `*.mgmt`. A
  consulta dava NXDOMAIN, o resolver appendava o search domain, e um **wildcard
  catch-all** apontava o nome inventado pra 10.40.2.1.
- **Diagnóstico:** `getent hosts` mostrou o nome canônico com sufixo de search domain
  + IP errado; `curl -v` mostrou cert com CN que não casa o hostname.
- **Fix:** apontar `dns.servers` da VM pro PowerDNS (10.40.1.53) — quem tem a verdade
  do split-horizon.
- **Lição:** wildcard catch-all é perigoso — mascara NXDOMAIN com IP/cert errados em
  vez de falhar limpo. Erro de TLS pode ser sintoma de DNS, não de certificado.

### 1.11 Forgejo — auto-registration via SSO

- **Sintoma:** primeiro login SSO recusado ("registration disabled").
- **Causa:** `FORGEJO__service__DISABLE_REGISTRATION=true` bloqueia o auto-register
  via OAuth (Gitea #16826), mesmo com `ENABLE_AUTO_REGISTRATION=true`.
- **Fix (no compose/`locals.tf`):**
  `DISABLE_REGISTRATION=false` + `ALLOW_ONLY_EXTERNAL_REGISTRATION=true` +
  `oauth2_client.ENABLE_AUTO_REGISTRATION=true` (+ `USERNAME=preferred_username`,
  `ACCOUNT_LINKING=auto`).
- **Lição:** "registro só via SSO" = registro local fechado + externo liberado, não
  registro globalmente desabilitado.

### 1.12 Forgejo — callback = nome da auth source

- **Causa:** o callback é `/user/oauth2/<Authentication Name>/callback`; o
  `<nome>` precisa bater com o redirect no `data.tf`.
- **Lição:** o nome da source não é cosmético — define a URL de redirect.

### 1.13 Hubble forward-auth — ADIADO p/ Cilium 1.20

- **Sintoma:** Hubble UI não tem auth nativa; o `mode=forward_single` do proxy
  provider assume o Gateway fazendo ext_authz.
- **Causa:** o Cilium Gateway API **não** tem external auth no 1.19.4. O
  `HTTPRouteExternalAuth` (GEP-1494, PR #45739) só chega no **1.20**. Alternativa via
  `CiliumEnvoyConfig` cru é frágil (#29831).
- **Fix:** **adiado p/ 1.20.** Hubble UI segue acessível por port-forward. Ao retomar:
  confirmar GEP-1494 GA + Deployment do outpost in-cluster + filtro ext_auth no
  HTTPRoute + `signing_key` no `authentik_provider_proxy.hubble` (ainda falta).
- **Lição:** mesma natureza do 1.4 — não-decisão documentada com gatilho de retomada.

---

## Parte 2 — Network Policies (default-deny ingress em `data` e `ai`)

### Decisões de arquitetura

- **Reuso do AppProject `security`** (não um project/namespace dedicado). Separação
  real vem do **path no Git** (`apps/security/network-policies/`) + **prune por app**,
  não de namespace. As CNPs vão pra `data`/`ai` pelo próprio `metadata.namespace`.
- **Fronteira GitOps:** `manifests/` = enforçado/sincronizado pelo ArgoCD;
  `pending/` = baselines em audit, aplicadas à mão, **fora** do GitOps. Promoção =
  `git mv pending/ → manifests/` (atômico, um arquivo por app).
- **Audit mode é imperativo** (ver 2.6). O ciclo observar→refinar vive fora do Git;
  só o resultado final (CNP com allows, em enforcement) é declarativo.

### 2.1 AppProject recusa destino com namespace vazio

- **Sintoma:** `application destination ... namespace '' do not match any of the
  allowed destinations in project 'security'`.
- **Causa:** o `app.yaml` não fixava `destination.namespace` (de propósito, pois cada
  CNP traz o seu). O ArgoCD valida o par `(server, '')` contra o project, e `''` não
  estava nos destinations.
- **Fix:** fixar `destination.namespace: tetragon` (qualquer namespace já permitido no
  project) — só p/ validação; as CNPs vão pra `data`/`ai` pelo próprio metadata.
- **Lição:** `destination.namespace` cumpre dois papéis — default p/ recursos sem
  namespace **e** o que o project valida. O segundo não aceita vazio.

### 2.2 `ingress: []` é INVÁLIDO no CRD

- **Sintoma:** CNP aplicada mas `VALID: False`; nenhum efeito.
- **Causa:** lista de ingress vazia (`[]`) viola o validador:
  `rule must have at least one of Ingress, IngressDeny, Egress, EgressDeny`.
- **Diagnóstico:** `kubectl get cnp` mostra `VALID False`; `describe` dá a mensagem.
- **Fix:** default-deny ingress puro = **`ingress: - {}`** (uma regra **presente
  porém vazia** = nenhuma origem permitida = nega tudo, e passa na validação).
- **Lição:** `ingress: []` ≠ `ingress: - {}`. O `[]` é inválido; o `- {}` é o
  default-deny. (E `- {}` **não** é allow-all — allow-all seria `fromEntities: [all]`.)

### 2.3 `enableDefaultDeny` sozinho não enforça

- **Causa:** setar só `enableDefaultDeny.ingress: true` sem nenhuma stanza de regra
  não ativa o default-deny (cilium #35558).
- **Lição:** precisa da seção `ingress` com regra (`- {}`); o campo sozinho é insuficiente.

### 2.4 CNP `VALID: False` silenciosa → audit sem efeito

- **Sintoma:** audit mode `Enabled`, mas `hubble observe` vazio com tráfego fluindo.
- **Causa:** a CNP estava `VALID: False` (2.2) → não aplicada a endpoint nenhum →
  endpoint com `policy-enabled: none` → audit mode sem efeito (não há policy p/ auditar).
- **Diagnóstico:** `cilium-dbg endpoint get <id>` mostra `policy-enabled: none` em vez
  de `ingress`.
- **Fix:** corrigir a CNP (2.2) até `VALID: True`; aí `policy-enabled` vira `ingress`.
- **Lição:** depois de aplicar uma CNP, **sempre** conferir `VALID: True` **e** o
  `policy-enabled` do endpoint antes de confiar que o audit observa.

### 2.5 Audit vem `Disabled` por padrão → bloqueio real

- **Sintoma:** Langfuse e LiteLLM `Policy denied DROPPED` na 5432 ao aplicar a baseline
  do Postgres.
- **Causa:** `PolicyAuditMode` vem `Disabled`; aplicar a default-deny sem ligar o audit
  **antes** = enforcement imediato.
- **Fix:** deletar a CNP p/ destravar; reaplicar **só após** `audit ... Enabled`
  confirmado (`audit-status` = Enabled em **todos** os pods do alvo).
- **Lição:** ordem obrigatória: ligar audit → confirmar Enabled → aplicar baseline.
  Nunca aplicar default-deny sem o audit ativo.

### 2.6 `PolicyAuditMode` é imperativo e não persiste

- **Causa:** não é campo de nenhum recurso K8s — é opção de runtime do endpoint
  (`cilium-dbg endpoint config`, ID efêmero). Não declarável em GitOps; reseta em
  restart do agent/pod.
- **Fix:** encapsular o ritual no `mod.just` (`audit Enabled/Disabled`) — comando
  versionado, efeito imperativo.
- **Lição:** o audit é andaime de transição, não estado desejado; por isso fica fora
  do Git. Janela de audit curta por app (restart re-tranca se a CNP já existe).

### 2.7 Pool de conexão persistente esconde os SYN

- **Sintoma:** cliente claramente usando o serviço, mas nenhum verdict de policy.
- **Causa:** o policy-verdict é avaliado na **abertura** (SYN). Pools persistentes
  (Langfuse→PG/CH, operator) reusam conexões abertas antes da policy → sem SYN novo.
- **Fix:** `kubectl rollout restart` no **cliente** (não no destino) p/ forçar
  reabertura → SYN → verdict.
- **Lição:** "sem verdict" ≠ "sem tráfego". Forçar reconexão; e o buffer do Hubble gira
  rápido a alto flows/s — usar `--follow` durante o restart, não `--last` depois.

### 2.8 Labels que fogem do padrão `app.kubernetes.io/name`

- **CNPG:** pods usam `cnpg.io/cluster: <nome>` (aqui `cnpg-cluster`); não filtrar por
  `instanceRole` (cobre primário e réplicas, sobrevive a failover).
- **ClickHouse (Altinity):** `clickhouse.altinity.com/chi: <chi>`.
- **Lição:** confirmar sempre com `kubectl get pod --show-labels` antes de escrever o
  `endpointSelector`.

### 2.9 Argo Workflows — pods sem label estável

- **Sintoma:** o ELT (`analytics-elt`) aparecia no AUDIT com pods cujo único label útil
  (`workflows.argoproj.io/workflow`) muda a cada run.
- **Causa:** pods de workflow não têm label de identidade estável por padrão.
- **Fix:** adicionar `spec.podMetadata.labels` fixo no **WorkflowTemplate** (propaga a
  todos os pods do workflow, inclusive os de `templateRef`). Aqui:
  `app.kubernetes.io/name: analytics-etl`.
- **Lição:** policy que mira workload efêmero (job/workflow) exige um label estável
  **adicionado** ao template. (Nota: label ficou `analytics-etl`, recurso é
  `analytics-elt` — typo histórico, consistente nos dois lados.)

### 2.10 Cross-namespace exige o label de namespace no `fromEndpoints`

- **Causa:** sem `io.kubernetes.pod.namespace: <ns>`, o `matchLabels` casa só dentro do
  namespace da própria CNP.
- **Fix:** todo `fromEndpoints` cross-namespace leva `io.kubernetes.pod.namespace`
  junto do label do app (ex.: vmagent em `observability` → ClickHouse/PG/Garage em `data`).
- **Lição:** allow entre namespaces sem o label de namespace simplesmente não casa.

### 2.11 Origem `ingress` (Gateway/Envoy) usa `fromEntities`, não `fromEndpoints`

- **Sintoma:** Open WebUI (exposto via Gateway) com source identity `reserved:ingress`.
- **Causa:** o último hop é o Envoy do Cilium Gateway, identidade reservada — não um pod.
- **Fix:** `fromEntities: [ingress]` (+ `health`/`host` se aparecerem probes do
  kubelet no AUDIT).
- **Lição:** identidades reservadas (`ingress`, `host`, `health`, `world`,
  `remote-node`) → `fromEntities`. Errar a regra do app exposto **derruba a própria UI**
  — validar abrindo a URL após enforçar.

### 2.12 Fluxos esporádicos só aparecem quando rodam

- **Sintoma:** o ELT (CronWorkflow) só apareceu no AUDIT quando o schedule disparou.
- **Causa:** backups, crons e jobs periódicos não geram tráfego contínuo.
- **Fix:** cobrir um **ciclo completo** na observação; disparar manualmente o que for
  raro (ELT, backup) antes de promover.
- **Lição:** o maior risco do default-deny é o fluxo que você não viu. Promover sem ter
  exercitado um ciclo = descobrir a quebra dias depois. Deixar `--verdict DROPPED`
  rodando após enforçar como rede de segurança.

### 2.13 Operator CNPG não precisou da 5432 (decisão conservadora)

- **Observação:** o `cloudnative-pg` (`cnpg-system`) gerencia o cluster via **instance
  manager (8000)**; restart do operator re-sincronizou sem dropar na 5432.
- **Decisão:** mesmo assim, **liberar 5432 + 8000** pro operator (conservador) — custo
  ~zero (componente confiável do próprio cluster), cobre operações raras que o restart
  não exercita (failover, scale-up, restore).
- **Lição:** mínimo-privilégio vs falhar-em-manutenção. Pra banco, a precaução numa
  regra barata vale mais que o minimalismo. Se escalar p/ HA, reabrir audit no scale-up.

---

## Parte 3 — Observabilidade de drops (alerta de network policy → Slack)

Objetivo: alertar quando uma policy dropa tráfego em `data`/`ai` (sinal de allow
rule faltando). Cadeia: `hubble_drop_total` → VMRule `CiliumPolicyDrop` → vmalert →
vmalertmanager → Slack. A saga foi longa porque cada elo tinha sua pegadinha.

### Decisões de arquitetura

- **VMServiceScrape no MESMO namespace do service alvo.** Scrape cross-namespace
  (scrape em `observability` mirando service em `kube-system` via `namespaceSelector`)
  não funciona de forma confiável no VM operator. Pôr o scrape junto do service.
- **VMRule no app que o alerta monitora** (`network-policies`, ns `observability`) —
  coeso: a regra vive ao lado do que ela vigia. O project `security` já permite
  `observability` e o whitelist `*/*` cobre VMRule.
- **Slack via VMAlertmanagerConfig + ESO**, nunca URL inline. Repo é público → a
  webhook URL vem de Infisical (ExternalSecret) e o `slack_configs.api_url` referencia
  o secret por `{name, key}`, não o valor.
- **Data source-managed alerts** (vmalert avalia, Grafana só UI). Não usar
  Grafana-managed pras mesmas regras (avaliação dupla). vmalert é stateless, estado
  nas próprias métricas.

### 3.1 Hubble não exporta métricas Prometheus

- **Sintoma:** `hubble_drop_total` não existe no VM; Grafana não mostra nada.
- **Causa:** o bloco `hubble` no values do Cilium tinha só `relay` e `ui`, **sem
  `metrics`**. Hubble observava (UI/CLI = flow buffer interno) mas não exportava.
- **Fix:** adicionar `hubble.metrics.enabled` no values do Cilium, com `drop` e
  `labelsContext` p/ ter os labels que tornam o alerta acionável:
  ```yaml
  hubble:
    metrics:
      enableOpenMetrics: true
      enabled:
        - drop:labelsContext=source_namespace,destination_namespace,traffic_direction
        - flow:labelsContext=source_namespace,destination_namespace
        - tcp
        - dns
  ```
- **Lição:** observar (relay/ui) e exportar (metrics) são coisas separadas. `drop`
  não vem por padrão; `labelsContext` é o que dá origem/destino (sem ele, métrica
  existe mas sem saber de onde). Evitar `source_ip`/`destination_ip` (cardinalidade).

### 3.2 A 9965 pareceu servir gRPC em vez de flow metrics

- **Sintoma:** `curl <node-ip>:9965/metrics` retornou `grpc_server_handled_total`,
  `observer.Observer`, `peer.Peer` — não `hubble_drop/flow_*`.
- **Causa:** o curl foi no IP do **nó** (a 9965 tem `hostPort`), e pegou outro
  listener. O metrics server de flow estava OK (log do agent: `Starting Hubble
  metrics server address=:9965 metricConfig="drop flow tcp dns"`).
- **Fix:** testar de dentro via port-forward no **service**:
  `kubectl -n kube-system port-forward svc/hubble-metrics 9965:9965` →
  `curl localhost:9965/metrics | grep -E "^hubble_(drop|flow)"`.
- **Lição:** confirmar a métrica no service (não no hostPort do nó) e via grep
  `hubble_*` (não gRPC). O log do agent é a fonte da verdade de onde o server subiu.

### 3.3 VMServiceScrape cross-namespace não vira target

- **Sintoma:** scrape criado em `observability` mirando `hubble-metrics` em
  `kube-system`; não aparece em `/targets` do vmagent; `hubble_drop_total` ausente.
- **Causa:** o `namespaceSelector` do VMServiceScrape no VM operator é inconsistente —
  o scrape casa services do **próprio namespace** do scrape. Em `observability` ele
  procurava o service ali (não existe) e não gerava target.
- **Fix:** mover o VMServiceScrape p/ `kube-system` (mesmo namespace do service),
  `selector.matchLabels: {k8s-app: hubble}`, `endpoints.port: hubble-metrics` (nome,
  não número). **E reiniciar o operator** (ver 3.7).
- **Lição:** VMServiceScrape junto do service que ele scrapeia. Todos os scrapes que
  funcionam estão co-localizados com o alvo; o único cross-ns era o que falhava.

### 3.4 VMRule não materializada apesar de `selectAllByDefault: true`

- **Sintoma:** VMRule `hubble-policy-drops` criada, válida, sem labels exigidos, mas
  não aparece entre as regras do vmalert no Grafana (262 outras aparecem).
- **Causa:** o operator não reconciliou o VMRule no rulefile do vmalert. Não era
  seletor (`selectAllByDefault: true`) nem label — era reconciliação travada.
- **Fix:** **restart do operator** (ver 3.7). Após isso, apareceu.
- **Lição:** com `selectAllByDefault: true` + VMRule válido + não aparece = quase
  sempre reconciliação. Confirmar no rulefile do vmalert e reiniciar o operator.

### 3.5 Integração Grafana (ver alertas/regras no Grafana)

- **Causa/Fix:** três peças, todas via values (GitOps, sem UI):
  - **Alertmanager datasource** no Grafana (vê firing em Alerting → Active
    notifications): `type: alertmanager`, `url: http://vmalertmanager-...:9093`,
    `jsonData.implementation: prometheus`.
  - **`vmalert.proxyURL`** no `vmsingle.spec.extraArgs` apontando p/
    `http://vmalert-...:8080` — põe a Ruler API na mesma URL da Query API (exigência
    do Grafana p/ data-source-managed).
  - **`jsonData.manageAlerts: true`** no datasource VictoriaMetrics existente.
- **Lição:** "ver regras" (proxyURL + manageAlerts no datasource VM) e "ver firing"
  (Alertmanager datasource) são telas/configs diferentes. O seletor "Choose
  Alertmanager" precisa apontar pro datasource externo, não pro "Grafana" interno.

### 3.6 Alerta não fira no teste por burst vs `for:`

- **Sintoma:** drop gerado (`seq 5 | xargs curl`), métrica sobe, mas `CiliumPolicyDrop`
  não chega a `firing`.
- **Causa:** o `for: 2m` exige o `rate(...[5m])` positivo por 2min contínuos. Um burst
  pontual de curls some antes disso; a regra fica `pending` e volta a `normal`.
- **Fix:** drop **sustentado** > 2min:
  `sh -c 'while true; do curl -m 2 -s http://<ip-clickhouse>:8123; sleep 3; done'`.
- **Lição:** testar alerta com `for:` exige tráfego sustentado, não burst. E o drop
  por policy é **timeout** no curl (sem RST/refused), não erro de conexão.

### 3.7 Padrão recorrente: operator não materializa → restart

- **Sintoma:** recurso do VM operator (VMServiceScrape, VMRule) criado e correto, mas
  não vira config/rulefile/target.
- **Causa:** o operator não reconcilia o recurso novo até ser reiniciado, mesmo com
  `selectAllByDefault: true` e o recurso 100% válido.
- **Fix:** `kubectl -n observability rollout restart deploy/victoria-metrics-victoria-metrics-operator`.
- **Lição:** **aconteceu 3x nesta fase** (scrape, rule, config). Recurso VM correto que
  "não aparece" → primeiro reflexo é reiniciar o operator, não o último recurso.

### 3.8 `useManagedConfig: false` mantém o blackhole e ignora VMAlertmanagerConfigs

- **Sintoma:** SSO/scrape/rule OK, alerta fira, mas não vai pro Slack. O config gerado
  do alertmanager seguia `route.receiver: blackhole`, sem rastro do receiver slack —
  mesmo com `selectAllByDefault: true`, `disableNamespaceMatcher: true`, e o
  VMAlertmanagerConfig `slack` Synced.
- **Causa:** o chart vmks tem `config` **default** (`route.receiver: blackhole`). Com
  `alertmanager.useManagedConfig: false` (default), o chart materializa esse config
  num Secret e seta `configSecret` no VMAlertmanager. **Enquanto `configSecret` está
  setado, o operator IGNORA todos os VMAlertmanagerConfigs.** Remover o `config` do
  values não bastou — o chart caiu no default dele (blackhole).
- **Fix:** `alertmanager.useManagedConfig: true` no values do vmks — o chart deixa de
  setar `configSecret`; o operator passa a combinar os VMAlertmanagerConfigs.
- **Lição:** no vmks, remover `alertmanager.config` não desliga o config default. A
  flag `useManagedConfig: true` é o que libera os VMAlertmanagerConfigs a assumirem.
  Confirmar `kubectl get vmalertmanager ... -o jsonpath='{.spec.configSecret}'` vazio.

### 3.9 Secret `-config` defasado após trocar `useManagedConfig`

- **Sintoma:** após `useManagedConfig: true`, o Slack passou a receber, MAS o secret
  `vmalertmanager-<name>-config` ainda mostrava blackhole no `gunzip`.
- **Causa:** o secret `-config` ficou **órfão/defasado** na transição de modo. O
  config ativo (com o receiver slack como rota filha `continue: true`, sem namespace
  matcher) está no que o **pod** carregou, não nesse secret.
- **Fix:** ler a verdade de dentro do pod:
  `kubectl exec vmalertmanager-...-0 -c alertmanager -- cat /etc/alertmanager/config_out/*.yaml`.
- **Lição:** a fonte da verdade do alertmanager é o config no pod (`config_out/`), não
  o secret `-config` (que pode defasar). A prova definitiva é o comportamento: alerta
  no Slack > leitura de um secret possivelmente obsoleto.

### 3.10 VMAlertmanagerConfig — snake_case no route + namespace matcher

- **Sintoma 1:** sync falhou com `.spec.route.repeatInterval: field not declared in
  schema`.
- **Causa/Fix 1:** o CRD usa **snake_case** no route: `repeat_interval`, `group_wait`,
  `group_interval`, `group_by` (não camelCase). Conferir com
  `kubectl explain vmalertmanagerconfig.spec.route --recursive`.
- **Sintoma 2 (evitado):** VMAlertmanagerConfig tem **namespace matcher forçado** —
  alertas precisam de label `namespace=<ns-do-config>`. O `CiliumPolicyDrop` tem
  `destination_namespace=data/ai`, não casaria.
- **Fix 2:** `disableNamespaceMatcher: true` no VMAlertmanager (sem isso, alerta cai
  no fallback em vez de ir pro Slack).
- **Lição:** snake_case no route do VMAlertmanagerConfig; `disableNamespaceMatcher:
  true` num alertmanager central que roteia alertas de vários namespaces.

---

## Apêndice — Ciclo padrão por app (referência rápida)

```
# 1. label real + nº de pods
kubectl -n <ns> get pod -l <selector> --show-labels

# 2. LIGA audit ANTES de tudo (vem Disabled!)
just apps::network-policies::audit <ns> <selector> Enabled
just apps::network-policies::audit-status <ns> <selector>   # confirma Enabled em TODOS

# 3. aplica baseline (pending/, à mão)
just apps::network-policies::apply-pending <ns>/<app>
kubectl -n <ns> get cnp <app>-default-deny-ingress          # VALID: True
# conferir policy-enabled: ingress no endpoint (cilium-dbg)

# 4. observa (força reconexão dos clientes p/ os SYN aparecerem)
hubble observe --namespace <ns> -l <selector> -t policy-verdict --follow | rg 'AUDITED|DROP'
kubectl -n <client-ns> rollout restart deploy/<cliente>

# 5. cada AUDIT vira allow (fromEndpoints+toPorts; fromEntities p/ ingress/host/health)
#    refina até zerar AUDIT, cobrindo 1 ciclo completo (inclui crons/backups)

# 6. PROMOVE
git mv pending/<ns>/<app>.yaml manifests/<ns>/<app>.yaml
git commit -m "netpol: <app> default-deny ingress"
just apps::network-policies::audit <ns> <selector> Disabled   # vira enforcement

# 7. rede de segurança
hubble observe --namespace <ns> --verdict DROPPED --follow
```

## Apêndice — Cadeia de observabilidade de drops (referência rápida)

```
# 1. Cilium values: habilita métricas Hubble (drop com labelsContext)
#    hubble.metrics.enabled: [drop:labelsContext=..., flow:..., tcp, dns]

# 2. VMServiceScrape em kube-system (mesmo ns do service hubble-metrics)
#    selector k8s-app=hubble, port hubble-metrics  -> RESTART operator

# 3. VMRule CiliumPolicyDrop (rate(hubble_drop_total{reason="POLICY_DENIED",
#    destination_namespace=~"data|ai"}[5m])>0, for:2m)  -> RESTART operator

# 4. Grafana: Alertmanager datasource + vmalert.proxyURL no vmsingle +
#    manageAlerts:true no datasource VM

# 5. Slack: ExternalSecret (webhook do Infisical) + VMAlertmanagerConfig
#    (slack_configs.api_url -> {name,key}; route snake_case)
#    vmks: alertmanager.useManagedConfig:true + disableNamespaceMatcher:true

# Validar fim-a-fim (drop sustentado > for:):
kubectl run droptest -n default --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c 'while true; do curl -m 2 -s http://<ip-clickhouse>:8123; sleep 3; done'
# -> hubble_drop_total++ -> CiliumPolicyDrop firing -> Slack

# Verdade do config do alertmanager (NÃO o secret -config, que pode defasar):
kubectl -n observability exec vmalertmanager-victoria-metrics-vmks-0 -c alertmanager \
  -- cat /etc/alertmanager/config_out/*.yaml
```

## Pendências da Fase 9

- **Hubble forward-auth** → Cilium 1.20 (GEP-1494) + `signing_key` no proxy provider.
- **Egress** em `data`/`ai` (fase futura; lembrar DNS p/ kube-dns:53 e ClickHouse→Garage:3900).
- **Dashboards Tetragon** → confirmar schema dos campos no VictoriaLogs (LogsQL).
- **Secret `-config` órfão** do alertmanager (defasado pós-`useManagedConfig`) — checar
  se o prune do ArgoCD limpou ou se ficou lixo inofensivo.
- **`inhibit_rules`** (severity critical→warning) sumiu ao remover o `config` inline —
  recriar no VMAlertmanagerConfig se quiser a supressão de volta.

## Concluído na Fase 9

- SSO Authentik em 6 apps (ArgoCD, Grafana, Open WebUI, Langfuse; Harbor, Forgejo em VM).
- Default-deny ingress em `data` (clickhouse, postgresql, garage, valkey, qdrant,
  memgraph) e `ai` (open-webui, litellm, langfuse, ollama), app por app, via audit mode.
- Observabilidade de drops: `hubble_drop_total` → VMRule → vmalert → vmalertmanager →
  **Slack**, validada fim-a-fim com drop real.

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

## Apêndice D — comandos úteis da Fase 3

```bash
# CRDs / Gateway
kubectl get crd tlsroutes.gateway.networking.k8s.io -o jsonpath='{.spec.versions[*].name}'
kubectl -n gateway get gateway main -o wide
kubectl -n gateway get svc cilium-gateway-main -o wide

# cert-manager
kubectl get clusterissuer
kubectl -n gateway get certificate,certificaterequest,order,challenge
kubectl -n gateway describe challenge      # quando o DNS-01 trava

# L2
kubectl -n kube-system get lease | grep cilium-l2announce
POD=$(kubectl -n kube-system get pod -l k8s-app=cilium \
  --field-selector spec.nodeName=worker-1 -o name)
kubectl -n kube-system exec "$POD" -- cilium-dbg shell -- db/show l2-announce

# DNS (no LXC)
ss -ulnp | grep -E ':53|:5300'
dig the-lab.zone SOA @127.0.0.1 -p 5300
dig google.com @10.40.1.53
dig hubble.lab.the-lab.zone @10.40.1.53
```

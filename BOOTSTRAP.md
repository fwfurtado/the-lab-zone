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

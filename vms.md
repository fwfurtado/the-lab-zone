# VMs de gestão fora do cluster (Harbor · Forgejo · Authentik)

> Tópico de referência das VMs de **plano de gestão** — serviços que rodam **fora** do
> cluster Kubernetes, numa VM Debian 13 cada, provisionadas por Terraform (bpg/proxmox) e
> com TLS por lego/DNS-01. As três compartilham o **mesmo molde**; este documento descreve
> o padrão comum **uma vez** e depois só os deltas de cada VM.

## Por que fora do cluster

Estas VMs são fundação ou borda do GitOps e **não podem depender do cluster pra existir**:

- **Harbor** (registry/proxy cache): se morasse no cluster, o cluster precisaria do Harbor
  pra puxar imagens e o Harbor precisaria do cluster pra rodar — *chicken-and-egg* de
  bootstrap. Fora, é o **tier-1** que alimenta o cluster.
- **Forgejo** (Git): fonte da verdade do GitOps; o ArgoCD puxa daqui. Não pode estar atrás
  do que ele mesmo provisiona.
- **Authentik** (IdP/SSO): **tier-0**, autentica até serviços off-cluster (Proxmox,
  TrueNAS, e os próprios apps de mgmt). In-cluster, um desastre do cluster derrubaria o SSO
  junto — e você precisaria do SSO pra entrar nas ferramentas de conserto.

Regra geral: **quanto mais baixo o tier, menos ele pode depender de qualquer coisa acima.**
Daí PG/Redis próprios no Authentik (não CNPG/Valkey do cluster), pull direto das imagens
(não via Harbor), e TLS por lego na própria VM (não cert-manager).

## Inventário

| VM | FQDN | IP | Papel | Disco | State (B2) |
|---|---|---|---|---|---|
| `harbor` | `harbor.mgmt.the-lab.zone` | 10.40.1.10 | OCI registry + proxy cache (docker.io/ghcr.io/quay.io) + Trivy | boot 20G + **dados 150G** (`virtio1`→`/data`) | `prod/harbor` |
| `forgejo` | `git.mgmt.the-lab.zone` | 10.40.1.11 | Git (fonte do GitOps) | single + bind-mount `/srv/forgejo` | `prod/forgejo` |
| `authentik` | `auth.mgmt.the-lab.zone` | 10.40.1.12 | IdP / SSO (tier-0) | single 50G (PG+redis no compose) | `prod/authentik` |

Sizing exato (vCPU/RAM) vive no `variables.tf` de cada módulo. Plano de gestão: `10.40.1.x/21`,
gateway `10.40.0.1`. Node Proxmox: `pve`.

---

## Padrão comum (vale para as três)

### Convenção de módulo

`infra/prod/<svc>/` com `provider.tf` · `backend.tf` · `variables.tf` · `main.tf` ·
`locals.tf` · `outputs.tf` · `mod.just`. State no B2 (`the-lab-zone-tf-state`,
`us-east-005`), key `prod/<svc>/terraform.tfstate`. Segredos via 1Password em runtime:
`op run --env-file=../../../.env.tpl -- terraform ...` (vault `homelab`).

### Imagem e VM (bpg/proxmox `~> 0.109`)

- **Debian 13 genericcloud** (`debian-13-genericcloud-amd64.qcow2`), baixada pelo próprio
  Terraform (`proxmox_download_file`, **nome curto** `*.img`, `content_type=iso`,
  `overwrite_unmanaged=true`).
- **`agent { enabled = false }`** — a genericcloud **não traz** o qemu-guest-agent; com
  `enabled=true` o provider trava no Read esperando o agente (~15 min). IP é estático e o
  SSH conecta por IP, então o agente é dispensável.
- **`file_id` do disco de boot é CONSTRUÍDO** dos args configurados do download
  (`"${...datastore_id}:${...content_type}/${...file_name}"`), **não** do `.id` do recurso
  (que é *computed* → "known after apply" → forçaria replace da VM a cada plan). `depends_on`
  garante a ordem em build do zero.
- **cloud-init:** `user_account` com `username = "root"` + a chave pública (a genericcloud
  permite login de root **por chave**); `ip_config` estático `/21` + gateway; `dns.servers
  = [gateway]` (resolve via UDR; **nunca** via si mesma).

### Provisionamento (`terraform_data` + remote-exec)

- SSH como **root**, via **1Password SSH agent** (`connection { agent = true }`).
- **`triggers_replace = [sha1(join("\n", local.<svc>_script))]`** — re-provisiona quando
  **qualquer coisa** no script muda (inclui segredos e config interpolados), contra a mesma
  VM, sem recriar.
- **Top-level 100% POSIX** (o shell de entrada pode ser `dash`, sem `pipefail`/`trap ERR`):
  o `inline` grava `/root/provision-<svc>.sh` e o executa com **`bash` explícito**,
  redirecionando tudo pra `/var/log/<svc>-provision.log`. Os bash-ismos (`set -euo
  pipefail`, `trap ERR`) vivem **dentro** do arquivo. Heredocs **quoted** (`<<'EOF'`) = o
  shell da VM não expande; o Terraform já interpolou os `${...}` antes.
- **Regra de escape:** dentro do script, variáveis de **shell** usam `$VAR` (sem chaves) pra
  não colidir com a interpolação do Terraform; só `${var.x}`/`${local.x}` são do TF. Arquivos
  estáticos com `${}` próprio (ex.: `env_file` do compose) são entregues **via base64**
  (`echo '<b64>' | base64 -d`) pra passar verbatim, sem inferno de escape.
- **Idempotência é requisito** (o provisioner re-roda): todo passo tem que tolerar "já está
  feito". `curl | bash` de instaladores precisa de guard — ver Incidente A-4 do Authentik.

### TLS por lego (DNS-01 Cloudflare) — split-horizon

- Imagem `goacme/lego:v5.2.2` (lego v5: subcomando `run`/`renew` **antes** das flags).
- Token Cloudflare (`Zone:DNS:Edit` em `the-lab.zone`, **mesmo escopo do cert-manager**) em
  `/etc/lego/cloudflare.env` (0600). Emissão **idempotente**:
  `if [ ! -f /etc/lego/certificates/<fqdn>.crt ]; then lego run ...; fi`.
- **`--dns.resolvers 1.1.1.1:53`** (resolver **público**) pro self-check do DNS-01: a vista
  **interna** (PowerDNS) não tem o `_acme-challenge` — ele vive na zona pública Cloudflare.
- Script `<svc>-cert-deploy.sh` copia o `.crt`/`.key` do lego pro destino que o serviço
  consome. Renovação via `lego-renew.service` + `.timer` (daily, `RandomizedDelaySec=3600`,
  `Persistent=true`), com `ExecStartPost` = cert-deploy + reload do serviço.
- **Split-horizon:** o cert vale **só pro FQDN**. O `_acme-challenge` fica na Cloudflare
  (pública); o A record interno (`*.mgmt → IP`) fica no PowerDNS. **Acesse sempre pelo
  nome** — cert de hostname não valida por IP (ver Incidente Authentik A-1).

### DNS (PowerDNS, `10.40.1.53`)

Registros no map `mgmt_records` em `infra/prod/dns/variables.tf`:
`harbor = 10.40.1.10`, `git = 10.40.1.11`, `auth = 10.40.1.12`. Após editar: `just dns
tf-apply`. O cliente (workstation) precisa encaminhar `the-lab.zone` pro PowerDNS — ver
Incidente Authentik A-2.

---

## Harbor (`harbor.mgmt.the-lab.zone`, 10.40.1.10)

Registry OCI: **proxy cache** de `docker.io`/`ghcr.io`/`quay.io`, imagens próprias e
**Trivy**. 4 vCPU / 8GB. **Disco de dados dedicado** (`virtio1` → `/dev/vdb` →
`/data`, `mkfs.ext4`, `backup = false` no disco — DR é app-level).

### Específicos

- **`harbor.yml` a partir do template oficial:** baixa o tarball
  (`harbor-online-installer-<ver>.tgz`, `harbor_version = v2.15.1`) e parte do
  `harbor.yml.tmpl` (que já tem **todos** os campos da versão, ex.: `jobservice.job_loggers`)
  — só troca valores via **`python str.replace`** (literal, não regex). Senhas via **arquivo
  temp** (heredoc quoted = qualquer caractere) lidas no python, pra não quebrar com chars
  especiais. `./install.sh --with-trivy`.
- **TLS:** cert do lego → `/etc/harbor/tls/harbor.crt|key` (0644); `lego-renew`
  `ExecStartPost` = cert-deploy + `cd /opt/harbor && docker compose restart`.
- **Registry mirrors no Talos** (consumidores do proxy cache): patch
  `registry-mirrors.yaml` mapeia `docker.io→dockerhub-proxy`, `ghcr.io→ghcr-proxy`,
  `quay.io→quay-proxy` (endpoints `https://harbor.mgmt.the-lab.zone/v2/<proj>`,
  `overridePath: true`). **Sem `skipFallback`** = fallback implícito pro upstream
  (anti-brick: Harbor cair não trava o pull). **NÃO** espelhar `registry.k8s.io` nem
  `factory.talos.dev` (componentes que sobem o próprio cluster/nós). Rollout **canary**
  (worker-1) antes de todos.
- **Projetos de proxy públicos** (`metadata: {public: "true"}`) pra pull anônimo dos nós.
- **Cache warming:** `crane pull --platform linux/amd64 <ref> /dev/null` por imagem.
  Imagens oficiais precisam do prefixo `library/`; o Cilium é puxado por `@sha256:` (digest,
  sem tag). `just harbor warm-cache` (descobre as imagens rodando) ou lista estática.

### Notas e incidentes (Harbor)

- **lego v5 — ordem do CLI:** `run`/`renew` vêm **antes** das flags (`--dns`, `--domains`,
  `--path`). Inverter = erro silencioso de parse.
- **`registriesconfig` não é recurso COSI** no Talos; validar via `talosctl get mc -o yaml`
  (registries em `persistent` **e** `v1alpha1`) e o `hosts.toml` em
  `/etc/cri/conf.d/hosts/<reg>/`. `resolv.conf = 127.0.0.53` é o stub do hostDNS — normal.
- **DNS SPOF no `nameservers` do Talos:** usar **dois** (`[10.40.1.53, 10.40.0.1]`). O
  `resolv.conf` só faz failover em **timeout** (não em REFUSED), então o PowerDNS único
  seria ponto único de falha pro pull; o secundário (UDR) preserva o fallback anti-brick se
  o LXC do PowerDNS morrer.
- **Senhas no `harbor.yml`:** `str.replace` **literal** (não regex) lendo de arquivo temp —
  caractere especial em senha quebraria um regex/heredoc não-quoted.

---

## Forgejo (`git.mgmt.the-lab.zone`, 10.40.1.11)

Git hosting (Forgejo, `15.0.3+gitea-1.22.0`), via `docker compose`. Disco único, dados em
**bind-mount** `/srv/forgejo`. TLS pelo mesmo padrão lego. SSH de Git na :22 servido pelo
**openssh embutido** na imagem padrão.

### Incidentes (Forgejo)

### Incidente F-1 — `unable to open database file` (SQLite)

- **Sintoma:** o container do Forgejo não sobe; erro de abrir o arquivo de DB.
- **Causa:** o bind-mount `/srv/forgejo/data` nasce **root-owned**; o Forgejo roda como
  uid/gid **1000** e não consegue escrever.
- **Fix:** `chown -R 1000:1000 /srv/forgejo/data` **antes** do `compose up` + `compose
  restart`.
- **Lição:** bind-mount pra processo non-root precisa de `chown` pro uid do container no
  provisionamento (diferente do Postgres, que faz self-chown no entrypoint).

### Incidente F-2 — página de install em 404

- **Sintoma:** a UI de instalação inicial não abre (404).
- **Causa:** a instalação interativa estava travada/concluída sem o lock coerente.
- **Fix:** `INSTALL_LOCK=true` na config — pula o instalador web e sobe já configurado
  (config declarativa via env/app.ini, não pelo wizard).
- **Lição:** em deploy declarativo, travar o instalador web é o esperado — a config vem do
  Terraform/compose, não do wizard.

### Incidente F-3 — crash-loop `listen tcp :22: bind: address already in use`

- **Sintoma:** o container reinicia em loop reclamando da :22 ocupada.
- **Causa:** a imagem **padrão** do Forgejo já roda o **openssh** próprio na :22; ligar o
  servidor SSH interno do Forgejo (`START_SSH_SERVER=true`) colide com ele.
- **Fix:** `START_SSH_SERVER=false` — deixa o openssh da imagem cuidar do Git-over-SSH.
- **Lição:** a imagem padrão ≠ a `rootless`; na padrão o SSH é o openssh do sistema, não o
  embutido do Forgejo.

---

## Authentik (`auth.mgmt.the-lab.zone`, 10.40.1.12)

IdP/SSO **tier-0** (Authentik `2026.5.3`). VM autocontida: **server + worker + Postgres +
Redis** no compose. 2 vCPU / 6GB / disco único 50G. **Backup `pg_dump` → B2** offsite.

### Específicos

- **Compose estático** entregue **verbatim via base64** (toda config por `env_file: .env`,
  zero `${}` de substituição no compose → não colide com a interpolação do Terraform).
- **Pins:** `postgres:16-alpine` (casa com o compose **oficial** 2026.5 — o Helm foi pra
  PG18, o compose **não** — e com o restore, mesmo major); `redis:7-alpine` (cache-only);
  `ghcr.io/goauthentik/server:2026.5.3` (server e worker = mesma imagem, `command:
  server`/`worker`). **Pull direto** (não via Harbor — independência tier-0).
- **Listen `0.0.0.0:9000/9443` explícito:** o 2026.5 mudou o default pra `[::]`; em rede
  Docker IPv4 o publish da 443 não casaria.
- **Cert bring-your-own:** o lego dropa o par em `/opt/authentik/certs/` (key `0644` pro uid
  non-root do Authentik ler); o Authentik faz **auto-discovery** e cria o KeyPair
  `authentik`; **atribuir ao Brand** (System → Brands → default → Web Certificate) é um passo
  **único** (a renovação atualiza o arquivo in-place, mesmo KeyPair).
- **Backup:** `pg_dump -Fc` → `rclone` → bucket B2 `the-lab-zone-authentik-backup` (app key
  **escopada**, criada à mão + 1Password). Timer diário, keep 14. Bucket gerenciado em
  `infra/prod/buckets/b2` (state próprio, `prevent_destroy`). `RCLONE_CONFIG_B2_HARD_DELETE=true`
  pra poda imediata.
- **Handoff:** `AUTHENTIK_BOOTSTRAP_TOKEN` provisiona o token de API do admin na 1ª subida
  (= valor no 1Password) — consumido pelo wiring OIDC dos apps.

### Runbook de RESTORE

Identidade = **`dump` + `AUTHENTIK_SECRET_KEY`** (a key cifra os secrets no DB; vive no
1Password). (1) `just authentik tf-apply` recria a VM com o mesmo SECRET_KEY/PG → `.env`
idêntico, DB vazio. (2) baixar o dump do B2. (3) `docker compose stop server worker` →
`docker compose exec -T postgresql pg_restore -U authentik -d authentik --clean --if-exists
< dump` (mesmo **PG16**) → `docker compose up -d`. (4) reatribuir o cert ao Brand se preciso.

### Incidentes (Authentik)

### Incidente A-1 — cert atribuído ao Brand e o site "não carrega" (IP × cert de hostname)

- **Sintoma:** após atribuir o cert ao Web Certificate do Brand, o site para de abrir;
  containers `Up`/healthy.
- **Causa:** o Web Certificate só afeta a **9443**. O cert vale só pro FQDN e o acesso era
  pelo **IP** — cert de hostname não valida por IP. Antes "funcionava" só porque o
  self-signed dava o click-through.
- **Diagnóstico/recuperação:** a 80→9000 (HTTP) **continua servindo** → `http://<IP>`
  recupera o admin. `openssl s_client -connect <IP>:443 -servername <fqdn> | openssl x509
  -noout -subject` prova o handshake. System → Certificates: KeyPair com "Private key
  available: Yes".
- **Fix:** acessar pelo **FQDN** (depois do DNS). Reverter sem UI:
  `docker compose exec -T worker ak shell` setando `Brand.web_certificate=None`, ou PATCH na
  API por HTTP com o bootstrap token.
- **Lição:** o Web Certificate muda **só a 9443**; a 80 é a rota de socorro. Cert de
  hostname nunca valida por IP — split-horizon = acesse pelo nome.

### Incidente A-2 — `dig @10.40.1.53` resolve, mas `curl`/browser não

- **Sintoma:** `dig +short <fqdn> @10.40.1.53` retorna o IP, mas `curl` dá `Could not
  resolve host`.
- **Causa:** o `dig @53` pergunta **direto** ao PowerDNS; o curl/browser usam o resolver
  **padrão do SO**, que não encaminha `the-lab.zone` pro PowerDNS → DNS público → sem o
  registro (split-horizon).
- **Diagnóstico:** `dig +short harbor.mgmt.the-lab.zone` **sem** `@53` classifica (resolve =
  forward existe + cache negativo; não resolve = sem forward na VLAN).
- **Fix (macOS):** `/etc/resolver/the-lab.zone` com `nameserver 10.40.1.53` +
  `dscacheutil -flushcache; killall -HUP mDNSResponder`. **Sistêmico:** conditional forward
  `the-lab.zone → 10.40.1.53` no UDR/UniFi.
- **Lição:** `dig` **ignora** o `/etc/resolver` — testar com `curl`/`ping`/`dscacheutil`.

### Incidente A-3 — rclone B2 `401 unauthorized` no backup

- **Sintoma:** `rclone ... failed to authorize account: ... 401 unauthorized`. O `pg_dump`
  já rodou — falha só no upload.
- **Causa:** credencial errada (o `b2_authorize_account` falha **antes** de qualquer questão
  de bucket).
- **Diagnóstico:** `cat /root/.authentik-backup.env` (vazio = campos do 1Password não batem
  no `.env.tpl`; preenchido = valor errado); erro completo via `rclone lsd b2: -vv`.
- **Fix:** `RCLONE_CONFIG_B2_ACCOUNT` = **keyID** (não keyName); keyID/appKey não trocados;
  appKey não mal-copiado (só aparece 1x → recriar se errou). Corrigir no 1Password + re-apply.
- **Lição:** erro de auth no B2 é sempre credencial. **keyID ≠ keyName.**

### Incidente A-4 — `tf-apply` exit 3 na RE-provisão (instalador do rclone)

- **Sintoma:** 1ª provisão OK; na 2ª, `remote-exec ... Process exited with status 3`.
- **Causa:** `rclone.org/install.sh` retorna **exit 3** quando o rclone já está atualizado.
  1ª provisão: ausente (exit 0); re-provisão: presente (exit 3) → `set -euo pipefail` aborta.
- **Diagnóstico:** `/var/log/authentik-provision.log` (o `trap` aponta a linha do rclone).
- **Fix:** `command -v rclone >/dev/null 2>&1 || curl -fsSL https://rclone.org/install.sh | bash`.
- **Lição (vale pras três VMs):** todo `curl | bash` num script re-provisionável precisa
  tolerar "já feito". Provisionamento idempotente > assumir estado limpo.

---

## Apêndice — comandos comuns

```bash
# Provisionamento (qualquer das três)
just <svc> tf-init|tf-plan|tf-apply       # svc = harbor | forgejo | authentik
ssh root@<IP> 'tail -n 40 /var/log/<svc>-provision.log'

# TLS (lego) na VM
ssh root@<IP> 'ls -l /etc/lego/certificates/ && systemctl status lego-renew.timer'
openssl s_client -connect <IP>:443 -servername <fqdn> </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -enddate

# DNS split-horizon
dig +short <fqdn> @10.40.1.53        # PowerDNS direto
dig +short <fqdn>                    # resolver default (classifica forward vs cache)

# Harbor
just harbor warm-cache
ssh root@10.40.1.10 'cd /opt/harbor && docker compose ps'

# Forgejo
curl -s https://git.mgmt.the-lab.zone/api/v1/version
ssh root@10.40.1.11 'cd /srv/forgejo && docker compose logs --tail 50'

# Authentik
just authentik check                 # /-/health/live/ e /-/health/ready/
just authentik backup-now            # dispara o backup -> B2 e mostra o journal
```

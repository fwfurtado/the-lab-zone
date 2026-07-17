# the-lab-zone

Homelab Kubernetes em GitOps para infraestrutura, observabilidade, plataforma de dados,
segurança, IA e recuperação de desastre.

O repositório é a fonte de verdade do ambiente `the-lab-zone`: Terraform provisiona a
infraestrutura externa e o cluster é reconciliado pelo Argo CD a partir dos manifests em Git.
A documentação operacional fica em `docs/`, separada entre decisões arquiteturais, setup por
fase e runbooks por sintoma.

## Visão geral

```text
Terraform
  └── Proxmox, DNS, buckets, VMs externas e SSO

Git repository
  └── apps/, projects/ e bootstrap/
          │
          ▼
Argo CD
  └── App-of-apps por domínio
          │
          ▼
Kubernetes/Talos
  ├── core
  ├── observability
  ├── data
  ├── ai
  └── security
```

## Domínios

| Domínio | Conteúdo principal |
|---|---|
| `core` | Argo CD, Cilium, Gateway API, cert-manager, External Secrets, OpenEBS, CNPG operator, ToolHive, Kyverno, Velero |
| `observability` | VictoriaMetrics, VictoriaLogs, Grafana, Alertmanager, OTel Collector, Tempo, Pyroscope, blackbox-exporter |
| `data` | Garage, CNPG/PostgreSQL, ClickHouse, Valkey, Redpanda, Qdrant, Memgraph, dbt/ELT, off-site sync |
| `ai` | Ollama, LiteLLM, Open WebUI, Langfuse, MCP servers, bots/agentes, indexadores e triagem por alerta |
| `security` | NetworkPolicies Cilium, Trivy Operator, Tetragon, Policy Reporter |

## Estrutura do repositório

| Caminho | Função |
|---|---|
| `apps/` | Aplicações reconciliadas pelo Argo CD, organizadas por domínio |
| `projects/` | AppProjects e ApplicationSet raiz por domínio |
| `bootstrap/` | Application raiz do app-of-apps |
| `infra/prod/` | Módulos Terraform de produção |
| `docs/decisions/` | ADRs: por que uma decisão foi tomada |
| `docs/setup/` | Procedimentos de instalação/reconstrução por fase |
| `docs/runbooks/` | Runbooks por sintoma e domínio |
| `scripts/` | Utilitários locais de validação e geração |
| `*.just` | Receitas operacionais via `just` |

## Pré-requisitos locais

O projeto usa `mise` para fixar versões de ferramentas.

```bash
mise install
```

Ferramentas principais:

- `kubectl`, `argocd`, `helm`, `cilium/hubble`
- `terraform`, `talosctl`, `velero`, `sops`, `age`
- `just`, `trivy`, `yamllint`, `rclone`

Para preparar a chave SOPS local:

```bash
just setup
```

## Fluxo GitOps

1. Alterações são feitas em Git.
2. CI valida YAML, Terraform e scripts.
3. O merge em `main` atualiza a fonte de verdade.
4. Argo CD reconcilia os `Application` e `ApplicationSet`.
5. Operações de drift, falha e restore são tratadas pelos runbooks.

O Argo CD é o mecanismo de entrega. Evite aplicar manifests manualmente com `kubectl apply`,
a menos que um runbook indique explicitamente uma ação emergencial.

## Bootstrap e operação

Receitas disponíveis:

```bash
just --list
```

Exemplos úteis:

```bash
just setup
just debug-pod <namespace>
```

Os módulos específicos ficam importados nos arquivos `*.just`:

- `argo.just`
- `garage.just`
- `litellm.just`
- `docker.just`
- `infra/prod/justfile`

## Validação local

Validações recomendadas antes de abrir PR:

```bash
yamllint .
terraform fmt -check -recursive
bash -n scripts/*.sh infra/prod/harbor/*.sh
python3 -m py_compile scripts/*.py
```

Para validar módulos Terraform sem acessar o backend remoto:

```bash
for module in $(find infra/prod -type f -name backend.tf -printf '%h\n' | sort); do
  TF_DATA_DIR="$(mktemp -d)" terraform -chdir="$module" init -backend=false -input=false -lockfile=readonly
  terraform -chdir="$module" validate -no-color
done
```

## Documentação

Comece por:

- [docs/README.md](docs/README.md) — mapa da documentação;
- [docs/decisions/README.md](docs/decisions/README.md) — índice de ADRs;
- [docs/runbooks/INDEX.md](docs/runbooks/INDEX.md) — busca por sintoma;
- [ROADMAP.md](ROADMAP.md) — estado atual e próximos passos.

## Princípios operacionais

- Git é a fonte de verdade.
- Argo CD aplica; humanos propõem via Git.
- Status verde não basta: validar o destino real.
- Backup só conta depois de restore testado.
- NetworkPolicy deve ser aplicada por app, com audit/observabilidade antes.
- Agentes são read-only e propõem mudanças por PR.
- Segredos ficam no 1Password/External Secrets/SOPS, não em manifests plaintext.

## Segurança

Este repositório contém manifests e referências para infraestrutura real de homelab. Não coloque
segredos literais em Git. Use:

- 1Password + External Secrets para segredos do cluster;
- SOPS/age para arquivos criptografados;
- variáveis `TF_VAR_*` via `.env.tpl` e `op://`;
- NetworkPolicies Cilium para isolamento;
- Kyverno para políticas preventivas.

## Status

O ambiente já cobre as fases principais de GitOps, observabilidade, dados, IA, segurança e DR.
Os próximos focos estão descritos em [ROADMAP.md](ROADMAP.md), com prioridade para validação de
restore, CI mais completa, políticas de egress e fortalecimento da supply chain.

# Roadmap — the-lab-zone

Este roadmap registra o estado atual do homelab e os próximos incrementos planejados.

Legenda:

| Estado | Significado |
|---|---|
| Planejado | Ainda não implementado |
| Em andamento | Parcialmente implementado ou em validação |
| Implantado | Reconciliado pelo Argo CD ou provisionado por Terraform |
| Validado | Testado contra o destino real, não apenas status verde |
| Pendente | Existe trabalho conhecido antes de considerar concluído |

## Estado por fase

| Fase | Tema | Estado | Componentes | Próximos critérios de saída |
|---|---|---|---|---|
| 0 | Pré-requisitos | Validado | mise, SOPS/age, 1Password, ferramentas locais | Manter `.mise.toml` atualizado e validar onboarding em máquina limpa |
| 1 | Infra base Talos | Implantado | Proxmox, Talos, Terraform, DNS base | Revalidar rebuild documentado após mudanças de storage/boot |
| 2 | GitOps core | Implantado | Argo CD, ApplicationSet, AppProjects, Cilium, ESO | CI bloqueando PRs inválidos antes do merge em `main` |
| 3 | Ingress, TLS e DNS | Implantado | Gateway API, cert-manager, Cloudflare DNS-01, split-horizon | Testes periódicos de certificado, DNS interno/externo e rotas públicas |
| 4 | Storage LocalPV | Implantado | OpenEBS LocalPV hostpath, classes de storage | Documentar e testar expansão/migração de volumes críticos |
| 5 | Observabilidade | Implantado | VictoriaMetrics, VictoriaLogs, Grafana, Alertmanager, OTel Collector, Tempo, Pyroscope | Alertas sintéticos, testes de roteamento e validação de dashboards |
| 6 | Plataforma de dados | Implantado | Garage, CNPG, Valkey, ClickHouse, Qdrant, Memgraph | Testes recorrentes de backup/restore por store |
| 7 | Stack de IA | Implantado | Ollama, LiteLLM, Open WebUI, Langfuse, ToolHive/MCP, bots e agentes | Limites de custo/contexto, SLOs de agentes e hardening de egress |
| 8 | Analytics/ELT | Implantado | Argo Workflows, dbt, ClickHouse, workflows analíticos | Testes de regressão dos modelos dbt e validação de lineage básico |
| 9 | Segurança + SSO | Implantado | Authentik, Trivy, Tetragon, NetworkPolicies, Policy Reporter, Kyverno | Egress default-deny por app e políticas Kyverno preventivas adicionais |
| 10 | DR | Em andamento | Velero, Barman/CNPG, Garage, B2, off-site sync | Restore completo a partir do B2 em ambiente paralelo |

## Prioridades atuais

### P0 — Confiabilidade e segurança operacional

1. **Validar restore completo a partir do B2**
   - Criar cenário paralelo de rebuild.
   - Restaurar dados críticos fora do cluster original.
   - Registrar evidências no runbook de DR.
   - Critério de saída: dados restaurados e verificados no destino, não apenas backup existente.

2. **Fortalecer CI**
   - Manter a GitHub Action atual como baseline.
   - Adicionar `kubeconform` para manifests Kubernetes.
   - Adicionar detecção de chaves YAML duplicadas.
   - Adicionar `trivy config`.
   - Adicionar `shellcheck`.
   - Critério de saída: PR inválido falha antes do merge.

3. **Remover imagens mutáveis**
   - Substituir `:latest` por versões fixas.
   - Avaliar uso de digest para workloads críticos.
   - Critério de saída: política bloqueando imagens sem tag explícita ou digest.

4. **Egress policies por app**
   - Começar por workloads com tokens: agentes, MCPs, bots, indexadores e CI.
   - Permitir apenas DNS, endpoints internos necessários e APIs externas justificadas.
   - Critério de saída: tráfego negado é observável via Hubble e não quebra fluxos esperados.

### P1 — Supply chain e governança

5. **Renovate ou equivalente**
   - Atualizar Helm charts, imagens OCI, providers Terraform e ferramentas do `mise`.
   - Agrupar updates por domínio.
   - Exigir CI verde.

6. **Políticas Kyverno adicionais**
   - Bloquear `:latest`.
   - Exigir `runAsNonRoot`, `allowPrivilegeEscalation: false`, capabilities dropadas e resources.
   - Criar exceções explícitas para workloads como DCGM.

7. **Proteção de branch**
   - Exigir PR.
   - Exigir status checks.
   - Definir CODEOWNERS para áreas críticas.
   - Avaliar assinatura de commits ou tags.

8. **Assinatura e provenance**
   - Avaliar Tekton ou outro motor de CI interno para builds.
   - Gerar SBOM.
   - Assinar imagens com Cosign.
   - Validar assinaturas com Kyverno antes da admissão.

### P2 — Qualidade, documentação e experiência operacional

9. **`just check`**
   - Agregar validações locais em uma receita única.
   - Espelhar o máximo possível da CI.

10. **Testes sintéticos de observabilidade**
    - Validar rotas do Alertmanager.
    - Validar blackbox probes.
    - Validar dashboards e datasources do Grafana.
    - Validar targets do VictoriaMetrics.

11. **Matriz de restore por componente**
    - CNPG/PostgreSQL.
    - Garage.
    - ClickHouse.
    - Qdrant.
    - Valkey, quando aplicável.
    - Grafana/configuração operacional.

12. **Documentar limites conhecidos**
    - Single-instance intencional em componentes stateful.
    - Dependência de LocalPV.
    - Componentes fora do cluster.
    - Serviços que são lab-only e não HA.

## Backlog por domínio

### Core

- Revisar AppProjects para manter menor privilégio possível.
- Avaliar sync waves e dependências explícitas entre operadores e CRs.
- Adicionar validação automática de CRDs vendorizados.
- Documentar procedimento de upgrade do Argo CD.

### Observability

- Testar alertas críticos com firing sintético.
- Detectar dashboards com UID duplicado antes do deploy.
- Validar health de datasources Grafana via API.
- Padronizar SLOs mínimos para agentes, LLM gateway e stores.

### Data

- Automatizar restore drills.
- Validar retenção e lifecycle nos buckets.
- Adicionar testes de conectividade pós-NetworkPolicy.
- Documentar capacidade, limites e plano de expansão por store.

### AI

- Medir custo e tokens por agente.
- Adicionar egress allowlist específica.
- Separar permissões MCP por persona/caso de uso.
- Registrar avaliações mínimas para triage e QA bot.

### Security

- Expandir Kyverno.
- Revisar CiliumNetworkPolicies por egress.
- Garantir que scanners não tenham permissões excessivas.
- Criar runbook de resposta para achados Trivy/Tetragon.

### DR

- Executar rebuild paralelo a partir do B2.
- Registrar RTO/RPO observado.
- Automatizar verificação de objetos restauráveis.
- Garantir que `rclone check` não aceite vazio-vs-vazio como sucesso operacional.

## CI atual

Baseline inicial:

- `yamllint .`
- `terraform fmt -check -recursive`
- `terraform init -backend=false`
- `terraform validate`
- `bash -n`
- `python3 -m py_compile`

Próximos incrementos sugeridos:

- `kubeconform` com schemas de CRDs;
- `trivy config`;
- `shellcheck`;
- verificação de links Markdown;
- verificação de imagens `:latest`;
- validação de ApplicationSet/AppProject;
- renderização de Helm charts críticos.

## Decisões abertas

| Tema | Opções | Critério de decisão |
|---|---|---|
| CI dentro do cluster | Forgejo Actions, Argo Workflows, Tekton, Woodpecker | Simplicidade vs. supply chain completa |
| Supply chain | Apenas CI, Cosign+SBOM, Tekton Chains | Necessidade de assinatura e provenance |
| Egress default-deny | Por domínio, por app, por perfil | Menor quebra operacional com máxima contenção |
| Atualizações automáticas | Renovate no GitHub, Renovate self-hosted, manual | Controle de ruído e confiabilidade da CI |

## Critérios de maturidade

O homelab será considerado em estado operacional maduro quando:

- toda alteração passar por CI antes do merge;
- nenhuma imagem crítica usar tag mutável;
- restores principais forem testados e documentados;
- NetworkPolicies cobrirem ingress e egress de workloads sensíveis;
- alertas críticos tiverem testes sintéticos;
- dashboards e regras forem validados antes do deploy;
- agentes permanecerem read-only e auditáveis;
- dependências tiverem processo de atualização controlado.

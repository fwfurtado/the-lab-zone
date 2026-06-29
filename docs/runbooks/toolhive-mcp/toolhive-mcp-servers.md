---
tipo: runbook
componente: toolhive-mcp
tags: [toolhive, mcpserver, kyverno, session-affinity, stdio, oauth, serviceaccount, bind-address, searxng]
fases: [7]
relacionado: [runbooks/cilium-rede, runbooks/gitops-argocd]
---

# ToolHive: MCP servers, Kyverno e quirks do operator

Subir MCP servers (`github`, `grafana`, `kubernetes`, `fastcrw`, `searxng`) via ToolHive
operator. Tema central: **`Ready` do ToolHive ≠ backend alcançável cross-pod.**

## `sessionAffinity: ClientIP` do ToolHive quebra com o Cilium

**Sintoma:** o proxy do MCPServer não alcança o backend; conexões com `EHOSTUNREACH`. O Service
de backend que o ToolHive cria vem com `sessionAffinity: ClientIP`.
**Causa:** o KubeProxyReplacement do Cilium não lida bem com `sessionAffinity: ClientIP` nesse
padrão de Service efêmero criado em runtime — o tracking de afinidade aponta pra um endpoint
inalcançável.
**Fix:** ClusterPolicy do Kyverno (`toolhive-backend-svc-session-affinity-none`) que faz mutate
`spec.sessionAffinity: None` em Service no ns `ai` com label `toolhive: "true"`.
**Por que não há loop:** o Service `mcp-<nome>` é criado pelo PROXY em runtime (não está no git
→ ArgoCD não faz diff); o proxy não reconcilia o Service continuamente; o operator gerencia só o
Service do PROXY (`app=mcpserver`), que a policy EXCLUI via precondition. Guards: idempotência
(`sessionAffinity == ClientIP`) + `metadata.labels.app != mcpserver`.
**Lição:** mutate de admissão em recurso criado por controller-em-runtime é seguro desde que (a)
o recurso não esteja sob reconciliação apertada e (b) a policy seja idempotente e exclua o que o
controller-pai gerencia.

## Quirks do ToolHive operator v0.30.0

**Sintoma:** mudanças no `MCPServer` não refletem; deletar o Service do backend não o recria;
`rollout restart` no proxy é revertido.
**Causa:** o operator (v0.30.0) não propaga `sessionAffinity` do CR pro Service, não recria
Service deletado manualmente, e reverte rollout restart do Deployment do proxy.
**Fix:** pra reiniciar o proxy, **deletar o pod** (não `rollout restart`). Mudança estrutural no
backend = deletar o pod do proxy pra forçar recriação.
**Lição:** operator imaturo — tratar o Service/Deployment do proxy como efêmero, reconciliado só
na criação; intervir no pod, não no controller.

## github-mcp-server modo http exige OAuth de cliente

**Sintoma:** o `github` MCPServer em streamable-http nativo falha a autenticação; o proxy não
fornece o token.
**Causa:** o `github-mcp-server` v1.4.0 em modo http exige fluxo OAuth de cliente; o proxy do
ToolHive não implementa.
**Fix:** rodar em **stdio + `proxyMode: streamable-http`**, com PAT via secret
(`GITHUB_PERSONAL_ACCESS_TOKEN`). stdio também é imune ao MTU/drop do Cilium.
**Lição:** quando o server http exige auth de cliente, stdio+proxy contorna e simplifica o secret.

## ServiceAccount do kubernetes-mcp precisa existir ANTES do MCPServer

**Sintoma:** o pod do `kubernetes` MCPServer falha (`serviceaccount "kubernetes-mcp" not
found`); o StatefulSet entra em backoff e não recupera sozinho mesmo após criar a SA.
**Causa:** o ToolHive cria o workload referenciando a SA; sem ela na criação, o STS barra. RBAC
split: a SA mora no ns `ai`, o ClusterRoleBinding mora no `core`.
**Fix:** SA com `sync-wave: "-1"` no ns `ai`; binding no projeto `core`. Pra destravar o STS já
em backoff: **deletar o STS** (o operator recria limpo).
**Lição:** dependência SA→workload precisa de ordering explícito (sync-wave); STS em backoff
após falha de dependência precisa de um kick (delete), não espera.

## Kyverno: drift eterno e CRDs grandes

**Sintoma:** app do Kyverno `OutOfSync` pra sempre; CRDs grandes falham no apply.
**Causa:** (a) o Helm renderiza `metadata.annotations`/`labels` como `{}` vazios em CRDs, que o
k8s descarta → diff permanente; (b) `ClusterRole.rules` agregadas divergem; (c) CRDs grandes
estouram o client-side apply.
**Fix:** `ServerSideApply=true`; `ignoreDifferences` em `ClusterRole.rules` e em CRD
`.metadata.annotations`/`.labels` com **group `apiextensions.k8s.io` SEM `/v1`** (usar `/v1` era
o bug); sync-wave `1` (pós-CNI). O `skipBackgroundRequests: true` que o Kyverno injeta entra no
`ignoreDifferences`.
**Lição:** `ignoreDifferences` de CRD usa o group puro (`apiextensions.k8s.io`), não com `/v1`.

## `enableServiceLinks` colide com a config do SearXNG

**Sintoma:** o engine SearXNG falha a subir; `SEARXNG_PORT` com valor `tcp://...`.
**Causa:** o k8s injeta env de service discovery (`<SVC>_PORT=tcp://...`); o Service `searxng`
gera `SEARXNG_PORT`, que colide com a env de config que o SearXNG espera.
**Fix:** `enableServiceLinks: false` no pod do engine.
**Lição:** Service cujo nome (uppercased) bate com env de config do app = `enableServiceLinks:
false`.

## Colisão de nome: engine SearXNG × Service do proxy MCP

**Sintoma:** o Deployment/Service do engine conflita com o Service que o ToolHive cria pro
MCPServer `searxng`.
**Causa:** ambos queriam o nome `searxng` no ns `ai`.
**Fix:** renomear o engine pra **`searxng-engine`**; o MCP aponta `SEARXNG_URL=http://
searxng-engine.ai.svc.cluster.local:8080`.
**Lição:** nome do MCPServer reserva o nome no namespace (o ToolHive cria objetos homônimos) —
auxiliares precisam de nome distinto.

## mcp-searxng escuta em 127.0.0.1 (inacessível cross-pod)

**Sintoma:** o ToolHive marca o MCPServer `Ready`, mas o proxy recebe `connection refused`.
**Causa:** o `mcp-searxng` faz bind em `127.0.0.1` por default; de outro pod (o proxy) é
inalcançável.
**Fix:** `MCP_HTTP_HOST=0.0.0.0` (+ `MCP_HTTP_PORT=8080`).
**Lição:** **`Ready` do ToolHive ≠ backend alcançável cross-pod.** Sempre confirmar bind em
`0.0.0.0` em server http nativo.

## Tag do Docker ≠ versão do app

**Sintoma:** comportamento/versão do `mcp-searxng` não bate com a tag.
**Causa:** a tag Docker (`0.8.0`) estava decoplada da versão interna do app (`1.7.0`).
**Fix:** usar a tag correta e **pinar por digest** após validar.
**Lição:** tag não é contrato de versão; pinar digest após o primeiro deploy.

## Lição transversal

ToolHive operator é imaturo: trata Service/Deployment do proxy como efêmero (delete pod, não
rollout restart), não propaga campos do CR. `Ready` não prova alcançabilidade — confirmar bind
0.0.0.0 e `initialize` retornando `serverInfo` via proxy. stdio+proxy contorna OAuth e o
MTU/drop do Cilium. Nome do MCPServer reserva o namespace.

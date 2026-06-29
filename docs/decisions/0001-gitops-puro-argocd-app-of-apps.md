---
tipo: adr
numero: 1
titulo: GitOps puro via ArgoCD (app-of-apps), nada instalado à mão após a Fase 2
status: aceito
fases: [2]
---

# ADR-0001 — GitOps puro via ArgoCD (app-of-apps)

## Status
Aceito (Fase 2).

## Contexto
O cluster precisa de um modelo operacional reproduzível para DR. A alternativa seria
instalar componentes imperativamente (helm install, kubectl apply manuais), o que cria
estado órfão que ninguém reconcilia.

## Decisão
Após a Fase 2, **nada mais é instalado manualmente** — todo componente novo entra via
commit. ArgoCD em core mode, app-of-apps, descoberta por `ApplicationSet`
(`directory.recurse: true` + `include: '*/app.yaml'`). Contrato de descoberta: todo
`apps/<domínio>/<componente>/app.yaml` é um Application; o resto (values, manifests) é
material referenciado.

Princípios derivados:
- **O DR aplica o estado final, não reexecuta a história.** Toda config commitada é
  auto-consistente sob convergência fora de ordem (componentes toleram dependências
  ainda-não-prontas com retry/degradar, em vez de falhar fatalmente).
- **Bootstrap e ArgoCD usam os mesmos insumos** (mesmo chart/versão/values/releaseName/
  server-side apply) — é o que garante adoção com diff zero.

## Consequências
- `helm template | kubectl apply --server-side` no bootstrap (não `helm install`), pra não
  criar release órfão.
- Todo chart novo exige whitelist de `sourceRepos` no AppProject antes do `app.yaml`.
- "Quebrar de propósito" pra testar exige pausar selfHeal (ver runbook gitops-argocd).

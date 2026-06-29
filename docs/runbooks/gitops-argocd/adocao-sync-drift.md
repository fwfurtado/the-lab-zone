---
tipo: runbook
componente: gitops-argocd
tags: [server-side-apply, app-yaml, appproject, sourcerepos, drift, selfheal, ignoredifferences, sync-travado]
fases: [2, 5, 7, 10]
---

# ArgoCD: adoção, apply, AppProject, drift e sync travado

Incidentes recorrentes do ArgoCD ao longo de todas as fases.

## CRD estoura o client-side apply (limite 256KB)

**Sintoma:** `The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
metadata.annotations: Too long: may not be more than 262144 bytes`.
**Causa:** `kubectl apply` client-side grava o manifest inteiro na annotation
`last-applied-configuration` (limite 256KB); o schema de CRD grande sozinho estoura.
**Fix:** `kubectl apply --server-side --force-conflicts` nos pipes do bootstrap. O
`--force-conflicts` é necessário quando recursos já foram criados client-side numa
execução interrompida (transferência de field ownership). O mesmo `ServerSideApply=true`
é o que o ArgoCD usa — mesmo mecanismo nas duas eras do cluster.
**Lição:** CRD grande = server-side apply sempre. Estado parcial é inofensivo (apply
incremental, re-executar completa).

## `app.yaml` inválido falha SILENCIOSAMENTE

**Sintoma:** o Application simplesmente não aparece — nada vermelho, só uma ausência.
**Causa:** `app.yaml` commitado sem `apiVersion`/`kind`/`metadata` (fragmento começando
em `spec:`). O discovery encontra, o parse falha, nenhum Application nasce.
**Diagnóstico:** `kubectl -n argocd get app <pai> -o jsonpath='{.status.conditions}'` —
o app PAI acusa o erro de parse.
**Lição:** após todo commit estrutural, conferir não só o que está verde, mas **o que
era esperado e não apareceu** — e as conditions do app pai quando a resposta for estranha.

## Chart barrado pelo AppProject (`sourceRepos` whitelist)

**Sintoma:** Application com "repository not permitted in project".
**Causa:** o AppProject faz whitelist de `sourceRepos`; chart de repo Helm não listado é
rejeitado. Vale também pra `clusterResourceWhitelist` (CRDs de operator) e destinos.
**Fix:** adicionar o repo Helm / CRD / destino ao `projects/<domínio>.yaml` ANTES do
`app.yaml`.

## AppProject recusa destino com namespace vazio

**Sintoma:** `application destination ... namespace '' do not match any of the allowed
destinations`.
**Causa:** o `app.yaml` não fixa `destination.namespace` (de propósito — cada recurso traz
o seu, ex. CNPs). O ArgoCD valida o par `(server, '')` contra o project, e `''` não está
nos destinations.
**Fix:** fixar `destination.namespace: <qualquer-ns-já-permitido>` só p/ validação; os
recursos vão pros seus namespaces pelo próprio metadata.
**Lição:** `destination.namespace` cumpre dois papéis — default p/ recursos sem namespace
E o que o project valida. O segundo não aceita vazio.

## Deployment com strategy imutável (RollingUpdate ↔ Recreate)

**Sintoma:** retry loop com `spec.strategy.rollingUpdate: Forbidden: may not be specified
when strategy type is 'Recreate'`.
**Causa:** o k8s não aceita patch em `spec.strategy` num Deployment existente; a mudança de
tipo é imutável via patch.
**Fix:** `kubectl delete deployment <nome>` + terminate do sync + sync com prune.
**Prevenção:** Deployment com PVC RWO deve ter `strategy.type: Recreate` +
`rollingUpdate: null` **desde o primeiro deploy**.

## sync travado: Deployment `missing`/`OutOfSync` sem pod e sem erro

**Sintoma:** o Deployment não cria pod (`No resources found`); app `missing`/`OutOfSync`,
sem erro de admissão (visto no Ollama, fase 7; e no Velero BSL, 10.5).
**Causa:** estado de sync do ArgoCD preso (operação anterior não finalizou).
**Fix:** `terminate` no sync preso → `sync` + `prune`. (PVC `Pending` com
`WaitForFirstConsumer` é consequência — binda quando o pod agenda.)

## selfHeal reverte patches de teste

**Sintoma:** ao "quebrar de propósito" pra testar alerta (corromper secret/BSL), o ArgoCD
reverte o patch em segundos → teste dá falso-verde. `generation` altíssima no recurso.
**Fix:** `argocd app set <app> --self-heal=false` durante o teste, aplicar o patch
(persiste), rodar, religar `--self-heal=true` (restaura sozinho).
**Lição:** em GitOps, "quebrar de propósito" exige pausar a reconciliação, senão o teste dá
falso-verde. O ESO reforça no caso de secret.

## ignoreDifferences para campos que o controller normaliza

Padrão recorrente: controllers reescrevem campos pós-apply → drift falso-positivo. Casos
vistos: `caBundle` injetado pelo cainjector (VM operator webhook), `ClusterRole.rules`
agregadas + CRD `.metadata.annotations`/`labels` (Kyverno), `archiveLogs` do containerSet
(indexador). Fix: `ignoreDifferences` com `jqPathExpressions`. Detalhe: para CRD, o group
é `apiextensions.k8s.io` **sem** `/v1` (usar `/v1` era o bug, incidente 7.5).

## Lição transversal

ArgoCD é a fonte da verdade — editar à mão recurso gerido por app com selfHeal não cola
(reverte). Diagnóstico: `argocd app diff`, `kubectl -n argocd get app <X> -o
jsonpath='{.status.conditions}'`. Server-side apply pra tudo grande.

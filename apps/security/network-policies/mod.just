cilium_ns := "kube-system"

# Liga/desliga Policy Audit Mode nos endpoints que casam o selector.
# Ex.: just netpol audit data app.kubernetes.io/name=clickhouse Enabled
#      just netpol audit data cnpg.io/cluster=pg Disabled
audit ns selector mode:
    #!/usr/bin/env bash
    set -euo pipefail
    pods=$(kubectl -n {{ns}} get pod -l '{{selector}}' \
            -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
    [ -z "$pods" ] && { echo "nenhum pod casa '{{selector}}' em '{{ns}}'"; exit 1; }
    while read -r pod; do
      [ -z "$pod" ] && continue
      node=$(kubectl -n {{ns}} get pod "$pod" -o jsonpath='{.spec.nodeName}')
      ep=$(kubectl -n {{ns}} get cep "$pod" -o jsonpath='{.status.id}' 2>/dev/null || true)
      if [ -z "$ep" ]; then echo "  ! sem CiliumEndpoint pra $pod (subindo?) — pulando"; continue; fi
      cil=$(kubectl -n {{cilium_ns}} get pod -l k8s-app=cilium \
              --field-selector spec.nodeName="$node" -o jsonpath='{.items[0].metadata.name}')
      echo "==> $pod (ep $ep, nó $node) -> PolicyAuditMode={{mode}}"
      kubectl -n {{cilium_ns}} exec "$cil" -c cilium-agent -- \
        cilium-dbg endpoint config "$ep" PolicyAuditMode={{mode}}
    done <<< "$pods"

# Mostra o estado do audit mode dos endpoints que casam o selector.
# Ex.: just netpol audit-status data app.kubernetes.io/name=clickhouse
audit-status ns selector:
    #!/usr/bin/env bash
    set -euo pipefail
    for pod in $(kubectl -n {{ns}} get pod -l '{{selector}}' \
                  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}'); do
      node=$(kubectl -n {{ns}} get pod "$pod" -o jsonpath='{.spec.nodeName}')
      ep=$(kubectl -n {{ns}} get cep "$pod" -o jsonpath='{.status.id}' 2>/dev/null || true)
      [ -z "$ep" ] && continue
      cil=$(kubectl -n {{cilium_ns}} get pod -l k8s-app=cilium \
              --field-selector spec.nodeName="$node" -o jsonpath='{.items[0].metadata.name}')
      mode=$(kubectl -n {{cilium_ns}} exec "$cil" -c cilium-agent -- \
              cilium-dbg endpoint get "$ep" -o jsonpath='{[*].spec.options.PolicyAuditMode}')
      echo "$pod (ep $ep): ${mode:-Disabled}"
    done

# Observa o que SERIA negado (verdict AUDIT) num namespace, ao vivo.
# Ex.: just netpol observe data
observe ns:
    hubble observe --namespace {{ns}} -t policy-verdict --follow | grep -i audited

# Observa drops REAIS (já em enforcement) num namespace.
# Ex.: just netpol dropped data
dropped ns:
    hubble observe --namespace {{ns}} --verdict DROPPED --follow --output compact

# Aplica uma baseline de pending/ à mão (fora do GitOps, pra fase de audit).
# Ex.: just netpol apply-pending data/clickhouse
apply-pending path:
    kubectl apply -f pendings/{{path}}.yaml

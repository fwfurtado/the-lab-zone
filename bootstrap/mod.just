
export CILIUM_VERSION := "1.19.4"
export ARGOCD_VERSION := "9.5.20"

@run:
    echo "==> [1/4] Cilium"
    helm repo add cilium https://helm.cilium.io/
    helm template cilium cilium/cilium --version $CILIUM_VERSION --namespace kube-system -f ../apps/core/cilium/values.yaml | kubectl apply -f -

    echo "==> Waiting for Nodes to be ready"
    kubectl wait --for=condition=Ready nodes --all --timeout=5m

    echo "==> [2/4] ArgoCD"
    helm repo add argo https://argoproj.github.io/argo-helm --force-update
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    helm template argocd argo/argo-cd --version $ARGOCD_VERSION --namespace argocd -f ../apps/core/argocd/values.yaml | kubectl apply -f -

    echo "==> Waiting for ArgoCD to be ready"
    kubectl -n argocd wait --for=condition=Available deploy  --all --timeout=5m

    echo "==> [3/4] Secret de bootstrap (1Password Connect)"
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

    op document get "1password-connect-credentials" --vault homelab \
    |  kubectl -n external-secrets create secret generic op-connect-credentials --from-file=1password-credentials.json=/dev/stdin --dry-run=client -o yaml \
    | kubectl apply -f -

    kubectl -n external-secrets create secret generic op-connect-token --from-literal=token="$(op read 'op://homelab/1password-connect/token')" --dry-run=client -o yaml | kubectl apply -f -

    echo "==> [4/4] Root app — daqui em diante, GitOps"
    kubectl apply -f root.yaml

    echo "Bootstrap completo. O ArgoCD assume a partir daqui."

[confirm("Are you sure you want to create a new 1Password Connect server?")]
@connet-server-create:
    op connect server create the-lab-zone --vaults the-lab-zone
    op document create 1password-credentials.json --title 1password-connect-credentials --vault homelab
    op item create --vault homelab --title 1password-connect --category password "token=$(op connect token create eso-token --server the-lab-zone --vault the-lab-zone)"
    rm 1password-credentials.json

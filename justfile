import "infra/prod/justfile"

mod bootstrap
mod argo
mod garage
mod litellm

@setup:
    mkdir -p ~/.config/sops/age
    op read "op://homelab/sops-age/private-key" > ~/.config/sops/age/keys.txt


@debug-pod namespace="default":
    kubectl -n {{namespace}} run debug --rm -it --image=curlimages/curl --restart=Never \
      --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"debug","image":"curlimages/curl","stdin":true,"tty":true,"command":["sh"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'

export ARGOCD_OPTS:='--core'
current_ns := `kubectl ns -c`

[private]
@setup:
    kubectl ns argocd > /dev/null 2>&1

[private]
@teardown:
    kubectl ns {{ current_ns }} > /dev/null 2>&1

@login:
    argocd login

@list-apps: setup && teardown
    -argocd app list

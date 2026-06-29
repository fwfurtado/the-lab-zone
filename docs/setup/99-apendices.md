---
tipo: setup
fase: apendices
titulo: Apêndices — rollback, diagnóstico Talos/GitOps, comandos
---

# Apêndices

## A — Rollback da Fase 1
`just talos tf-destroy` remove as 5 VMs e a ISO. Estado externo que pode permanecer: token do
Proxmox, key do B2, bucket de tfstate, chave age, `talsecret.yaml` no repo.
- Recriar o cluster do zero SEM trocar os certificados raiz: manter o `talsecret.yaml` e repetir
  1.4 → 1.6.
- Cluster criptograficamente novo: apagar o `talsecret.yaml` e repetir desde 1.5.

## B — Diagnóstico (Talos sem SSH)
```bash
talosctl -n <IP> dashboard      # console do nó
talosctl -n <IP> dmesg          # kernel log
talosctl -n <IP> services       # estado dos serviços (etcd, kubelet...)
talosctl -n <IP> logs etcd      # log de um serviço
talosctl -n <IP> get members    # membros do cluster vistos pelo nó
```

## C — Diagnóstico (GitOps / secrets)
```bash
just bootstrap check-cilium
just bootstrap check-argocd
just bootstrap argocd-port-forward                                  # UI em localhost:8080
kubectl -n argocd get app <X> -o jsonpath='{.status.conditions}'    # erros de parse/sync
argocd app diff <X>                                                 # diff antes de adoção/sync
kubectl get clustersecretstore onepassword                         # saúde do canal de secrets
kubectl -n external-secrets logs deploy/onepassword-connect -c connect-sync --tail=30
kubectl -n default describe externalsecret <X>                      # events com o erro real
```

## D — Comandos úteis da Fase 3
```bash
# CRDs / Gateway
kubectl get crd tlsroutes.gateway.networking.k8s.io -o jsonpath='{.spec.versions[*].name}'
kubectl -n gateway get gateway main -o wide
kubectl -n gateway get svc cilium-gateway-main -o wide
# cert-manager
kubectl get clusterissuer
kubectl -n gateway get certificate,certificaterequest,order,challenge
kubectl -n gateway describe challenge      # quando o DNS-01 trava
# L2
kubectl -n kube-system get lease | grep cilium-l2announce
# DNS (no LXC)
dig the-lab.zone SOA @127.0.0.1 -p 5300
dig google.com @10.40.1.53
dig hubble.lab.the-lab.zone @10.40.1.53
```

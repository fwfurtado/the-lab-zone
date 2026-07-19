@status:
    kubectl exec -n data garage-0 -c garage -- /garage status
    echo "^== The ID value used to initialize layout"

[arg("id", long="id")]
@init-layout id:
    kubectl exec -n data garage-0 -- /garage layout assign -z dc1 -c 100G {{id}}
    kubectl exec -n data garage-0 -- /garage layout apply --version 1


@set-global-alias:
    #!/usr/bin/env bash
    for name in cnpg-wal langfuse qdrant-snapshots velero clickhouse-backup argo-workflows triage-reports tempo pyroscope lakehouse; do
      id=$(kubectl exec -n data garage-0 -c garage -- /garage bucket list 2>/dev/null | grep ":${name}$" | awk '{print $1}' | cut -d' ' -f1)
      kubectl exec -n data garage-0 -c garage -- /garage bucket alias "$id" "$name"
    done

[arg("keyname", long="keyname")]
@generate-key keyname:
    kubectl exec -n data garage-0 -c garage -- /garage key create {{keyname}}
    echo "⚠️ Store securely the secret. You will not be able to retrieve it later."

[arg("keyid", long="keyid")]
@allow-create-bucket keyid:
    kubectl exec -n data garage-0 -c garage -- /garage key allow --create-bucket {{keyid}}

[arg("keyid", long="keyid")]
[arg("bucket", long="bucket")]
@make-owner-of-bucket keyid bucket:
    kubectl exec -n data garage-0 -c garage -- /garage bucket allow {{bucket}} --read --write --owner --key {{keyid}}


@list-buckets:
    kubectl exec -n data garage-0 -c garage -- /garage bucket list

[arg("keyid", long="keyid")]
@info-key keyid:
    kubectl exec -n data garage-0 -c garage -- /garage key info {{keyid}}


[arg("bucket", long="bucket")]
@info-bucket bucket:
    kubectl exec -n data garage-0 -c garage -- /garage bucket key {{bucket}}

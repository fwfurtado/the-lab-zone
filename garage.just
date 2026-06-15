@status:
    kubectl exec -n data garage-0 -c garage -- /garage status
    echo "^== The ID value used to initialize layout"

[arg("id", long="id")]
@init-layout id:
    kubectl exec -n data garage-0 -- /garage layout assign -z dc1 -c 100G {{id}}
    kubectl exec -n data garage-0 -- /garage layout apply --version 1

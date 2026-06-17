export masterkey := `kubectl -n ai get secret litellm-env -o jsonpath='{.data.masterkey}' | base64 -d`
export litellm_url := 'https://litellm.lab.the-lab.zone'

[arg("keyname", long="keyname")]
@new-virtual-key keyname:
    echo "Generating new virtual key..."
    https -A bearer -a $masterkey "$litellm_url/key/generate" key_alias="{{keyname}}" models:="[]" | jq '.key'

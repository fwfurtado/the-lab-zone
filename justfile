import "infra/prod/justfile"

mod bootstrap

@setup:
    mkdir -p ~/.config/sops/age
    op read "op://homelab/sops-age/private-key" > key.txt

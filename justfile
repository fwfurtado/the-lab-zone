import "infra/prod/justfile"

mod bootstrap

@setup:
    mkdir -p ~/.config/sops/age
    op read "op://homelab/sops-age/private-key" > ~/.config/sops/age/keys.txt

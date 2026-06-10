import "infra/prod/justfile"


@setup:
    mkdir -p ~/.config/sops/age
    op read "op://homelab/sops-age/private-key" > key.txt

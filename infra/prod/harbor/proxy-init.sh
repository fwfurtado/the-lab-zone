#!/usr/bin/env bash
# Cria os 3 registries upstream e os 3 projetos proxy cache no Harbor.
# Idempotente: 409 (ja existe) e contado como sucesso.
# Variaveis vem do `op run --env-file=.env.tpl`:
#   - DOCKERHUB_PROXY_USERNAME / DOCKERHUB_PROXY_TOKEN  (evita rate limit anonimo)
# Senha do admin vem direto do op (nao precisa estar no .env.tpl).
set -euo pipefail

HARBOR_URL="https://harbor.mgmt.the-lab.zone"
ADMIN_PW="$(op read 'op://homelab/Harbor/admin-password')"
AUTH=(-u "admin:${ADMIN_PW}")

api() { curl -fsS -o /dev/null -w '%{http_code}' "${AUTH[@]}" "$@" || true; }

create_registry() {
  local name="$1" type="$2" url="$3" cred_json="$4"
  echo "==> registry ${name} (${type})"
  local body
  body=$(jq -nc --arg n "$name" --arg t "$type" --arg u "$url" \
    --argjson c "$cred_json" \
    '{name:$n, type:$t, url:$u, insecure:false} + (if $c == null then {} else {credential:$c} end)')
  local code
  code=$(api -X POST -H 'Content-Type: application/json' -d "$body" "${HARBOR_URL}/api/v2.0/registries")
  case "$code" in
    201|409) echo "    ok (${code})" ;;
    *)       echo "    FALHOU (${code})"; exit 1 ;;
  esac
}

registry_id() {
  curl -fsS "${AUTH[@]}" "${HARBOR_URL}/api/v2.0/registries?q=name%3D$1" | jq -r '.[0].id'
}

create_proxy_project() {
  local project="$1" reg_name="$2"
  local rid; rid=$(registry_id "$reg_name")
  echo "==> projeto proxy ${project} -> registry_id ${rid}"
  local body
  body=$(jq -nc --arg p "$project" --argjson r "$rid" \
    '{project_name:$p, registry_id:$r, storage_limit:-1, metadata:{public:"true"}}')
  local code
  code=$(api -X POST -H 'Content-Type: application/json' -d "$body" "${HARBOR_URL}/api/v2.0/projects")
  case "$code" in
    201|409) echo "    ok (${code})" ;;
    *)       echo "    FALHOU (${code})"; exit 1 ;;
  esac
}

# Docker Hub: type docker-hub + credencial (dodge do rate limit anonimo 100/6h)
DH_CRED=$(jq -nc --arg k "${DOCKERHUB_PROXY_USERNAME}" --arg s "${DOCKERHUB_PROXY_TOKEN}" \
  '{type:"basic", access_key:$k, access_secret:$s}')
create_registry "dockerhub" "docker-hub" "https://hub.docker.com" "$DH_CRED"

# ghcr.io e quay.io: generic OCI via docker-registry (sem credencial; adicione se precisar)
create_registry "ghcr" "docker-registry" "https://ghcr.io" "null"
create_registry "quay" "docker-registry" "https://quay.io" "null"

create_proxy_project "dockerhub-proxy" "dockerhub"
create_proxy_project "ghcr-proxy"      "ghcr"
create_proxy_project "quay-proxy"      "quay"

echo "==> pronto. valide com: just harbor check"

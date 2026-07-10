#!/usr/bin/env bash
# Compara os dashboards versionados no repo (ConfigMaps) com o que está no banco do
# Grafana. Existe porque, enquanto um uid duplicado bloqueia a escrita dos providers
# ("no database write permissions because of duplicates"), o Grafana segue servindo a
# versão ANTIGA sem erro visível na UI.
#
# Uso:
#   GRAFANA_URL=https://grafana.lab.the-lab.zone \
#   GRAFANA_PW=$(op read "op://the-lab-zone/Grafana/password") \
#   ./check-dashboards-drift.sh
#
# Requer: jq, python3, curl. Rode da raiz do repo.
set -euo pipefail

: "${GRAFANA_URL:?defina GRAFANA_URL}"
: "${GRAFANA_PW:?defina GRAFANA_PW}"
GRAFANA_USER="${GRAFANA_USER:-admin}"

MANIFESTS="apps/observability/grafana/manifests"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
drift=0

for f in "$MANIFESTS"/configmap-*dashboard*.yaml; do
  # extrai uid + JSON canônico (sem campos voláteis) do ConfigMap
  python3 - "$f" > "$tmp/local.json" <<'PY'
import sys, yaml, json
d = yaml.safe_load(open(sys.argv[1]))
key = next(iter(d["data"]))
dash = json.loads(d["data"][key])
for k in ("id", "version"):        # atribuídos pelo Grafana; não comparam
    dash.pop(k, None)
print(json.dumps({"uid": dash.get("uid"), "dash": dash}, sort_keys=True))
PY

  uid=$(jq -r '.uid' "$tmp/local.json")
  jq -S '.dash' "$tmp/local.json" > "$tmp/want.json"

  code=$(curl -s -o "$tmp/resp.json" -w '%{http_code}' -u "$GRAFANA_USER:$GRAFANA_PW" \
           "$GRAFANA_URL/api/dashboards/uid/$uid")
  if [ "$code" != "200" ]; then
    echo "AUSENTE   $uid  (HTTP $code) — nunca foi provisionado"
    drift=1; continue
  fi

  # o que o Grafana serve hoje, mesma normalização
  jq -S 'del(.dashboard.id, .dashboard.version) | .dashboard' "$tmp/resp.json" > "$tmp/have.json"
  updated=$(jq -r '.meta.updated' "$tmp/resp.json")

  if diff -q "$tmp/want.json" "$tmp/have.json" >/dev/null; then
    echo "OK        $uid  (atualizado em $updated)"
  else
    echo "DIVERGE   $uid  (banco atualizado em $updated)"
    diff <(jq -S . "$tmp/want.json") <(jq -S . "$tmp/have.json") | head -20 | sed 's/^/            /'
    drift=1
  fi
done

# Sanidade: nenhum provider pode estar com escrita bloqueada.
echo
echo "--- providers com escrita bloqueada (deve ser vazio) ---"
kubectl -n observability logs deploy/grafana -c grafana 2>/dev/null \
  | grep -i 'no database write permissions' | tail -3 || true

exit "$drift"

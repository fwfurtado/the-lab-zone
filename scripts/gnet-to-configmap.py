#!/usr/bin/env python3
"""Converte um dashboard do grafana.com (gnetId) num ConfigMap versionado.

Por quê: dashboards por `gnetId` no values do chart são baixados por um init
container para /var/lib/grafana/dashboards/default — dentro do PVC. Esse script só
ESCREVE, nunca apaga: remover a entrada do values deixa o .json órfão no disco, o
provider `default` continua carregando, e um uid duplicado com o sidecar REVOGA a
permissão de escrita de todos os providers ("no database write permissions because
of duplicates"), congelando silenciosamente todos os dashboards.

Com ConfigMap: o Argo controla, prune funciona, some a dependência de egress pro
grafana.com no boot, e o dashboard vira revisável em PR.

Uso:
  ./scripts/gnet-to-configmap.py --gnet-id 15661 --revision 1 --name kubernetes-cluster
  ./scripts/gnet-to-configmap.py --gnet-id 763   --revision 5 --name valkey --datasource-type prometheus

Escreve em apps/observability/grafana/manifests/configmap-<name>-dashboard.yaml
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

GNET_URL = "https://grafana.com/api/dashboards/{gid}/revisions/{rev}/download"
OUT_DIR = Path("apps/observability/grafana/manifests")

# Datasource default por tipo, para o `current` da variável.
DEFAULT_DS = {"prometheus": "victoriametrics", "victoriametrics-logs-datasource": "victorialogs"}


def fetch(gnet_id: int, revision: int) -> dict:
    url = GNET_URL.format(gid=gnet_id, rev=revision)
    with urllib.request.urlopen(url, timeout=30) as r:  # noqa: S310
        return json.loads(r.read().decode())


def rewrite(dash: dict, ds_type: str, ds_label: str) -> dict:
    """Troca os placeholders ${DS_*} pela variável de dashboard ${ds} e injeta a var.

    Dashboards do grafana.com trazem `__inputs` (o wizard de importação) e referências
    tipo "${DS_PROMETHEUS}", ora string, ora {"type": ..., "uid": "${DS_PROMETHEUS}"}.
    O chart resolvia isso com `datasource: VictoriaMetrics`; aqui resolvemos com uma
    variável, o que deixa o dashboard imune a troca de UID de datasource.
    """
    # 1) descobre os nomes de input (DS_PROMETHEUS, DS_VICTORIAMETRICS, ...)
    inputs = [i["name"] for i in dash.get("__inputs", []) if i.get("type") == "datasource"]

    blob = json.dumps(dash)
    for name in inputs or ["DS_PROMETHEUS"]:
        blob = blob.replace("${%s}" % name, "${ds}")
    # alguns dashboards referenciam sem as chaves
    blob = re.sub(r'"\$(DS_[A-Z0-9_]+)"', '"${ds}"', blob)
    dash = json.loads(blob)

    # 2) metadados de importação não fazem sentido num dashboard provisionado
    dash.pop("__inputs", None)
    dash.pop("__requires", None)
    # id é do banco; version é gerido pelo Grafana
    dash.pop("id", None)
    dash.pop("version", None)

    # 3) injeta a variável `ds` (idempotente)
    tmpl = dash.setdefault("templating", {}).setdefault("list", [])
    if not any(v.get("name") == "ds" for v in tmpl):
        tmpl.insert(0, {
            "current": {"text": ds_label, "value": DEFAULT_DS.get(ds_type, "")},
            "label": "Datasource",
            "name": "ds",
            "options": [],
            "query": ds_type,
            "refresh": 1,
            "type": "datasource",
        })
    return dash


def to_configmap(name: str, dash: dict, gnet_id: int, revision: int) -> str:
    body = json.dumps(dash, indent=2, ensure_ascii=False)
    indented = "\n".join("    " + line for line in body.splitlines())
    return f"""# Dashboard versionado (era gnetId {gnet_id}, revision {revision}).
# Servido pelo SIDECAR (label grafana_dashboard). Não usar o bloco `dashboards:` do
# chart: aquilo baixa para o PVC e nunca limpa — ver runbook de provisionamento.
#
# Regerar:  ./scripts/gnet-to-configmap.py --gnet-id {gnet_id} --revision {revision} --name {name}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {name}-dashboard
  namespace: observability
  labels:
    grafana_dashboard: "1"
data:
  {name}.json: |
{indented}
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gnet-id", type=int, required=True)
    ap.add_argument("--revision", type=int, required=True)
    ap.add_argument("--name", required=True, help="slug: vira o nome do arquivo, do CM e da chave")
    ap.add_argument("--datasource-type", default="prometheus")
    ap.add_argument("--datasource-label", default="VictoriaMetrics")
    ap.add_argument("--stdout", action="store_true")
    a = ap.parse_args()

    dash = rewrite(fetch(a.gnet_id, a.revision), a.datasource_type, a.datasource_label)
    if not dash.get("uid"):
        print(f"AVISO: dashboard sem uid; usando '{a.name}'", file=sys.stderr)
        dash["uid"] = a.name

    cm = to_configmap(a.name, dash, a.gnet_id, a.revision)
    if a.stdout:
        print(cm)
        return 0

    out = OUT_DIR / f"configmap-{a.name}-dashboard.yaml"
    out.write_text(cm)
    n_ds = json.dumps(dash).count("${ds}")
    print(f"{out}  (uid={dash['uid']}, refs \\${{ds}}={n_ds}, {len(dash.get('panels', []))} painéis)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Runner GENÉRICO do goose. NÃO contém migrations nem lógica de app.
# Recebe tudo via env (GOOSE_DRIVER / GOOSE_DBSTRING / GOOSE_MIGRATION_DIR).
# Reutilizável pra ClickHouse e CNPG/Postgres. bash+jq presentes pra quem precisa
# montar/encodar o DSN no command (caso do ClickHouse).
#
#   docker build -t zot.lab.the-lab.zone/lab/goose-runner:0.1.0 images/goose-runner
#   docker push    zot.lab.the-lab.zone/lab/goose-runner:0.1.0
#   crane digest   zot.lab.the-lab.zone/lab/goose-runner:0.1.0   # -> pinar no values.yaml
#
# Tag não é contrato; o digest é.
FROM debian:bookworm-slim

ARG GOOSE_VERSION=v3.24.1   # CONFIRMAR última: github.com/pressly/goose/releases

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq bash \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://github.com/pressly/goose/releases/download/${GOOSE_VERSION}/goose_linux_x86_64" \
      -o /usr/local/bin/goose \
 && chmod +x /usr/local/bin/goose

ENTRYPOINT ["goose"]

# dbt-runner GENÉRICO: engine dbt-core + adapter clickhouse, vindos do uv.lock deste projeto
# (fidelidade de versão, sem PyPI em runtime). NÃO contém os models/seeds — o projeto vem por
# git artifact do Argo em runtime. Roda qualquer projeto dbt-clickhouse cujas deps caibam neste lock.
#
#   docker build -t zot.lab.the-lab.zone/lab/dbt-runner:0.1.0 apps/data/dbt-analytics/dbt
#   docker push    zot.lab.the-lab.zone/lab/dbt-runner:0.1.0
#   crane digest   zot.lab.the-lab.zone/lab/dbt-runner:0.1.0   # -> pinar em chart/values.yaml
FROM ghcr.io/astral-sh/uv:0.11.21-python3.12-trixie-slim

WORKDIR /opt/dbt
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# só as deps (do lock). Sem COPY . . -> imagem não carrega o projeto.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

# `dbt` no PATH. O projeto e o profiles vêm do git artifact em runtime (workingDir aponta lá).
ENV PATH="/opt/dbt/.venv/bin:$PATH"

ENTRYPOINT ["dbt"]

FROM ghcr.io/berriai/litellm-database:v1.90.2

# Imagem wolfi + uv, sem pip no PATH. Instala o headroom-ai NO venv que o
# LiteLLM usa (/app/.venv) — senão o callback não é importável no startup.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
RUN uv pip install --python /app/.venv/bin/python3 --no-cache "headroom-ai==0.28.0"

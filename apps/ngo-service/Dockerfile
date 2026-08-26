# --- Stage 1: build deps em imagem completa (psycopg2-binary etc precisam de build tools) ---
FROM python:3.11-slim AS builder

WORKDIR /install
COPY requirements.txt .
# --target (não --prefix): gera um diretório flat autocontido. Necessário porque o Python
# do builder (CPython oficial) usa a convenção "site-packages", mas o Python de SISTEMA do
# distroless/python3-debian12 (Debian, na stage runtime) usa a convenção Debian
# "dist-packages" - copiar /install direto para /usr/local faria o interpretador da runtime
# nunca achar os pacotes ("No module named gunicorn"). --target + PYTHONPATH explícito
# ignora essa diferença de convenção por completo.
RUN pip install --no-cache-dir --target=/deps -r requirements.txt

# --- Stage 2: minimal, non-root runtime (distroless = sem shell, sem package manager) ---
FROM gcr.io/distroless/python3-debian12:nonroot AS runtime

WORKDIR /app
COPY --from=builder /deps /deps
COPY app.py otel.py ./

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/deps \
    PORT=8081

USER nonroot
EXPOSE 8081

ENTRYPOINT ["python3"]
CMD ["-m", "gunicorn", "--bind=0.0.0.0:8081", "--workers=2", "--threads=4", "--timeout=30", "app:app"]

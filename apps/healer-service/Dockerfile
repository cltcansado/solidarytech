FROM python:3.11-slim AS builder

WORKDIR /install
COPY requirements.txt .
# --target (não --prefix): ver justificativa em apps/ngo-service/Dockerfile — evita a
# incompatibilidade site-packages (builder) vs dist-packages (Python de sistema Debian
# do distroless runtime).
RUN pip install --no-cache-dir --target=/deps -r requirements.txt

FROM gcr.io/distroless/python3-debian12:nonroot AS runtime

WORKDIR /app
COPY --from=builder /deps /deps
COPY app.py .

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/deps \
    PORT=8090

USER nonroot
EXPOSE 8090

ENTRYPOINT ["python3"]
CMD ["-m", "gunicorn", "--bind=0.0.0.0:8090", "--workers=1", "--threads=4", "--timeout=30", "app:app"]

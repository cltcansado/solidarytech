# --- Stage 1: build binário estático ---
FROM golang:1.25-bookworm AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go otel.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/donation-service .

# --- Stage 2: distroless estático, non-root ---
FROM gcr.io/distroless/static-debian12:nonroot AS runtime

COPY --from=builder /out/donation-service /donation-service

ENV PORT=8082
USER nonroot
EXPOSE 8082

ENTRYPOINT ["/donation-service"]

package main

import (
	"context"
	"log"
	"os"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

// setupTracing configura o exporter OTLP/gRPC para o OpenTelemetry Collector do cluster.
// Se a inicialização falhar (ex: rodando localmente sem collector), o serviço segue
// funcionando sem tracing em vez de derrubar o processo.
func setupTracing(ctx context.Context) func(context.Context) error {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-collector.observability.svc.cluster.local:4317"
	}
	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		environment = "production"
	}

	ctxTimeout, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	exporter, err := otlptracegrpc.New(
		ctxTimeout,
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		log.Printf("aviso: OTel exporter indisponível (%v) - seguindo sem tracing", err)
		return func(context.Context) error { return nil }
	}

	res, _ := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName("donation-service"),
			semconv.ServiceNamespace("solidarytech"),
			semconv.DeploymentEnvironment(environment),
		),
	)

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	log.Printf("OpenTelemetry tracing ativo para 'donation-service' -> %s", endpoint)
	return tp.Shutdown
}

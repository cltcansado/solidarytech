"""
Bootstrap de OpenTelemetry (traces) para os serviços Flask.

Exporta sempre via OTLP/gRPC para o OpenTelemetry Collector rodando como
DaemonSet/Service no cluster (endpoint padrão: otel-collector.observability.svc:4317).
O Collector é quem decide para onde os dados vão de fato (Datadog, New Relic,
Tempo, etc.) - a aplicação nunca fala direto com o vendor de APM.
"""
import logging
import os

log = logging.getLogger(__name__)


def setup_tracing(flask_app, service_name: str):
    if os.getenv("OTEL_SDK_DISABLED", "false").lower() == "true":
        log.info("OTel desabilitado via OTEL_SDK_DISABLED.")
        return

    try:
        from opentelemetry import trace
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.instrumentation.flask import FlaskInstrumentor
        from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
        from opentelemetry.instrumentation.requests import RequestsInstrumentor

        endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector.observability.svc.cluster.local:4317")
        environment = os.getenv("ENVIRONMENT", "production")

        resource = Resource.create({
            "service.name": service_name,
            "service.namespace": "solidarytech",
            "deployment.environment": environment,
        })

        provider = TracerProvider(resource=resource)
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint, insecure=True)))
        trace.set_tracer_provider(provider)

        FlaskInstrumentor().instrument_app(flask_app)
        Psycopg2Instrumentor().instrument()
        RequestsInstrumentor().instrument()

        log.info(f"OpenTelemetry tracing ativo para '{service_name}' -> {endpoint}")
    except Exception as e:  # nunca deixar observabilidade derrubar o serviço
        log.warning(f"Falha ao inicializar OpenTelemetry (seguindo sem tracing): {e}")

import os
import sys
import uuid
import time
import logging

import boto3
import boto3.dynamodb.conditions  # BUG FIX (código-base original): submódulo usado via
                                   # boto3.dynamodb.conditions.Attr(...) sem este import
                                   # explícito -> quebrava em runtime no GET /volunteers/<ngo_id>
from flask import Flask, request, jsonify, Response
from dotenv import load_dotenv
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

from otel import setup_tracing

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)
setup_tracing(app, service_name="volunteer-service")

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE = os.getenv("AWS_DYNAMODB_TABLE")
DYNAMODB_ENDPOINT_URL = os.getenv("AWS_DYNAMODB_ENDPOINT_URL")  # usado só no docker-compose local

if not DYNAMODB_TABLE:
    log.critical("Erro: AWS_DYNAMODB_TABLE não definida.")
    sys.exit(1)

try:
    dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION, endpoint_url=DYNAMODB_ENDPOINT_URL)
    table = dynamodb.Table(DYNAMODB_TABLE)
    log.info(f"Conectado à tabela DynamoDB: {DYNAMODB_TABLE}")
except Exception as e:
    log.critical(f"Falha ao conectar no DynamoDB: {e}")
    sys.exit(1)

REQUEST_COUNT = Counter(
    "http_requests_total", "Total de requisições HTTP",
    ["method", "path", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds", "Latência das requisições HTTP",
    ["method", "path"]
)


@app.before_request
def _start_timer():
    request._start_time = time.time()


@app.after_request
def _record_metrics(response):
    if request.path != "/metrics":
        elapsed = time.time() - getattr(request, "_start_time", time.time())
        REQUEST_LATENCY.labels(request.method, request.path).observe(elapsed)
        REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    return response


@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route('/health')
def health():
    try:
        table.table_status  # força round-trip com o DynamoDB (describe cacheado pelo boto3)
        return jsonify({"status": "ok", "service": "volunteer-service"})
    except Exception as e:
        log.error(f"Health check falhou: {e}")
        return jsonify({"status": "degraded", "service": "volunteer-service"}), 503


@app.route('/volunteers', methods=['POST'])
def register_volunteer():
    data = request.get_json(silent=True)
    if not data or not all(k in data for k in ('name', 'email', 'ngo_id')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    volunteer_id = str(uuid.uuid4())
    item = {
        'volunteer_id': volunteer_id,
        'name': data['name'],
        'email': data['email'],
        'ngo_id': int(data['ngo_id']),
        'registered_at': str(int(time.time()))
    }

    try:
        table.put_item(Item=item)
        return jsonify(item), 201
    except Exception as e:
        log.error(f"Erro ao salvar voluntário no DynamoDB: {e}")
        return jsonify({"error": "Erro interno ao processar dados"}), 500


@app.route('/volunteers/<int:ngo_id>', methods=['GET'])
def get_volunteers_by_ngo(ngo_id):
    try:
        # Nota do código-base original: Scan simplificado para fins didáticos.
        # Em produção real, um GSI por ngo_id evitaria o full-table-scan.
        response = table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr('ngo_id').eq(ngo_id)
        )
        return jsonify(response.get('Items', [])), 200
    except Exception as e:
        log.error(f"Erro ao buscar dados no DynamoDB: {e}")
        return jsonify({"error": "Erro interno"}), 500


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8083))
    app.run(host='0.0.0.0', port=port)

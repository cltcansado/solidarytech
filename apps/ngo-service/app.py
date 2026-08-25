import os
import sys
import time
import logging

import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool
from flask import Flask, request, jsonify, Response
from dotenv import load_dotenv
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

from otel import setup_tracing

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)
setup_tracing(app, service_name="ngo-service")

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    log.critical("Erro: DATABASE_URL não definida.")
    sys.exit(1)

try:
    pool = SimpleConnectionPool(1, 10, dsn=DATABASE_URL)
    log.info("Pool de conexões com o PostgreSQL (ngo-service) inicializado.")
except Exception as e:
    log.critical(f"Erro ao conectar ao PostgreSQL: {e}")
    sys.exit(1)

# --- Golden Metrics (Requests / Latência / Erros) ---
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
    # readiness real: valida se o pool consegue emprestar uma conexão
    try:
        conn = pool.getconn()
        pool.putconn(conn)
        return jsonify({"status": "ok", "service": "ngo-service"})
    except Exception as e:
        log.error(f"Health check falhou: {e}")
        return jsonify({"status": "degraded", "service": "ngo-service"}), 503


@app.route('/ngos', methods=['POST'])
def create_ngo():
    data = request.get_json(silent=True)
    if not data or not all(k in data for k in ('name', 'email', 'cause', 'city')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO ngos (name, email, cause, city) VALUES (%s, %s, %s, %s) RETURNING *",
                (data['name'], data['email'], data['cause'], data['city'])
            )
            new_ngo = cur.fetchone()
            conn.commit()
            return jsonify(new_ngo), 201
    except psycopg2.IntegrityError:
        conn.rollback()
        return jsonify({"error": "E-mail já cadastrado"}), 409
    except Exception as e:
        conn.rollback()
        log.error(f"Erro ao criar ONG: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


@app.route('/ngos', methods=['GET'])
def get_ngos():
    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM ngos ORDER BY id DESC")
            return jsonify(cur.fetchall()), 200
    except Exception as e:
        log.error(f"Erro ao buscar ONGs: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8081))
    app.run(host='0.0.0.0', port=port)

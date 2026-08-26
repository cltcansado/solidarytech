"""
healer-service - automação de resposta a incidentes (self-healing) da SolidaryTech.

Recebe webhooks do Alertmanager (formato padrão do "webhook_config") quando um alerta
de SRE dispara (ex: DonationServiceHighErrorRate, DonationServiceCrashLooping) e executa
um `rollout restart` no Deployment afetado via API do Kubernetes - sem `kubectl` manual e
sem intervenção humana, reduzindo o MTTR do donation-service.

Design deliberadamente conservador:
- Allowlist de deployments que podem ser reiniciados (evita blast radius amplo).
- Cooldown por deployment (evita restart-storm se o Alertmanager reenviar o alerta).
- Toda ação é logada e contabilizada em métrica Prometheus (evidência para o dashboard
  SRE de "automação reduzindo MTTR" e para o relatório de ITSM/AIOps).
"""
import logging
import os
import time
from datetime import datetime, timezone

from flask import Flask, request, jsonify, Response
from kubernetes import client, config
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

app = Flask(__name__)

NAMESPACE = os.getenv("TARGET_NAMESPACE", "solidarytech")
COOLDOWN_SECONDS = int(os.getenv("HEAL_COOLDOWN_SECONDS", "300"))
WEBHOOK_TOKEN = os.getenv("HEALER_WEBHOOK_TOKEN")  # opcional: shared secret validado no header

# alerta Prometheus -> deployment que deve ser reiniciado
ALERT_TO_DEPLOYMENT = {
    "DonationServiceHighErrorRate": "donation-service",
    "DonationServiceHighLatency": "donation-service",
    "DonationServiceCrashLooping": "donation-service",
    "NgoServiceCrashLooping": "ngo-service",
    "VolunteerServiceCrashLooping": "volunteer-service",
}

_last_action = {}  # deployment -> epoch da última ação (cooldown em memória)

HEAL_ACTIONS_TOTAL = Counter(
    "healer_actions_total", "Ações de auto-healing executadas", ["deployment", "alert", "result"]
)

try:
    config.load_incluster_config()
    _k8s_apps = client.AppsV1Api()
    log.info("Cliente Kubernetes (in-cluster) inicializado.")
except Exception as e:
    _k8s_apps = None
    log.warning(f"Sem config in-cluster (ok em dev local, não em produção): {e}")


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "healer-service"})


@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route('/webhook/alertmanager', methods=['POST'])
def alertmanager_webhook():
    if WEBHOOK_TOKEN:
        if request.headers.get("X-Healer-Token") != WEBHOOK_TOKEN:
            return jsonify({"error": "unauthorized"}), 401

    payload = request.get_json(silent=True) or {}
    alerts = payload.get("alerts", [])
    results = []

    for alert in alerts:
        if alert.get("status") != "firing":
            continue

        alertname = alert.get("labels", {}).get("alertname")
        deployment = ALERT_TO_DEPLOYMENT.get(alertname)

        if not deployment:
            log.info(f"Alerta '{alertname}' recebido sem ação de auto-healing mapeada - ignorado.")
            continue

        result = _restart_deployment(deployment, alertname)
        results.append(result)

    return jsonify({"processed": results}), 200


def _restart_deployment(deployment: str, alertname: str) -> dict:
    now = time.time()
    last = _last_action.get(deployment, 0)

    if now - last < COOLDOWN_SECONDS:
        log.info(f"Cooldown ativo para '{deployment}' ({int(now - last)}s desde a última ação) - pulando.")
        HEAL_ACTIONS_TOTAL.labels(deployment, alertname, "skipped_cooldown").inc()
        return {"deployment": deployment, "action": "skipped_cooldown"}

    if _k8s_apps is None:
        log.error("Cliente Kubernetes não inicializado - não é possível executar rollout restart.")
        HEAL_ACTIONS_TOTAL.labels(deployment, alertname, "error_no_client").inc()
        return {"deployment": deployment, "action": "error_no_client"}

    try:
        # equivalente a `kubectl rollout restart deployment/<nome>`, mas via API - sem shell manual.
        now_iso = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S%z')
        body = {
            "spec": {
                "template": {
                    "metadata": {
                        "annotations": {
                            "kubectl.kubernetes.io/restartedAt": now_iso,
                            "solidarytech.io/healed-by": "healer-service",
                            "solidarytech.io/heal-reason": alertname,
                        }
                    }
                }
            }
        }
        _k8s_apps.patch_namespaced_deployment(name=deployment, namespace=NAMESPACE, body=body)
        _last_action[deployment] = now
        log.info(f"AUTO-HEALING: rollout restart disparado em '{deployment}' por causa do alerta '{alertname}'.")
        HEAL_ACTIONS_TOTAL.labels(deployment, alertname, "restarted").inc()
        return {"deployment": deployment, "action": "restarted"}
    except Exception as e:
        log.error(f"Falha ao reiniciar '{deployment}': {e}")
        HEAL_ACTIONS_TOTAL.labels(deployment, alertname, "error").inc()
        return {"deployment": deployment, "action": "error", "detail": str(e)}


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8090))
    app.run(host='0.0.0.0', port=port)

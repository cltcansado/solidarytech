#!/usr/bin/env bash
# Teste de caos deliberado para gravar a evidência de self-healing / MTTR do relatório de SRE
# (docs/SRE-SLI-SLO-SLA.md).
#
# Estratégia: chamar repetidas vezes o endpoint /debug/crash de UM pod específico do
# donation-service (habilitado por CHAOS_ENDPOINTS_ENABLED=true no ConfigMap - ver
# apps/donation-service/main.go). Cada chamada faz o processo sair com exit(1); o kubelet
# reinicia o container NO MESMO pod, sem recriar o pod e sem alterar o Deployment - portanto
# sem disputa com o `selfHeal` do ArgoCD (uma versão anterior deste script quebrava a
# livenessProbe via `kubectl patch`, e o ArgoCD revertia o patch em ~1s, então o alerta
# nunca disparava).
#
# Efeito esperado, em ordem:
#   1. kube_pod_container_status_restarts_total do pod alvo passa de 3 em < 10min
#   2. alerta DonationServiceCrashLooping fica `firing` no Prometheus/Alertmanager (for: 2m)
#   3. Alertmanager faz POST no webhook do healer-service
#   4. healer-service dispara `rollout restart` no deployment -> pods novos e saudáveis
#   5. healer_actions_total{deployment="donation-service",result="restarted"} incrementa
#
# Pré-requisitos: kubeconfig apontando pro cluster (aws eks update-kubeconfig) e o
# donation-service já rodando com CHAOS_ENDPOINTS_ENABLED=true.
# NUNCA rode isso fora de um ambiente de demonstração/hackathon.
set -euo pipefail

NAMESPACE="${NAMESPACE:-solidarytech}"
DEPLOYMENT="donation-service"
# nº de crashes no mesmo pod. > 3 restarts em 10min já satisfaz o alerta; 5 dá folga para
# o alerta sustentar o `for: 2m`. Se o healer agir no meio da bateria, as chamadas restantes
# viram no-op (o pod alvo já foi substituído pelo rollout) - o teste continua válido.
CRASHES="${CRASHES:-5}"
LOCAL_PORT="${LOCAL_PORT:-18082}"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Escolhe o pod mais "velho" (menos provável de ser mexido por um rollout no meio do teste).
POD="$(kubectl -n "$NAMESPACE" get pods -l app="$DEPLOYMENT" \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[0].metadata.name}')"

echo "== [$( ts )] Estado ANTES do caos =="
kubectl -n "$NAMESPACE" get pods -l app="$DEPLOYMENT" -o wide
echo ""
echo "Pod alvo: $POD"
echo "Vão ser $CRASHES crashes nesse pod (acompanhe em outro terminal:"
echo "  watch kubectl -n $NAMESPACE get pods -l app=$DEPLOYMENT)"
echo ""

crash_once() {
  # (re)abre o port-forward a cada iteração: ele cai quando o container reinicia.
  kubectl -n "$NAMESPACE" port-forward "pod/$POD" "$LOCAL_PORT:8082" >/dev/null 2>&1 &
  local pf=$!
  # espera o port-forward subir
  for _ in $(seq 1 20); do
    curl -s -o /dev/null "http://localhost:$LOCAL_PORT/live" && break || sleep 0.5
  done
  curl -s -m 3 -X POST "http://localhost:$LOCAL_PORT/debug/crash" || true
  kill "$pf" 2>/dev/null || true
}

wait_pod_ready() {
  # entre um crash e o próximo, espera o container voltar (o backoff cresce: 10s,20s,40s...)
  for _ in $(seq 1 40); do
    phase="$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
    [ "$phase" = "true" ] && return 0
    sleep 3
  done
}

for i in $(seq 1 "$CRASHES"); do
  echo "-- [$( ts )] crash $i/$CRASHES no pod $POD"
  crash_once
  sleep 4
  wait_pod_ready
  restarts="$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo '?')"
  echo "   restartCount atual do pod: $restarts"
done

echo ""
echo "== [$( ts )] Caos concluído - a partir daqui é o self-healing que age =="
kubectl -n "$NAMESPACE" get pods -l app="$DEPLOYMENT" -o wide
echo ""
echo "== Onde olhar para a evidência (gravar no vídeo) =="
echo "  Prometheus:   ALERTS{alertname=\"DonationServiceCrashLooping\"}  -> pending depois firing"
echo "                increase(kube_pod_container_status_restarts_total{namespace=\"$NAMESPACE\",pod=~\"donation-service-.*\"}[10m])"
echo "  Alertmanager: alerta DonationServiceCrashLooping -> firing -> (resolve após o healer agir)"
echo "  Grafana:      dashboard 'SolidaryTech - Visão Geral', painel de restarts / healer_actions_total"
echo "  Healer:       kubectl -n $NAMESPACE logs deploy/healer-service -f --since=15m"
echo "  Métrica:      healer_actions_total{deployment=\"donation-service\",result=\"restarted\"}"
echo ""
echo "  MTTR = (horário do 1º crash acima)  ->  (horário do rollout restart no log do healer)"

#!/usr/bin/env bash
# Teste de caos deliberado para gravar a evidência de self-healing/MTTR do relatório de SRE
# (docs/SRE-SLI-SLO-SLA.md).
#
# Como a imagem do donation-service é distroless (sem shell/sem `kubectl exec`), o jeito
# limpo de provocar crash-loop real (restart DENTRO do mesmo pod, não recriação de pod) é
# quebrar temporariamente a liveness probe: aponta para um path inexistente e acelera o
# threshold, o kubelet mata e reinicia o container repetidas vezes -> incrementa
# kube_pod_container_status_restarts_total -> dispara DonationServiceCrashLooping.
#
# O script reverte a probe automaticamente ao final; a partir daí, o próprio Kubernetes
# (kubelet) já mantém o container saudável — o `healer-service` entra no fluxo assim que o
# Alertmanager processa o alerta (latência normal de scrape+avaliação, não instantânea).
#
# Pré-requisito: kubeconfig apontando para o cluster (aws eks update-kubeconfig).
# NUNCA rode isso fora de um ambiente de demonstração/hackathon.
set -euo pipefail

NAMESPACE="${NAMESPACE:-solidarytech}"
DEPLOYMENT="donation-service"
CHAOS_DURATION_SECONDS="${CHAOS_DURATION_SECONDS:-90}"

echo "== Estado ANTES do caos =="
date -u +"%Y-%m-%dT%H:%M:%SZ"
kubectl -n "$NAMESPACE" get pods -l app="$DEPLOYMENT" -o wide

echo ""
echo "== Quebrando a liveness probe (path inexistente + threshold agressivo) =="
kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT" --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/__chaos_liveness_fail__"},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/periodSeconds","value":5},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":1}
]'

echo "Aguardando ${CHAOS_DURATION_SECONDS}s para os restarts se acumularem..."
echo "(acompanhe em outro terminal: watch kubectl -n $NAMESPACE get pods -l app=$DEPLOYMENT)"
sleep "$CHAOS_DURATION_SECONDS"

echo ""
echo "== Revertendo a liveness probe para o estado saudável =="
kubectl -n "$NAMESPACE" patch deployment "$DEPLOYMENT" --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/health"},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/periodSeconds","value":20},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":3}
]'

echo ""
echo "== Estado DEPOIS do caos =="
kubectl -n "$NAMESPACE" get pods -l app="$DEPLOYMENT" -o wide

echo ""
echo "== Onde olhar para a evidência (gravar no vídeo) =="
echo "  Prometheus: increase(kube_pod_container_status_restarts_total{pod=~\"donation-service-.*\"}[10m])"
echo "  Alertmanager UI: alerta DonationServiceCrashLooping -> firing -> resolved"
echo "  Grafana: painel 'Restarts do donation-service (proxy de MTTR / auto-healing)'"
echo "  Logs do healer: kubectl -n $NAMESPACE logs deploy/healer-service -f"
echo "  Métrica do healer: healer_actions_total{deployment=\"donation-service\"}"

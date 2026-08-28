#!/usr/bin/env bash
# Um único crash do donation-service, para a demonstração de self-healing PASSO A PASSO
# (roteiro do vídeo 2.5). Diferente do chaos-crash-donation-service.sh (que faz a bateria
# inteira sozinho), este roda 1 crash por vez e mostra o antes/depois — dá pra narrar cada
# quebra na câmera.
#
# Uso: rode 4-5 vezes seguidas, esperando o pod voltar entre uma e outra:
#   bash scripts/crash-once.sh
#   bash scripts/crash-once.sh
#   ...
#
# Pré: kubeconfig no cluster + donation-service com CHAOS_ENDPOINTS_ENABLED=true.
set -euo pipefail
NAMESPACE="${NAMESPACE:-solidarytech}"
LOCAL_PORT="${LOCAL_PORT:-18082}"

# fixa o mesmo pod entre execuções (o mais antigo do ReplicaSet atual)
POD="$(kubectl -n "$NAMESPACE" get pods -l app=donation-service \
  --field-selector=status.phase=Running \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[0].metadata.name}')"

r0="$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
echo "pod alvo : $POD"
echo "restarts : $r0  (antes)"

kubectl -n "$NAMESPACE" port-forward "pod/$POD" "$LOCAL_PORT:8082" >/dev/null 2>&1 &
pf=$!
for _ in $(seq 1 20); do curl -sf -o /dev/null "http://localhost:$LOCAL_PORT/live" && break || sleep 0.5; done
echo -n "crash    : "; curl -s -m 3 -X POST "http://localhost:$LOCAL_PORT/debug/crash"; echo
kill "$pf" 2>/dev/null || true

echo -n "aguardando o container reiniciar"
for _ in $(seq 1 60); do
  ready="$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo false)"
  rc="$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "$r0")"
  [ "$rc" != "$r0" ] && [ "$ready" = "true" ] && break
  echo -n "."; sleep 2
done
echo
kubectl -n "$NAMESPACE" get pod "$POD"
echo "restarts : $(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')  (depois)"
echo
echo "-> repita até restarts > 3. Aí acompanhe:"
echo "   Prometheus /alerts : DonationServiceCrashLooping  (inactive -> pending -> firing)"
echo "   healer             : kubectl -n $NAMESPACE logs deploy/healer-service -f --since=2m"

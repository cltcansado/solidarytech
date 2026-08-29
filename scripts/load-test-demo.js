// k6 - perfil CURTO, feito para a gravação do vídeo (o load-test-donation-service.js completo
// dura ~10 min; este dura 2-6 min conforme o MODE).
//
//   MODE=baseline (padrão)  ~2 min  -> só tráfego válido. Alimenta as Golden Metrics / SLO
//                                      do dashboard SRE sem disparar alerta.
//   MODE=errors             ~6 min  -> injeta ERROR_PCT% de requisições com o header
//                                      `X-Chaos: error-500` (donation-service responde 500
//                                      quando CHAOS_ENDPOINTS_ENABLED=true). A taxa de erro
//                                      5xx passa de 5% e dispara DonationServiceHighErrorRate
//                                      (for: 2m) -> healer-service faz rollout restart.
//
// Uso:
//   k6 run -e BASE_URL=http://<elb-donation>:8082 scripts/load-test-demo.js
//   k6 run -e BASE_URL=http://<elb-donation>:8082 -e MODE=errors scripts/load-test-demo.js
import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8082";
const MODE = __ENV.MODE || "baseline";
const ERROR_PCT = Number(__ENV.ERROR_PCT || 15); // % de requisições que forçam 500 (MODE=errors)

const PROFILES = {
  baseline: [
    { duration: "30s", target: 20 },
    { duration: "60s", target: 20 },
    { duration: "30s", target: 0 },
  ],
  errors: [
    { duration: "30s", target: 15 },
    { duration: "5m", target: 15 }, // sustentado > for:2m + tempo da média móvel de 5m subir
    { duration: "30s", target: 0 },
  ],
};

export const options = {
  scenarios: {
    demo: { executor: "ramping-vus", startVUs: 1, stages: PROFILES[MODE] || PROFILES.baseline },
  },
  thresholds: {
    // No MODE=errors o threshold de falha VAI estourar de propósito - é o ponto da demo.
    http_req_duration: ["p(95)<300"],
  },
};

export default function () {
  const forceError = MODE === "errors" && Math.random() * 100 < ERROR_PCT;

  const payload = JSON.stringify({
    ngo_id: Math.ceil(Math.random() * 2),
    amount: Number((Math.random() * 500 + 10).toFixed(2)),
    donor_name: `Doador demo ${__VU}-${__ITER}`,
  });

  const headers = { "Content-Type": "application/json" };
  if (forceError) headers["X-Chaos"] = "error-500";

  const res = http.post(`${BASE_URL}/donations`, payload, { headers });

  check(res, {
    "201 (ou 500 esperado no modo errors)": (r) =>
      r.status === 201 || (forceError && r.status === 500),
  });

  sleep(Math.random() * 1.2 + 0.3);
}

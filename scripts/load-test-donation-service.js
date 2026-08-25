// k6 (https://k6.io) — gera tráfego real no donation-service para:
//  1) alimentar as Golden Metrics com dados reais (não sintéticos) para o Dashboard SRE;
//  2) treinar a linha de base do AIOps/Watchdog (Etapa E11 — precisa de tráfego real e tempo
//     rodando para aprender o comportamento "normal" antes de detectar anomalia);
//  3) gerar dado real de CPU/Mem para o exercício de Rightsizing (Etapa E13).
//
// Uso local:
//   k6 run -e BASE_URL=http://localhost:8082 scripts/load-test-donation-service.js
// Uso contra o cluster (via port-forward ou Ingress):
//   k6 run -e BASE_URL=https://donation.solidarytech.exemplo.com scripts/load-test-donation-service.js
import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8082";

export const options = {
  scenarios: {
    trafego_normal: {
      executor: "ramping-vus",
      startVUs: 1,
      stages: [
        { duration: "1m", target: 10 },
        { duration: "5m", target: 10 },
        { duration: "1m", target: 0 },
      ],
    },
    // Pico imprevisível de acesso (citado no enunciado: "a plataforma ganhou destaque em
    // rede nacional") — dispara depois do tráfego normal já ter estabilizado a baseline.
    pico_viral: {
      executor: "ramping-vus",
      startVUs: 0,
      startTime: "7m",
      stages: [
        { duration: "30s", target: 80 },
        { duration: "2m", target: 80 },
        { duration: "30s", target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ["p(95)<300"], // mesmo SLO documentado em docs/SRE-SLI-SLO-SLA.md
    http_req_failed: ["rate<0.001"],
  },
};

export default function () {
  const payload = JSON.stringify({
    ngo_id: Math.ceil(Math.random() * 2),
    amount: (Math.random() * 500 + 10).toFixed(2),
    donor_name: `Doador k6 ${__VU}-${__ITER}`,
  });

  const res = http.post(`${BASE_URL}/donations`, payload, {
    headers: { "Content-Type": "application/json" },
  });

  check(res, {
    "status é 201": (r) => r.status === 201,
  });

  sleep(Math.random() * 1.5);
}

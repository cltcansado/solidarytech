# SRE - SLI, SLO e SLA do `donation-service`

> Seção obrigatória do Relatório de Entrega (PDF), item "Seção SRE". Escopo: `donation-service`,
> o Caminho Crítico (Hot Path) da SolidaryTech - é onde uma indisponibilidade tem impacto
> financeiro direto (doação não processada = doação perdida).

## 1. Golden Metrics usadas

Seguindo o modelo de Golden Signals (Google SRE Book): **Latência**, **Tráfego**, **Erros**
e **Saturação**. Definimos SLIs formais sobre os dois primeiros por serem os que mais afetam
diretamente a experiência do doador; Tráfego e Saturação são monitorados no dashboard mas não
viram SLI formal nesta entrega.

## 2. SLI 1 - Disponibilidade

- **Definição**: proporção de requisições HTTP em `POST /donations` e `GET /donations` que
  retornam status diferente de `5xx`, sobre o total de requisições, medida em janela de 5
  minutos e agregada em janela móvel de 30 dias.
- **Query (PromQL)**: `1 - donation_service:error_ratio:rate5m`
  (ver `solidarytech-gitops/observability/extras/slo-donation-service.yaml`)
- **Fonte do dado**: métrica `http_requests_total{path="/donations"}` exportada pelo próprio
  `donation-service` (Golden Metric implementada em `apps/donation-service/main.go`).

## 3. SLI 2 - Latência

- **Definição**: proporção de requisições em `/donations` respondidas em menos de 300ms,
  janela de 5 minutos / agregação de 30 dias.
- **Query (PromQL)**: `donation_service:requests_under_300ms:ratio5m`
- **Fonte do dado**: métrica `http_request_duration_seconds_bucket{path="/donations"}`
  (histograma Prometheus nativo, buckets padrão do `client_golang`).

## 4. SLOs (metas formais)

| SLI | SLO | Janela | Error Budget |
|---|---|---|---|
| Disponibilidade | **99.9%** das requisições sem erro 5xx | 30 dias móveis | ~43,2 min/mês de indisponibilidade tolerada |
| Latência | **99%** das requisições < 300ms | 30 dias móveis | 1% das requisições podem exceder 300ms |

**Justificativa dos números**: 99.9% (não 99.99%) foi escolhido porque a SolidaryTech é uma
ONG com orçamento de infraestrutura limitado (ver `docs/FINOPS-FORECAST.md`) - perseguir
99.99% exigiria Multi-AZ ativo em todos os componentes (RDS Multi-AZ, múltiplos NAT Gateways,
réplicas cross-AZ mínimas maiores), o que não se paga no estágio atual do produto. 300ms como
limiar de latência é o padrão de mercado para operações de escrita síncronas com um banco
relacional (INSERT + retorno do registro) em uma API REST simples.

## 5. SLA (compromisso formal com as ONGs parceiras)

Como o enunciado pede SLI/SLO/**SLA**, formalizamos o compromisso externo derivado dos SLOs
internos (o SLA é sempre um pouco mais frouxo que o SLO interno - dá margem de segurança
operacional antes de violar o compromisso contratual):

> **SLA SolidaryTech - donation-service**
> A SolidaryTech garante às ONGs parceiras **99.5% de disponibilidade mensal** do serviço de
> processamento de doações, medida como proporção de requisições sem erro 5xx.
> Em caso de violação, a SolidaryTech se compromete a: (1) publicar um post-mortem público em
> até 5 dias úteis (ver fluxo em `docs/ITSM-AIOPS.md`); (2) reportar o Error Budget consumido
> no relatório mensal de transparência da plataforma.
> Este SLA **não** cobre indisponibilidade decorrente de falha na região inteira da AWS acima
> do RTO definido no PCN (`docs/PCN-DR.md`) nem de eventos de força maior.

## 6. Dashboard SRE dedicado

Painel exclusivo em Grafana: `solidarytech-gitops/observability/extras/grafana-dashboard-sre-donation-service.yaml`
(dashboard `SRE - donation-service (SLO / Error Budget)`, importado automaticamente via
sidecar do kube-prometheus-stack). Contém: os 2 SLIs em tempo real, os 2 SLOs como texto,
gauge de Error Budget consumido (30d), séries de latência p95/tráfego/erro, e correlação de
restarts vs. ações do `healer-service` (evidência de MTTR - próxima seção).

## 7. MTTR - como a automação reduz o tempo de recuperação

### 7.1 Sem automação (cenário anterior, manual)

1. Alerta dispara → precisa de alguém de plantão olhar o alerta (latência humana: minutos a
   horas, dependendo do horário).
2. Engenheiro investiga logs/métricas manualmente.
3. Engenheiro decide reiniciar o serviço e roda `kubectl rollout restart` manualmente.
4. Serviço volta.

**MTTR estimado (manual, cenário realista de plantão): 15-30 minutos** (tempo dominado pela
etapa 1 - detecção humana e triagem, não pela correção em si, que leva segundos).

### 7.2 Com a automação implementada nesta entrega

1. `PrometheusRule` (`solidarytech-gitops/observability/extras/slo-donation-service.yaml`) avalia a cada
   30s e detecta `DonationServiceHighErrorRate` / `CrashLooping` (`for: 2m`) ou `HighLatency`
   (`for: 5m` - latência é mais ruidosa e tolera janela maior). O `for` evita reagir a um pico
   transitório sem virar espera excessiva no Hot Path.
2. Alertmanager despacha o alerta via `webhook_configs` para o `healer-service`
   (`apps/healer-service/app.py`) em segundos.
3. `healer-service` executa `rollout restart` do Deployment via API do Kubernetes
   imediatamente (respeitando um cooldown de 5min para evitar restart-storm).
4. Toda ação fica registrada na métrica `healer_actions_total` (correlacionável no dashboard
   com o pico de restarts) - dá rastreabilidade completa de quando o auto-healing agiu.

**MTTR estimado (automatizado): ~3-4 minutos**, dominado pela janela de confirmação do alerta
(`for: 2m` + ~1-1,5min para a métrica cruzar o limiar) - a ação de remediação em si leva
segundos. **Redução de MTTR de ~75-85%** frente ao cenário manual (15-30min), e sem depender de
haver alguém de plantão acordado.

> Evidência prática: `scripts/chaos-crash-donation-service.sh` provoca o cenário de
> CrashLoopBackOff sob demanda; o tempo entre o início do caos e o log
> `AUTO-HEALING: rollout restart disparado` no `healer-service` é o MTTR real medido e
> gravado no vídeo de demonstração.

## 8. Resiliência adicional do Hot Path (contexto para o Error Budget)

- **DLQ no SQS** (`infra/modules/sqs`): eventos de doação que falham ao publicar não são
  perdidos silenciosamente - vão para a Dead Letter Queue após 3 tentativas.
- **Retry com backoff exponencial** na publicação SQS (`apps/donation-service/main.go`,
  função `sendNotificationEventWithRetry`) - reduz falsos positivos de erro por instabilidade
  transitória de rede.
- **PodDisruptionBudget** (`solidarytech-gitops/apps/donation-service/pdb.yaml`, `minAvailable: 2`) - nunca
  menos de 2 réplicas de pé, nem durante rollout ou manutenção de nó.
- **HPA dedicado** (`solidarytech-gitops/apps/donation-service/hpa.yaml`) com `stabilizationWindowSeconds: 0`
  no scale-up - reage imediatamente a picos de acesso imprevisíveis (citados no enunciado).

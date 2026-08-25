# FinOps — Tagging, Rightsizing e Forecast de Custos

> Seção obrigatória do Relatório de Entrega (PDF), item "Seção FinOps". Todos os valores de
> custo abaixo são **estimativas baseadas na tabela pública de preços on-demand da AWS para
> `us-east-1`**. Depois do primeiro mês rodando, substituir esta seção pelos números reais do
> Cost Explorer.

## 1. Estratégia de Tagging (evidência em código)

Toda a infraestrutura é tagueada de 2 formas redundantes, ambas centralizadas em
`infra/modules/tags`:

1. **`default_tags` no provider AWS** (`infra/envs/production/versions.tf`) — aplica
   `Project=SolidaryTech`, `Environment=Production`, `CostCenter=NGO-Core`,
   `ManagedBy=Terraform` a **todo recurso criado pelo provider**, mesmo os que os módulos
   esqueçam de tagear explicitamente (rede de segurança contra "recurso órfão sem tag").
2. **Tag explícita `module.tags.tags`** passada a cada módulo (`vpc`, `eks`, `rds`, `sqs`,
   `dynamodb`, `redis`, `ecr`, `velero-backend`) — visível e auditável recurso a recurso.

Evidência a gravar no vídeo: `terraform plan` mostrando as tags em qualquer recurso novo, ou
o Console AWS > Resource Groups & Tag Editor filtrando por `CostCenter=NGO-Core`.

## 2. Rightsizing

### 2.1 Metodologia

1. Valores **iniciais** de `requests`/`limits` (ver tabela abaixo) foram definidos por
   estimativa de engenharia (perfil de app Flask/Go simples, sem histórico de produção).
2. Depois de rodar `scripts/load-test-donation-service.js` por tempo suficiente (Etapa E13),
   observar `container_cpu_usage_seconds_total` / `container_memory_working_set_bytes` no
   Prometheus (já coletado via `kube-state-metrics` + `cAdvisor`, sem custo/config extra).
3. Ajustar os manifestos em `solidarytech-gitops/apps/*/deployment.yaml` — **nunca manualmente no
   cluster**, sempre via commit + ArgoCD sync (GitOps).

### 2.2 Valores iniciais (requests/limits) por serviço

| Serviço | CPU request | CPU limit | Mem request | Mem limit | Réplicas | Justificativa |
|---|---|---|---|---|---|---|
| `donation-service` | 200m | 500m | 128Mi | 256Mi | 3 (min HPA) | Hot Path — mais CPU de folga para picos |
| `ngo-service` | 100m | 300m | 128Mi | 256Mi | 2 (min HPA) | CRUD simples, baixa carga esperada |
| `volunteer-service` | 100m | 300m | 128Mi | 256Mi | 2 (min HPA) | idem, porém com Scan no DynamoDB (mais I/O que CPU) |
| `healer-service` | 50m | 150m | 64Mi | 128Mi | 1 (sem HPA) | Controller reativo, não serve tráfego de usuário |

### 2.3 Node groups (rightsizing de infraestrutura, não só de Pod)

- **Node group ON_DEMAND** (`t3.medium` x2-4): hospeda `donation-service` — estabilidade
  prioritária sobre custo.
- **Node group SPOT** (`t3.medium`/`t3a.medium` x1-3, `PreferNoSchedule` taint): hospeda
  `ngo-service`, `volunteer-service`, `healer-service` e a stack de observabilidade —
  **~60-70% mais barato** que On-Demand para cargas que toleram interrupção eventual.

## 3. Forecast de custos mensais (estimativa)

Preços de referência on-demand `us-east-1` (não incluem Free Tier, que zeraria boa parte
disso no primeiro ano de conta nova — não considerado aqui para ser conservador):

| Recurso | Configuração | Estimativa mensal (USD) |
|---|---|---|
| EKS control plane | 1 cluster | $73,00 |
| EC2 — node group ON_DEMAND | 2x `t3.medium` (~730h/mês cada) | ~$60,74 |
| EC2 — node group SPOT | 1-3x `t3.medium`/`t3a.medium`, média 2 ativos | ~$18,00 (Spot ≈ 30% do On-Demand) |
| NAT Gateway | 1x (single NAT, decisão de custo) | ~$32,85 + processamento de dados |
| RDS PostgreSQL | 1x `db.t3.micro`, 20GB gp3, single-AZ | ~$13,00 |
| ElastiCache Redis | 1x `cache.t3.micro` | ~$12,00 |
| DynamoDB | On-demand, tráfego de hackathon | ~$1-3,00 |
| SQS | Standard, tráfego de hackathon | < $1,00 |
| ECR | 4 repositórios, lifecycle de 10 imagens | ~$1-2,00 |
| S3 (tfstate + Velero backups) | poucos GB, com lifecycle de 30 dias | ~$1-2,00 |
| CloudWatch Logs (EKS control plane) | api/audit/authenticator | ~$3-5,00 |
| **Total estimado** | | **~$215-225 USD/mês** |

> Fora de escopo do forecast: custo do APM (Datadog — plano de trial cobre o período do
> hackathon) e egress de rede além do free tier.

## 4. Recomendações práticas de otimização nativa de nuvem

1. **Spot para node group não-crítico** (já implementado, `infra/modules/eks`) — maior
   alavanca de custo disponível sem sacrificar o Hot Path.
2. **Single NAT Gateway** (já implementado, `infra/modules/vpc`, `var.single_nat_gateway`) —
   evita pagar 1 NAT por AZ (~$32,85/mês cada) num ambiente de estudo/hackathon; trocar para
   1 NAT por AZ é a primeira coisa a reverter se isto virar produção real (trade-off:
   disponibilidade de rede vs. custo).
3. **RDS single-AZ com `db.t3.micro`** — Multi-AZ dobraria o custo do RDS; adiado até haver
   tráfego real que justifique (ver SLO de 99.9%, não 99.99%, em `docs/SRE-SLI-SLO-SLA.md`).
4. **DynamoDB e SQS on-demand/pay-per-request** — sem capacidade provisionada ociosa, cobra só
   pelo uso real; reavaliar para capacidade provisionada só se o padrão de tráfego virar
   previsível (economia adicional de até ~40% em altíssimo volume constante, não é o caso
   aqui).
5. **Lifecycle policy no ECR** (`infra/modules/ecr`, mantém só as 10 imagens mais recentes por
   serviço) — evita crescimento indefinido do custo de storage do ECR.
6. **Próximo passo recomendado (não implementado ainda)**: **Savings Plan de Compute** de 1
   ano, no-upfront, cobrindo o baseline do node group ON_DEMAND — só faz sentido depois de
   ter ~1-2 meses de uso real medido (Savings Plan é aposta em baseline estável; comprar cedo
   demais, sem dado, é o oposto de FinOps).

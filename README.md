# SolidaryTech

Plataforma de doações da SolidaryTech: `ngo-service`, `donation-service` (hot path) e
`volunteer-service`, construída sobre o [código-base fornecido](https://github.com/dougls/hackathon-DCLT),
com fundação de infraestrutura própria (Kubernetes/EKS, Terraform, CI/CD, GitOps,
observabilidade e self-healing).

O desired state do cluster (ArgoCD, manifests, observabilidade, Velero) vive em repositório
separado: [`solidarytech-gitops`](https://github.com/cltcansado/solidarytech-gitops).

## Stack

| Camada | Detalhe |
|---|---|
| Docker/K8s | imagens distroless, requests/limits, HPA, PDB |
| Terraform (IaC) | VPC/EKS/RDS/SQS/DynamoDB/Redis/ECR/ArgoCD/Velero |
| CI/CD | pipelines por serviço (testes, Trivy, Sonar, build, push, bump no repo gitops) |
| GitOps | ArgoCD app-of-apps no repo `solidarytech-gitops` |
| Observabilidade/APM | Prometheus, Grafana, Loki, OTel Collector, Datadog |
| Self-healing | `healer-service` - remediação automática via webhook do Alertmanager |

Documentação de arquitetura e das frentes de SRE/FinOps/ITSM-AIOps/DR fica em `docs/`.

## Rodando localmente (sem AWS)

```bash
docker compose up --build
```

## Deploy em AWS

```bash
cd infra/bootstrap && terraform init && terraform apply   # uma vez, cria o backend do state
cd ../envs/production
cp terraform.tfvars.example terraform.tfvars              # preencher com os valores da conta
terraform init && terraform apply
```

## Estrutura

```text
apps/          código-fonte dos serviços (ngo, donation, volunteer, healer)
infra/         Terraform (bootstrap do backend + módulos + ambiente production)
.github/       pipelines de CI/CD
scripts/       carga (k6), teste de caos, ambiente local
docs/          arquitetura, SRE (SLI/SLO/SLA), FinOps, ITSM/AIOps, PCN/DR
docker-compose.yml
```

## Correções feitas no código-base original

- `volunteer-service/app.py` usava `boto3.dynamodb.conditions.Attr` sem importar o submódulo
  - quebrava em runtime no `GET /volunteers/<ngo_id>`. Corrigido, com teste de regressão em
  `apps/volunteer-service/tests/`.
- DLQ no SQS + retry com backoff na publicação de eventos do `donation-service` (o código-base
  original era fire-and-forget, sem tratamento de falha).

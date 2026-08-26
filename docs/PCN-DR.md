# Plano de Continuidade de Negócios (PCN) - SolidaryTech

> Documento executivo. Seção obrigatória do Relatório de Entrega (PDF), item "Seção
> Segurança e DR". Escrito para a diretoria da SolidaryTech (ONG), não para engenheiros.

## 1. Objetivo

Garantir que, em caso de indisponibilidade da região AWS principal (`us-east-1`) - falha de
datacenter, incidente de rede da AWS, corrupção de dados - **as doações processadas não sejam
perdidas** e a plataforma volte ao ar dentro de um prazo definido e aceitável para o negócio.

## 2. RTO e RPO - valores críticos para os dados de doações

| Métrica | Definição | Valor definido | Justificativa |
|---|---|---|---|
| **RPO** (Recovery Point Objective) | Quanto de dado a SolidaryTech aceita perder, medido em tempo | **24 horas** | Backup diário do Velero (`schedule: "0 3 * * *"`, ver `solidarytech-gitops/velero/velero-values.yaml`). Doações em si já estão persistidas de forma durável no RDS (não dependem só do backup do Velero - ver seção 4) |
| **RTO** (Recovery Time Objective) | Quanto tempo até o serviço voltar ao ar após o desastre | **4 horas** | Tempo estimado para: provisionar novo cluster via Terraform (~20-30min) + restaurar manifests/config via Velero (~15min) + apontar RDS/DynamoDB (dados já duráveis, não precisam de restore na Opção A) + validar smoke test |

**Por que RPO de 24h é aceitável**: os dados financeiros críticos (tabela `donations` no RDS,
tabela `SolidaryTechVolunteers` no DynamoDB) **não dependem do backup do Velero** para
sobreviver a uma falha de cluster Kubernetes - eles vivem em serviços gerenciados da AWS
(RDS, DynamoDB) com sua própria durabilidade (backup automático do RDS + point-in-time
recovery do DynamoDB, ambos habilitados em `infra/modules/rds` e `infra/modules/dynamodb`).
O Velero cobre o **estado do cluster** (manifests, configuração, volumes de
Prometheus/Grafana/Loki) - perder até 24h desse estado é operacionalmente inconveniente, mas
não é perda de doação.

## 3. Estratégia de DR escolhida: Opção A - Velero (Cross-Region Backup)

**Decisão**: Opção A (Velero), não Opção B (infraestrutura ativo-passivo multi-região).

**Justificativa executiva**:
- Custo: Opção B exigiria manter recursos (ao menos o cluster warm standby) ativos 24/7 em
  uma segunda região - dobra parte do custo de infraestrutura (ver `docs/FINOPS-FORECAST.md`)
  para um cenário de baixíssima probabilidade (falha de região inteira da AWS).
- Os dados mais críticos (doações) já residem em serviços gerenciados regionalmente
  duráveis - o ganho marginal de um ambiente ativo-passivo completo não compensa o custo
  extra no estágio atual do produto (ONG, orçamento limitado).
- Reversibilidade: a arquitetura Terraform já é modular (`infra/modules/`) - nada impede
  evoluir para a Opção B no futuro, reaplicando os mesmos módulos em `us-west-2` (o bucket de
  backup do Velero já está provisionado lá, ver `infra/modules/velero-backend`).

## 4. Como funciona na prática

1. **Dados transacionais** (RDS Postgres, DynamoDB): sobrevivem à perda do cluster
   Kubernetes por definição - são serviços gerenciados fora do cluster. RDS com backup
   automático de 7 dias de retenção (`infra/modules/rds`); DynamoDB com Point-in-Time
   Recovery habilitado (`infra/modules/dynamodb`).
2. **Estado do cluster** (manifests aplicados, ConfigMaps, Secrets, volumes de
   observabilidade): backup diário via Velero para o bucket `solidarytech-velero-backups-*`
   em `us-west-2` - **cross-region por definição**, sobrevive à perda da região inteira de
   `us-east-1` (`infra/modules/velero-backend`, `provider aws.dr`).
3. **Em caso de desastre**: provisionar um novo cluster EKS via `terraform apply`
   (infraestrutura já é 100% código, ver `infra/`), instalar o Velero apontando para o mesmo
   bucket de backup, rodar `velero restore create --from-backup <ultimo-backup>` para trazer
   de volta o estado do cluster, reconectar aos mesmos RDS/DynamoDB (que nunca caíram).

## 5. Evidência prática (a gravar no vídeo de demonstração)

- `velero backup get` mostrando os backups agendados rodando.
- `velero backup describe <nome> --details` mostrando os recursos incluídos.
- Um `velero restore create --from-backup <nome> --namespace-mappings solidarytech:solidarytech-restore-test`
  ao vivo, restaurando num namespace de teste - prova que o backup é restaurável de verdade,
  não só "existe".
- Console S3 (ou `aws s3 ls`) mostrando o bucket em `us-west-2` com os arquivos de backup.

## 6. Comunicação em caso de ativação do PCN

Ver fluxo completo em `docs/ITSM-AIOPS.md` - a ativação do PCN segue o mesmo processo formal
de gestão de incidente (Detecção → Triagem → Resposta → Resolução → Post-Mortem →
Comunicação a stakeholders), com a diferença de que a "Resposta" aqui é o procedimento de
restore descrito na seção 4, não um `rollout restart` automático.

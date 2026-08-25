# Fila principal + DLQ. O código-base original não tinha DLQ (fire-and-forget) — adicionada
# aqui como reforço de resiliência para o Hot Path (donation-service), citada em
# docs/SRE-SLI-SLO-SLA.md como parte da estratégia de confiabilidade.

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = var.message_retention_seconds
  tags                      = var.tags
}

resource "aws_sqs_queue" "main" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = var.tags
}

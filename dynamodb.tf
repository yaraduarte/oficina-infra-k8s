# =============================================================================
# DynamoDB do billing-service (banco por serviço - ADR-007)
#   billing-quotes   : chave id, GSI osId-index
#   billing-payments : chave id, GSI quoteId-index
# Sufixo "-hml" para o namespace de homologação (oficina-hml).
# =============================================================================

locals {
  billing_table_suffixes = toset(["", "-hml"])
}

resource "aws_dynamodb_table" "billing_quotes" {
  for_each     = local.billing_table_suffixes
  name         = "billing-quotes${each.key}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "osId"
    type = "S"
  }

  global_secondary_index {
    name            = "osId-index"
    hash_key        = "osId"
    projection_type = "ALL"
  }

  tags = {
    Project     = "oficina-marimb0ndo"
    Service     = "billing-service"
    Environment = each.key == "" ? "prod" : "hml"
  }
}

resource "aws_dynamodb_table" "billing_payments" {
  for_each     = local.billing_table_suffixes
  name         = "billing-payments${each.key}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "quoteId"
    type = "S"
  }

  global_secondary_index {
    name            = "quoteId-index"
    hash_key        = "quoteId"
    projection_type = "ALL"
  }

  tags = {
    Project     = "oficina-marimb0ndo"
    Service     = "billing-service"
    Environment = each.key == "" ? "prod" : "hml"
  }
}

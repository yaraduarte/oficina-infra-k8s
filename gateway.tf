# =============================================================================
# API Gateway explícito (HTTP API) à frente de toda a aplicação
#
#   POST /auth                         -> Lambda oficina-auth            (pública)
#   POST /os/api/auth/login            -> os-service                     (pública: login de funcionário)
#   GET  /os/health                    -> os-service                     (pública)
#   ANY  /os/{proxy+}                  -> os-service        (k3s Ingress) [authorizer JWT]
#   POST /billing/webhooks/mercadopago -> billing-service                (pública, valida x-signature)
#   ANY  /billing/{proxy+}             -> billing-service   (k3s Ingress) [authorizer JWT]
#   ANY  /execucao/{proxy+}            -> execution-service (k3s Ingress) [authorizer JWT]
#
# O Gateway injeta x-origin-verify; os serviços recusam chamadas sem ele (acesso direto à EC2).
# Rotas /internal/* NÃO são publicadas aqui.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  name_suffix         = var.environment == "prod" ? "" : "-${var.environment}"
  auth_function_name  = "oficina-auth${local.name_suffix}"
  authz_function_name = "oficina-authorizer${local.name_suffix}"
  lambda_arn_prefix   = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function"
  auth_function_arn   = "${local.lambda_arn_prefix}:${local.auth_function_name}"
  authz_function_arn  = "${local.lambda_arn_prefix}:${local.authz_function_name}"
  ingress_base_url    = "http://${aws_eip.k3s.public_ip}"

  # Contexto do authorizer repassado aos serviços + header de origem
  upstream_headers = {
    "overwrite:header.x-origin-verify" = random_password.origin_verify.result
    "overwrite:header.x-user-sub"      = "$context.authorizer.sub"
    "overwrite:header.x-user-role"     = "$context.authorizer.role"
    "overwrite:header.x-user-type"     = "$context.authorizer.type"
  }
  public_upstream_headers = {
    "overwrite:header.x-origin-verify" = random_password.origin_verify.result
  }

  # serviço -> prefixo no Gateway e no Ingress do k3s
  services = {
    os       = "os"
    billing  = "billing"
    execucao = "execucao"
  }
}

# Segredo compartilhado Gateway -> serviços (nunca sai do Terraform/Kubernetes)
resource "random_password" "origin_verify" {
  length  = 48
  special = false
}

resource "aws_apigatewayv2_api" "oficina" {
  name          = "oficina-gateway${local.name_suffix}"
  protocol_type = "HTTP"
  description   = "API Gateway da Oficina Marimb0ndo - porta unica de entrada (Fase 4)"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }

  tags = {
    Project     = "oficina-marimb0ndo"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "gateway_access" {
  name              = "/aws/apigateway/oficina-gateway${local.name_suffix}"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.oficina.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.gateway_access.arn
    format = jsonencode({
      requestId    = "$context.requestId"
      ip           = "$context.identity.sourceIp"
      method       = "$context.httpMethod"
      route        = "$context.routeKey"
      status       = "$context.status"
      latencyMs    = "$context.responseLatency"
      authzError   = "$context.authorizer.error"
      userSub      = "$context.authorizer.sub"
      integrStatus = "$context.integrationStatus"
    })
  }
}

# ---------------------------------------------------------------------------
# Authorizer JWT (Lambda REQUEST, respostas simples) — código em oficina-lambda-auth
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id                            = aws_apigatewayv2_api.oficina.id
  name                              = "jwt-lambda-authorizer"
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${local.authz_function_arn}/invocations"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  authorizer_result_ttl_in_seconds  = 300
}

resource "aws_lambda_permission" "gateway_invoke_authorizer" {
  statement_id  = "AllowGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = local.authz_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.oficina.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.jwt.id}"
}

# ---------------------------------------------------------------------------
# POST /auth -> Lambda de autenticação (pública)
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "auth" {
  api_id                 = aws_apigatewayv2_api.oficina.id
  integration_type       = "AWS_PROXY"
  integration_uri        = local.auth_function_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_route" "auth" {
  api_id    = aws_apigatewayv2_api.oficina.id
  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

resource "aws_lambda_permission" "gateway_invoke_auth" {
  statement_id  = "AllowGatewayInvokeAuth"
  action        = "lambda:InvokeFunction"
  function_name = local.auth_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.oficina.execution_arn}/*/*/auth"
}

# ---------------------------------------------------------------------------
# Microsserviços no k3s (via Ingress Traefik na porta 80 da EC2)
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "service" {
  for_each = local.services

  api_id               = aws_apigatewayv2_api.oficina.id
  integration_type     = "HTTP_PROXY"
  integration_method   = "ANY"
  integration_uri      = "${local.ingress_base_url}/${each.value}/{proxy}"
  timeout_milliseconds = 29000
  request_parameters   = local.upstream_headers
}

resource "aws_apigatewayv2_route" "service" {
  for_each = local.services

  api_id             = aws_apigatewayv2_api.oficina.id
  route_key          = "ANY /${each.value}/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.service[each.key].id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

# Rotas públicas específicas (têm precedência sobre {proxy+})
locals {
  public_routes = {
    os_login        = { route = "POST /os/api/auth/login", path = "os/api/auth/login" }
    os_health       = { route = "GET /os/health", path = "os/health" }
    billing_webhook = { route = "POST /billing/webhooks/mercadopago", path = "billing/webhooks/mercadopago" }
    billing_health  = { route = "GET /billing/health", path = "billing/health" }
    execucao_health = { route = "GET /execucao/health", path = "execucao/health" }
  }
}

resource "aws_apigatewayv2_integration" "public" {
  for_each = local.public_routes

  api_id               = aws_apigatewayv2_api.oficina.id
  integration_type     = "HTTP_PROXY"
  integration_method   = split(" ", each.value.route)[0]
  integration_uri      = "${local.ingress_base_url}/${each.value.path}"
  timeout_milliseconds = 29000
  request_parameters   = local.public_upstream_headers
}

resource "aws_apigatewayv2_route" "public" {
  for_each = local.public_routes

  api_id    = aws_apigatewayv2_api.oficina.id
  route_key = each.value.route
  target    = "integrations/${aws_apigatewayv2_integration.public[each.key].id}"
}

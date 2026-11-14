# oficina-infra-k8s

Infraestrutura Kubernetes da **Oficina Marimbondo** — EC2 com k3s provisionada via Terraform na AWS.

## Tecnologias

- Terraform >= 1.5
- AWS EC2 t3.medium (Amazon Linux 2023)
- k3s (Kubernetes leve)
- HPA (Horizontal Pod Autoscaler)
- GitHub Actions (CI/CD)

## Arquitetura

```
Internet
   │  HTTPS
   ▼
API Gateway HTTP API  (gateway.tf)  ── authorizer JWT: Lambda oficina-authorizer
   │  injeta x-origin-verify + x-user-sub/role/type
   ├── POST /auth ─────────────────────────► Lambda oficina-auth
   ├── ANY  /os/{proxy+}        [JWT] ─┐
   ├── ANY  /billing/{proxy+}   [JWT] ─┼──► EC2 :80  Traefik Ingress (k3s)
   ├── ANY  /execucao/{proxy+}  [JWT] ─┘        ├── /os       → os-service
   └── públicas: POST /os/api/auth/login,       ├── /billing  → billing-service
       GET /*/health, POST /billing/webhooks/   └── /execucao → execution-service
       mercadopago

Terraform
   ├── aws_instance (EC2 t3.medium) + user_data.sh
   │     ├── k3s, namespace, ConfigMap, Secret
   │     ├── Deployment + Service (ClusterIP/NodePort interno) + HPA
   │     └── Ingress /os + Middleware strip-prefix
   ├── aws_security_group: 22 (SSH deploy), 80/443 (Ingress), 6443 só VPC
   ├── aws_apigatewayv2_* (API, stage com access logs, authorizer, rotas)
   ├── random_password.origin_verify (segredo Gateway → serviços)
   └── aws_eip
```

### API Gateway explícito (feedback da Fase 3)

- **Porta única de entrada:** NodePorts não ficam mais abertos no Security Group, e os serviços recusam com 403 requisições sem o header `x-origin-verify`, que só o Gateway conhece.
- **Authorizer JWT:** valida assinatura, `iss`, `aud`, `exp` e `status = ATIVO` (código e testes em `oficina-lambda-auth/src/authorizer.js`). O cache é de 5 minutos por token.
- **Access logs** no CloudWatch (`/aws/apigateway/oficina-gateway`), com rota, status, latência e erro do authorizer.
- **Throttling:** 50 req/s, com burst de 100.
- Rotas `/internal/*` não são publicadas no Gateway. A Lambda de auth as chama pelo Ingress usando `x-internal-api-key`.

**Ordem de deploy:** as funções `oficina-auth` e `oficina-authorizer` (stack SAM do `oficina-lambda-auth`) precisam existir antes do `terraform apply`, por causa das permissões `aws_lambda_permission`.

## Pré-requisitos

- AWS CLI configurado
- Terraform >= 1.5
- Par de chaves SSH gerado

## Como executar localmente

```bash
# Gerar par de chaves SSH
ssh-keygen -t rsa -b 4096 -f oficina-k3s-key

terraform init
terraform plan \
  -var="db_host=SEU_RDS_HOST" \
  -var="db_password=SUA_SENHA" \
  -var="jwt_secret=SEU_JWT_SECRET"
terraform apply -auto-approve ...
```

## CI/CD

Pipeline em `.github/workflows/deploy.yml`: todo PR e push roda `terraform fmt -check`, `validate` e `plan` (resumo do plano publicado no job).

### Fluxo de branches e ambientes

```
feature/*  ──PR──►  homolog  ──PR──►  main
                      │                 │
                      ▼                 ▼
   plan (revisão das mudanças)    terraform apply (produção)
```

- `main` e `homolog` são **protegidas**: push direto bloqueado (inclusive para admin), merge só via Pull Request com os checks obrigatórios verdes e conversas resolvidas.
- Todo PR roda o pipeline de validação; o deploy acontece apenas após o merge.

A infraestrutura física (EC2 + k3s) é compartilhada: a homologação da aplicação roda isolada no namespace `oficina-hml` do mesmo cluster.

### Secrets necessários

| Secret | Descrição |
|--------|-----------|
| `AWS_ACCESS_KEY_ID` | Access key da AWS |
| `AWS_SECRET_ACCESS_KEY` | Secret key da AWS |
| `DB_HOST` | Endpoint do RDS |
| `DB_PASSWORD` | Senha do banco |
| `JWT_SECRET` | Chave JWT |
| `K3S_SSH_PUBLIC_KEY` | Chave pública SSH |
| `INTERNAL_API_KEY` | Chave das rotas `/internal/*` do os-service (mesmo valor do secret no `oficina-lambda-auth`) |

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
GitHub Actions
     │
     ▼
Terraform
     │
     ├── aws_instance (EC2 t3.medium)
     │     └── user_data.sh
     │           ├── instala k3s
     │           ├── cria namespace oficina-marimb0ndo
     │           ├── aplica ConfigMap + Secret
     │           ├── Deployment (2 réplicas)
     │           ├── Service NodePort :30080
     │           └── HPA (min:2 max:10 cpu:60%)
     ├── aws_security_group (22, 80, 443, 6443, 30080)
     ├── aws_key_pair
     └── aws_eip (IP elástico)
```

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

Push na `main` provisiona a infraestrutura automaticamente.

### Secrets necessários

| Secret | Descrição |
|--------|-----------|
| `AWS_ACCESS_KEY_ID` | Access key da AWS |
| `AWS_SECRET_ACCESS_KEY` | Secret key da AWS |
| `DB_HOST` | Endpoint do RDS |
| `DB_PASSWORD` | Senha do banco |
| `JWT_SECRET` | Chave JWT |
| `K3S_SSH_PUBLIC_KEY` | Chave pública SSH |

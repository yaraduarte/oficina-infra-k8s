variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "prod"
}

variable "db_host" {
  description = "Host do RDS PostgreSQL"
  type        = string
}

variable "db_password" {
  description = "Senha do banco de dados"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "Chave secreta JWT"
  type        = string
  sensitive   = true
}

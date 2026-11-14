output "k3s_public_ip" {
  description = "IP público do nó k3s"
  value       = aws_eip.k3s.public_ip
}

output "k3s_api_url" {
  description = "URL da API do cluster k3s"
  value       = "https://${aws_eip.k3s.public_ip}:6443"
}

output "gateway_url" {
  description = "URL pública do API Gateway (única porta de entrada)"
  value       = aws_apigatewayv2_api.oficina.api_endpoint
}

output "auth_url" {
  description = "Endpoint de autenticação por CPF"
  value       = "${aws_apigatewayv2_api.oficina.api_endpoint}/auth"
}

output "os_service_url" {
  description = "Base do os-service via Gateway (ex.: /os/api/clients, /os/api-docs)"
  value       = "${aws_apigatewayv2_api.oficina.api_endpoint}/os"
}

output "os_service_internal_url" {
  description = "URL usada pela Lambda de auth para as rotas /internal/* (Ingress direto; rotas /internal/* exigem x-internal-api-key)"
  value       = "http://${aws_eip.k3s.public_ip}/os"
}

output "ssh_command" {
  description = "Comando SSH para acessar o nó"
  value       = "ssh -i oficina-k3s-key ec2-user@${aws_eip.k3s.public_ip}"
}

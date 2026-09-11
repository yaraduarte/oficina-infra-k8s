output "k3s_public_ip" {
  description = "IP público do nó k3s"
  value       = aws_eip.k3s.public_ip
}

output "k3s_api_url" {
  description = "URL da API do cluster k3s"
  value       = "https://${aws_eip.k3s.public_ip}:6443"
}

output "app_url" {
  description = "URL da aplicação"
  value       = "http://${aws_eip.k3s.public_ip}:30080"
}

output "ssh_command" {
  description = "Comando SSH para acessar o nó"
  value       = "ssh -i oficina-k3s-key ec2-user@${aws_eip.k3s.public_ip}"
}

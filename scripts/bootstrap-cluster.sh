#!/bin/bash
# Bootstrap idempotente do cluster k3s, executado na EC2 via SSH após cada terraform apply.
# Uso: bootstrap-cluster.sh <namespace> <diretorio-dos-manifestos>
#   - gera o Secret rabbitmq-credentials (uma única vez; senha aleatória)
#   - aplica o RabbitMQ (k8s/rabbitmq.yaml)
#   - injeta RABBITMQ_URL no deployment oficina-api (os-service) se ainda não houver
set -euo pipefail

NS="$1"
DIR="$2"
K="sudo kubectl"

# Numa EC2 recém-criada o user_data ainda pode estar instalando o k3s
for i in $(seq 1 60); do
  if $K get namespace "$NS" >/dev/null 2>&1; then break; fi
  echo "aguardando k3s e namespace $NS ($i/60)..."; sleep 10
done
$K get namespace "$NS" >/dev/null

if ! $K get secret rabbitmq-credentials -n "$NS" >/dev/null 2>&1; then
  PASS=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
  $K create secret generic rabbitmq-credentials -n "$NS" \
    --from-literal=user=oficina \
    --from-literal=password="$PASS" \
    --from-literal=url="amqp://oficina:${PASS}@rabbitmq.${NS}.svc.cluster.local:5672"
  echo "secret rabbitmq-credentials criado em $NS"
fi

sed -e "s|__NAMESPACE__|${NS}|g" "$DIR/rabbitmq.yaml" | $K apply -f -
$K rollout status deployment/rabbitmq -n "$NS" --timeout=300s

# os-service: o deployment é criado pelo user_data com env explícito; acrescenta RABBITMQ_URL
for i in $(seq 1 30); do
  if $K get deployment oficina-api -n "$NS" >/dev/null 2>&1; then break; fi
  echo "aguardando deployment oficina-api ($i/30)..."; sleep 10
done
if ! $K get deployment oficina-api -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' | tr ' ' '\n' | grep -qx RABBITMQ_URL; then
  $K patch deployment oficina-api -n "$NS" --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"RABBITMQ_URL","valueFrom":{"secretKeyRef":{"name":"rabbitmq-credentials","key":"url"}}}}]'
  $K rollout status deployment/oficina-api -n "$NS" --timeout=300s
  echo "RABBITMQ_URL injetada no oficina-api"
fi

echo "bootstrap do cluster concluído em $NS"

#!/bin/bash
set -e

# Instala k3s
curl -sfL https://get.k3s.io | sh -

# Aguarda k3s iniciar
sleep 30

# Cria namespace
kubectl create namespace oficina-marimb0ndo --dry-run=client -o yaml | kubectl apply -f -

# ConfigMap
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: oficina-config
  namespace: oficina-marimb0ndo
data:
  NODE_ENV: "production"
  PORT: "3000"
  DB_HOST: "${db_host}"
  DB_PORT: "5432"
  DB_NAME: "oficina_db"
  DB_USER: "oficina_admin"
  JWT_EXPIRES_IN: "24h"
  DB_SYNCHRONIZE: "true"
  SMTP_HOST: "smtp.ethereal.email"
  SMTP_PORT: "587"
  SMTP_FROM: "noreply@oficina.com"
EOF

# Secret
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oficina-secret
  namespace: oficina-marimb0ndo
type: Opaque
stringData:
  DB_PASS: "${db_password}"
  JWT_SECRET: "${jwt_secret}"
  INTERNAL_API_KEY: "${internal_api_key}"
  ORIGIN_VERIFY_SECRET: "${origin_verify_secret}"
  SMTP_USER: ""
  SMTP_PASS: ""
EOF

# Deployment da API
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oficina-api
  namespace: oficina-marimb0ndo
  labels:
    app: oficina-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: oficina-api
  template:
    metadata:
      labels:
        app: oficina-api
    spec:
      containers:
      - name: oficina-api
        image: yaraduarte/oficina-marimb0ndo-api:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 3000
        envFrom:
        - configMapRef:
            name: oficina-config
        env:
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: oficina-secret
              key: DB_PASS
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: oficina-secret
              key: JWT_SECRET
        - name: INTERNAL_API_KEY
          valueFrom:
            secretKeyRef:
              name: oficina-secret
              key: INTERNAL_API_KEY
        - name: ORIGIN_VERIFY_SECRET
          valueFrom:
            secretKeyRef:
              name: oficina-secret
              key: ORIGIN_VERIFY_SECRET
        resources:
          requests:
            memory: "128Mi"
            cpu: "250m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 15
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 30
EOF

# Service NodePort
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: oficina-api-service
  namespace: oficina-marimb0ndo
spec:
  type: NodePort
  selector:
    app: oficina-api
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30080
EOF

# HPA
kubectl apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: oficina-api-hpa
  namespace: oficina-marimb0ndo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: oficina-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
EOF

# Ingress (Traefik, porta 80): /os -> os-service. O prefixo é removido antes de chegar ao pod.
# billing-service e execution-service registram /billing e /execucao nos próprios manifestos.
kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-os
  namespace: oficina-marimb0ndo
spec:
  stripPrefix:
    prefixes:
      - /os
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: os-service
  namespace: oficina-marimb0ndo
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.middlewares: oficina-marimb0ndo-strip-os@kubernetescrd
spec:
  rules:
  - http:
      paths:
      - path: /os
        pathType: Prefix
        backend:
          service:
            name: oficina-api-service
            port:
              number: 80
EOF

echo "k3s setup completo!"

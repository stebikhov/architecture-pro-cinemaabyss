# CinemaAbyss Kubernetes Deployment

This directory contains Kubernetes manifests and Helm charts for deploying CinemaAbyss.

## Prerequisites

- Kubernetes cluster (v1.19+) or Minikube
- kubectl configured
- Helm (v3.2.0+)
- Docker registry access (GitHub Container Registry)

## GitHub Container Registry Setup

### Step 1: Create Personal Access Token (PAT)

1. Go to https://github.com/settings/tokens
2. Create a new token with `read:packages` scope
3. Save the token securely

### Step 2: Configure Docker Authentication

```bash
# Login to GitHub Container Registry
echo YOUR_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# Generate base64 encoded auth
echo -n 'YOUR_USERNAME:YOUR_TOKEN' | base64

# Generate base64 encoded docker config
cat ~/.docker/config.json | base64 -w 0
```

### Step 3: Update dockerconfigsecret.yaml

Replace the `.dockerconfigjson` value in `dockerconfigsecret.yaml` with your base64 encoded config.

## Deployment Steps

### Using kubectl (Manual Deployment)

```bash
# 1. Create namespace
kubectl apply -f namespace.yaml

# 2. Create secrets and config
kubectl apply -f dockerconfigsecret.yaml
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f postgres-init-configmap.yaml

# 3. Deploy database
kubectl apply -f postgres.yaml

# 4. Deploy Kafka
kubectl apply -f kafka/kafka.yaml

# 5. Deploy monolith
kubectl apply -f monolith.yaml

# 6. Deploy microservices
kubectl apply -f movies-service.yaml
kubectl apply -f events-service.yaml

# 7. Deploy proxy service
kubectl apply -f proxy-service.yaml

# 8. Enable ingress (Minikube)
minikube addons enable ingress

# 9. Deploy ingress
kubectl apply -f ingress.yaml

# 10. Add to /etc/hosts
# 127.0.0.1 cinemaabyss.example.com

# 11. Start minikube tunnel (in separate terminal)
minikube tunnel
```

### Using Helm

```bash
# 1. Update values.yaml with your container registry paths
# Edit: src/kubernetes/helm/values.yaml

# 2. Install the chart
helm install cinemaabyss ./src/kubernetes/helm \
  --namespace cinemaabyss \
  --create-namespace

# 3. Check deployment
kubectl get pods -n cinemaabyss

# 4. Uninstall
helm uninstall cinemaabyss -n cinemaabyss
kubectl delete namespace cinemaabyss
```

## Configuration

### Strangler Fig Migration

Control traffic routing via ConfigMap or environment variables:

```yaml
# In proxy-service deployment
GRADUAL_MIGRATION: "true"        # Enable gradual migration
MOVIES_MIGRATION_PERCENT: "50"   # 50% traffic to movies-service
```

### Circuit Breaker (Istio)

```bash
# Apply circuit breaker configuration
kubectl apply -f circuit-breaker-config.yaml

# Test with fortio
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.25/samples/httpbin/sample-client/fortio-deploy.yaml -n cinemaabyss

FORTIO_POD=$(kubectl get pod -n cinemaabyss | grep fortio | awk '{print $1}')
kubectl exec -n cinemaabyss $FORTIO_POD -c fortio -- fortio load -c 50 -qps 0 -n 500 -loglevel Warning http://movies-service:8081/api/movies
```

## Testing

### Run Postman Tests

```bash
cd tests/postman
npm install
npm run test:kubernetes
```

### Manual Testing

```bash
# Add to /etc/hosts
# 127.0.0.1 cinemaabyss.example.com

# Test API Gateway
curl https://cinemaabyss.example.com/api/movies

# Test events service
curl -X POST https://cinemaabyss.example.com/api/events/movie \
  -H "Content-Type: application/json" \
  -d '{"movie_id": 1, "title": "Test", "action": "viewed", "user_id": 1}'
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n cinemaabyss
kubectl describe pod <pod-name> -n cinemaabyss
kubectl logs <pod-name> -n cinemaabyss
```

### Kafka Issues

```bash
kubectl logs kafka-0 -n cinemaabyss
kubectl logs zookeeper-0 -n cinemaabyss
```

### Database Issues

```bash
kubectl logs postgres-0 -n cinemaabyss
kubectl exec -it postgres-0 -n cinemaabyss -- psql -U postgres -d cinemaabyss
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| proxy-service | 8000 | API Gateway |
| monolith | 8080 | Legacy monolith |
| movies-service | 8081 | Movies microservice |
| events-service | 8082 | Events/Kafka microservice |
| kafka | 9092 | Kafka broker |
| zookeeper | 2181 | Zookeeper |
| postgres | 5432 | PostgreSQL database |
| kafka-ui | 8090 | Kafka UI (port-forward) |

## Port Forwarding

```bash
# Kafka UI
kubectl port-forward svc/kafka-ui 8090:8080 -n cinemaabyss

# PostgreSQL
kubectl port-forward svc/postgres 5432:5432 -n cinemaabyss
```

#!/usr/bin/env pwsh
# CinemaAbyss Kubernetes Deployment Script for Kind
# Usage: .\deploy-kind.ps1

param(
    [switch]$Clean = $false,
    [switch]$SkipBuild = $false
)

$ErrorActionPreference = "Stop"
$KIND_CLUSTER_NAME = "cinemaabyss"
$NAMESPACE = "cinemaabyss"
$PROJECT_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$KIND_PATH = "$PROJECT_ROOT\bin\kind.exe"
$KUBECTL = "kubectl"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Green
}

function Write-Error-Exit {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Test-Command {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Check prerequisites
Write-Step "Checking prerequisites"

if (-not (Test-Command docker)) {
    Write-Error-Exit "Docker is not installed or not in PATH"
}

if (-not (Test-Command $KUBECTL)) {
    Write-Error-Exit "kubectl is not installed or not in PATH"
}

if (-not (Test-Path $KIND_PATH)) {
    Write-Host "Kind not found at $KIND_PATH, trying to use global kind..." -ForegroundColor Yellow
    $KIND_PATH = "kind"
    if (-not (Test-Command kind)) {
        Write-Error-Exit "Kind is not installed. Download from https://kind.sigs.k8s.io/"
    }
}

# Clean up existing cluster if requested
if ($Clean) {
    Write-Step "Cleaning up existing cluster"
    & $KIND_PATH delete cluster --name $KIND_CLUSTER_NAME 2>&1 | Out-Null
    Write-Host "Cluster deleted" -ForegroundColor Green
}

# Create Kind cluster
Write-Step "Creating Kind cluster '$KIND_CLUSTER_NAME'"
& $KIND_PATH create cluster --name $KIND_CLUSTER_NAME 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error-Exit "Failed to create Kind cluster"
}

Write-Host "Cluster created successfully" -ForegroundColor Green

# Verify cluster connection
Write-Step "Verifying cluster connection"
& $KUBECTL cluster-info --context "kind-$KIND_CLUSTER_NAME" 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error-Exit "Cannot connect to cluster"
}

Write-Host "Connected to cluster" -ForegroundColor Green

# Build and load Docker images
if (-not $SkipBuild) {
    Write-Step "Building Docker images"
    
    $images = @(
        @{ Context = "src/monolith"; Name = "monolith" },
        @{ Context = "src/microservices/movies"; Name = "movies-service" },
        @{ Context = "src/microservices/events"; Name = "events-service" },
        @{ Context = "src/microservices/proxy"; Name = "proxy-service" }
    )
    
    foreach ($image in $images) {
        Write-Host "Building $($image.Name)..." -ForegroundColor Yellow
        docker build -t "$($image.Name):local" "$PROJECT_ROOT/$($image.Context)" 2>&1 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Exit "Failed to build $($image.Name)"
        }
        
        Write-Host "Loading $($image.Name) into Kind..." -ForegroundColor Yellow
        & $KIND_PATH load docker-image "$($image.Name):local" --name $KIND_CLUSTER_NAME 2>&1 | Out-Null
    }
    
    Write-Host "All images built and loaded" -ForegroundColor Green
}

# Update image references in manifests for local deployment
Write-Step "Updating Kubernetes manifests for local deployment"

$manifests = @(
    @{ File = "monolith.yaml"; Image = "monolith:local" },
    @{ File = "movies-service.yaml"; Image = "movies-service:local" },
    @{ File = "events-service.yaml"; Image = "events-service:local" },
    @{ File = "proxy-service.yaml"; Image = "proxy-service:local" }
)

foreach ($manifest in $manifests) {
    $filePath = "$PROJECT_ROOT/src/kubernetes/$($manifest.File)"
    if (Test-Path $filePath) {
        $content = Get-Content $filePath -Raw
        # Replace ghcr.io images with local images
        $content = $content -replace 'image: ghcr\.io/[^`s]+', "image: $($manifest.Image)"
        Set-Content -Path $filePath -Value $content -NoNewline
        Write-Host "Updated $($manifest.File)" -ForegroundColor Yellow
    }
}

# Deploy to Kubernetes
Write-Step "Deploying to Kubernetes"

# 1. Create namespace
Write-Host "Creating namespace..." -ForegroundColor Yellow
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/namespace.yaml" 2>&1 | Out-Null

# 2. Create secrets and configs
Write-Host "Creating secrets and configs..." -ForegroundColor Yellow
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/dockerconfigsecret.yaml" --validate=false 2>&1 | Out-Null
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/secret.yaml" 2>&1 | Out-Null
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/configmap.yaml" 2>&1 | Out-Null
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/postgres-init-configmap.yaml" 2>&1 | Out-Null

# 3. Deploy database
Write-Host "Deploying database..." -ForegroundColor Yellow
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/postgres.yaml" 2>&1 | Out-Null

# 4. Deploy Kafka
Write-Host "Deploying Kafka..." -ForegroundColor Yellow
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/kafka/kafka.yaml" 2>&1 | Out-Null

# Wait for infrastructure
Write-Step "Waiting for infrastructure to be ready (this may take a few minutes)..."
Start-Sleep -Seconds 30

# 5. Deploy monolith
Write-Host "Deploying monolith..." -ForegroundColor Yellow
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/monolith.yaml" 2>&1 | Out-Null

# 6. Deploy microservices
Write-Host "Deploying microservices..." -ForegroundColor Yellow
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/movies-service.yaml" 2>&1 | Out-Null
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/events-service.yaml" 2>&1 | Out-Null

# 7. Deploy proxy service
Write-Host "Deploying proxy service..." -ForegroundColor Yellow
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/proxy-service.yaml" 2>&1 | Out-Null

# 8. Setup ingress (using NodePort for Kind)
Write-Step "Setting up ingress"

# Check if ingress is already installed
$ingressExists = & $KUBECTL get namespace ingress-nginx -o name 2>&1 | Out-Null
if (-not $ingressExists) {
    Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Yellow
    & $KUBECTL apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml 2>&1 | Out-Null
}

# Wait for ingress controller
Write-Host "Waiting for ingress controller..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

# 9. Deploy ingress
Write-Host "Deploying ingress..." -ForegroundColor Yellow
& $KUBECTL apply -f "$PROJECT_ROOT/src/kubernetes/ingress.yaml" 2>&1 | Out-Null

# Wait for deployments
Write-Step "Waiting for deployments to be ready..."
Start-Sleep -Seconds 30

# Check pod status
Write-Step "Checking deployment status"
& $KUBECTL get pods -n $NAMESPACE

# Check services
Write-Step "Checking services"
& $KUBECTL get svc -n $NAMESPACE

# Get ingress info
Write-Step "Checking ingress"
$ingress = & $KUBECTL get ingress -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>&1
if ($ingress) {
    Write-Host "Ingress IP: $ingress" -ForegroundColor Green
}

# Setup port-forward for easy access
Write-Step "Setting up port-forward"
Write-Host "To access the application, run the following in a separate terminal:" -ForegroundColor Yellow
Write-Host "kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80" -ForegroundColor Cyan
Write-Host ""
Write-Host "Then access:" -ForegroundColor Yellow
Write-Host "  API Gateway: http://localhost:8080/api/movies" -ForegroundColor Cyan
Write-Host "  Health Check: http://localhost:8080/health" -ForegroundColor Cyan
Write-Host ""

# Add hosts entry (requires admin)
Write-Host "Note: Add the following to C:\Windows\System32\drivers\etc\hosts (as Administrator):" -ForegroundColor Yellow
Write-Host "  127.0.0.1 cinemaabyss.example.com" -ForegroundColor Cyan

Write-Step "Deployment complete!"
Write-Host "Use 'kubectl get pods -n $NAMESPACE' to check status" -ForegroundColor Green
Write-Host "Use '$KIND_PATH delete cluster --name $KIND_CLUSTER_NAME' to clean up" -ForegroundColor Green

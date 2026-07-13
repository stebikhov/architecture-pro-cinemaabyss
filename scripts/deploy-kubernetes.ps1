param(
    [switch]$Clean = $false,
    [switch]$NoTunnel = $false
)

$ErrorActionPreference = "Stop"
$NAMESPACE = "cinemaabyss"
$HOST_ENTRY = "127.0.0.1 cinemaabyss.example.com"
$HOSTS_FILE = "$env:SystemRoot\System32\drivers\etc\hosts"

function Write-Step {
    param([string]$Message)
    Write-Host "`n===> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host ('  [OK] ' + $Message) -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function Test-Command {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Wait-Pods {
    param(
        [string]$Namespace,
        [int]$Timeout = 300,
        [string[]]$ExpectedPods = @()
    )
    $elapsed = 0
    $interval = 10
    Write-Host "  Waiting for pods to be ready (timeout: ${Timeout}s)..." -ForegroundColor Yellow
    
    while ($elapsed -lt $Timeout) {
        $allReady = $true
        foreach ($podName in $ExpectedPods) {
            $pod = kubectl get pod -n $Namespace -l app=$podName -o json 2>$null
            if ($null -eq $pod) {
                $allReady = $false
                break
            }
            $items = $pod | ConvertFrom-Json
            if ($items.items.Count -eq 0) {
                $allReady = $false
                break
            }
            foreach ($item in $items.items) {
                if ($item.status.phase -ne "Running") {
                    $allReady = $false
                    break
                }
            }
            if (-not $allReady) { break }
        }
        
        if ($allReady) {
            Write-Success "All pods are running"
            return $true
        }
        
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        Write-Host "  ... ${elapsed}s elapsed" -ForegroundColor Gray
    }
    
    Write-Fail "Timeout waiting for pods"
    return $false
}

Write-Step "Checking prerequisites"

$missing = @()
if (-not (Test-Command "docker")) { $missing += "Docker" }
if (-not (Test-Command "kubectl")) { $missing += "kubectl" }
if (-not (Test-Command "minikube")) { $missing += "minikube" }

if ($missing.Count -gt 0) {
    Write-Fail "Missing commands: $($missing -join ', ')"
    Write-Host "  Install Docker Desktop (includes kubectl) and minikube."
    exit 1
}

Write-Success "Docker, kubectl, minikube found"

if ($Clean) {
    Write-Step "Cleaning up existing cluster"
    kubectl delete all --all -n $NAMESPACE 2>$null
    kubectl delete namespace $NAMESPACE 2>$null
    Write-Success "Cleanup complete"
}

Write-Step "Starting minikube"
$running = minikube status 2>$null | Select-String "Running"
if (-not $running) {
    minikube start --memory=4096 --cpus=2
} else {
    Write-Success "Minikube already running"
}

Write-Step "Enabling ingress addon"
minikube addons enable ingress 2>$null
Write-Success "Ingress enabled"

Write-Step "Configuring hosts file"
$hostsContent = Get-Content $HOSTS_FILE -Raw
if ($hostsContent -notmatch [regex]::Escape("cinemaabyss.example.com")) {
    $adminRequired = $true
    try {
        $tempFile = [System.IO.Path]::GetTempFileName()
        $hostsContent += "`n$HOST_ENTRY`n"
        Set-Content -Path $tempFile -Value $hostsContent -Encoding UTF8 -NoNewline
        Copy-Item -Path $tempFile -Destination $HOSTS_FILE -Force
        Remove-Item -Path $tempFile -Force
        Write-Success "Hosts entry added: cinemaabyss.example.com"
    } catch {
        Write-Fail "Cannot write to hosts file. Run as Administrator or add manually:"
        Write-Host "  $HOST_ENTRY"
    }
} else {
    Write-Success "Hosts entry already exists"
}

Write-Step "Creating namespace"
kubectl apply -f src/kubernetes/namespace.yaml
Write-Success "Namespace $NAMESPACE created"

Write-Step "Applying configmaps and secrets"
kubectl apply -f src/kubernetes/configmap.yaml
kubectl apply -f src/kubernetes/secret.yaml
kubectl apply -f src/kubernetes/dockerconfigsecret.yaml
kubectl apply -f src/kubernetes/postgres-init-configmap.yaml
Write-Success "ConfigMaps and secrets applied"

Write-Step "Deploying PostgreSQL"
kubectl apply -f src/kubernetes/postgres.yaml
Write-Success "PostgreSQL deployed"
Start-Sleep -Seconds 15

Write-Step "Deploying Kafka"
kubectl apply -f src/kubernetes/kafka/kafka.yaml
Write-Success "Kafka deployed"
Start-Sleep -Seconds 20

Write-Step "Deploying monolith"
kubectl apply -f src/kubernetes/monolith.yaml
Write-Success "Monolith deployed"

Write-Step "Deploying microservices"
kubectl apply -f src/kubernetes/movies-service.yaml
kubectl apply -f src/kubernetes/events-service.yaml
Write-Success "Microservices deployed"

Write-Step "Deploying proxy service"
kubectl apply -f src/kubernetes/proxy-service.yaml
Write-Success "Proxy service deployed"

Write-Step "Deploying ingress"
kubectl apply -f src/kubernetes/ingress.yaml
Write-Success "Ingress deployed"

Write-Step "Waiting for pods to be ready"
$ready = Wait-Pods -Namespace $NAMESPACE -Timeout 180 -ExpectedPods @("monolith", "movies-service", "events-service", "proxy-service")

if (-not $ready) {
    Write-Fail "Some pods failed to start. Check with: kubectl get pods -n $NAMESPACE"
    Write-Host "`nTo see logs:"
    Write-Host '  kubectl logs -n $NAMESPACE <pod-name>'
}

Write-Step "Cluster status"
kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE

if (-not $NoTunnel) {
    Write-Step "Starting minikube tunnel"
    Write-Host "  Starting tunnel in background... Press Ctrl+C to stop."
    Write-Host "  The tunnel must remain running for tests to work."
    Start-Process -FilePath "minikube" -ArgumentList "tunnel" -WindowStyle Normal
}

Write-Host "`n" -NoNewline
Write-Success ('Deployment complete!')
Write-Host '  To run tests:'
Write-Host '    cd tests/postman'
Write-Host '    npm run test:kubernetes'
Write-Host '  To clean up:'
Write-Host ('    kubectl delete all --all -n ' + $NAMESPACE)
Write-Host ('    kubectl delete namespace ' + $NAMESPACE)

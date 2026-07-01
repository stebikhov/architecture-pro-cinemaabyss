param(
    [switch]$Clean = $false
)

$ErrorActionPreference = "Stop"

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

Write-Step "Checking prerequisites"

$missing = @()
if (-not (Test-Command "docker")) { $missing += "Docker" }
if (-not (Test-Command "docker-compose")) { $missing += "docker-compose" }
if (-not (Test-Command "npm")) { $missing += "npm" }

if ($missing.Count -gt 0) {
    Write-Fail "Missing commands: $($missing -join ', ')"
    Write-Host "  Install Docker Desktop (includes docker-compose) and Node.js."
    exit 1
}

Write-Success "Docker, docker-compose, npm found"

if ($Clean) {
    Write-Step "Cleaning up existing containers"
    docker-compose down -v 2>$null
    Write-Success "Cleanup complete"
}

Write-Step "Building and starting services"
docker-compose up -d --build

Write-Step "Waiting for services to be ready"
Start-Sleep -Seconds 30

Write-Step "Checking service health"
$services = @("monolith", "movies-service", "events-service", "proxy-service")
$allHealthy = $true

foreach ($svc in $services) {
    $containers = docker compose ps --services 2>$null | Where-Object { $_ -eq $svc }
    if ($containers) {
        Write-Success "$svc is running"
    } else {
        Write-Fail "$svc is not running"
        $allHealthy = $false
    }
}

if (-not $allHealthy) {
    Write-Host "`nTo see logs:"
    Write-Host "  docker-compose logs <service-name>"
    exit 1
}

Write-Success "All services are running!"
Write-Host '  To run tests:'
Write-Host '    cd tests/postman'
Write-Host '    npm install'
Write-Host '    npm run test:docker'
Write-Host '  To clean up:'
Write-Host '    docker-compose down -v'

#!/usr/bin/env pwsh
# Cleanup script for Kind cluster
# Usage: .\cleanup-kind.ps1

$KIND_CLUSTER_NAME = "cinemaabyss"
$KIND_PATH = ".\bin\kind.exe"

Write-Host "Cleaning up Kind cluster '$KIND_CLUSTER_NAME'..." -ForegroundColor Yellow

if (Test-Path $KIND_PATH) {
    & $KIND_PATH delete cluster --name $KIND_CLUSTER_NAME 2>&1 | Out-Null
    Write-Host "Cluster deleted" -ForegroundColor Green
} else {
    Write-Host "Kind not found at $KIND_PATH, trying global kind..." -ForegroundColor Yellow
    kind delete cluster --name $KIND_CLUSTER_NAME 2>&1 | Out-Null
    Write-Host "Cluster deleted" -ForegroundColor Green
}

Write-Host "Cleanup complete!" -ForegroundColor Green

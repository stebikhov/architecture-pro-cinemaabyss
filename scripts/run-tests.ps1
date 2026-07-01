$ErrorActionPreference = "Stop"
$BASE_URL = "http://localhost:8080"
$MOVIES_URL = "http://localhost:8081"
$EVENTS_URL = "http://localhost:8082"
$PROXY_URL = "http://localhost:8000"

$passed = 0
$failed = 0

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Method = "GET",
        [string]$Url,
        [int]$ExpectedStatus = 200,
        [switch]$ExpectArray = $false,
        [switch]$ExpectId = $false,
        [string]$Body = $null
    )
    
    try {
        $params = @{
            Uri = $Url
            Method = $Method
            UseBasicParsing = $true
            ContentType = "application/json"
        }
        
        if ($Body) { $params.Body = $Body }
        
        $response = Invoke-WebRequest @params
        $statusCode = $response.StatusCode
        
        if ($statusCode -eq $ExpectedStatus) {
            if ($ExpectArray) {
                $json = $response.Content | ConvertFrom-Json
                if ($json -is [array]) {
                    Write-Host "  [PASS] $Name" -ForegroundColor Green
                    $script:passed++
                } else {
                    Write-Host "  [FAIL] $Name - Response is not an array" -ForegroundColor Red
                    $script:failed++
                }
            } elseif ($ExpectId) {
                $json = $response.Content | ConvertFrom-Json
                if ($json.id) {
                    Write-Host "  [PASS] $Name" -ForegroundColor Green
                    $script:passed++
                } else {
                    Write-Host "  [FAIL] $Name - No id in response" -ForegroundColor Red
                    $script:failed++
                }
            } else {
                Write-Host "  [PASS] $Name" -ForegroundColor Green
                $script:passed++
            }
        } else {
            Write-Host "  [FAIL] $Name - Expected $ExpectedStatus, got $statusCode" -ForegroundColor Red
            $script:failed++
        }
    } catch {
        Write-Host "  [FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host "`n=== CinemaAbyss API Tests (PowerShell) ===" -ForegroundColor Cyan

Write-Host "`n--- Monolith Service ---" -ForegroundColor Yellow
Test-Endpoint -Name "Health Check" -Url "$BASE_URL/health"
Test-Endpoint -Name "Get All Users" -Url "$BASE_URL/api/users" -ExpectArray
Test-Endpoint -Name "Get All Movies" -Url "$BASE_URL/api/movies" -ExpectArray

Write-Host "`n--- Movies Microservice ---" -ForegroundColor Yellow
Test-Endpoint -Name "Health Check" -Url "$MOVIES_URL/api/movies/health"
Test-Endpoint -Name "Get All Movies" -Url "$MOVIES_URL/api/movies" -ExpectArray

Write-Host "`n--- Events Microservice ---" -ForegroundColor Yellow
Test-Endpoint -Name "Health Check" -Url "$EVENTS_URL/api/events/health"

Write-Host "`n--- Proxy Service ---" -ForegroundColor Yellow
Test-Endpoint -Name "Health Check" -Url "$PROXY_URL/health"
Test-Endpoint -Name "Get Movies via Proxy" -Url "$PROXY_URL/api/movies" -ExpectArray
Test-Endpoint -Name "Get Users via Proxy" -Url "$PROXY_URL/api/users" -ExpectArray

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $passed" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -eq 0) {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome tests failed!" -ForegroundColor Red
    exit 1
}

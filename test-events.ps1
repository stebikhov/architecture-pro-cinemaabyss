# Test events service
$port = 8083
$body = '{"movie_id":1,"title":"Test","action":"viewed","user_id":1}'

Write-Host "Testing events service..."
$response = Invoke-WebRequest -Uri "http://localhost:$port/api/events/movie" -Method POST -ContentType "application/json" -Body $body -UseBasicParsing

Write-Host "Status Code: $($response.StatusCode)"
Write-Host "Response: $($response.Content)"

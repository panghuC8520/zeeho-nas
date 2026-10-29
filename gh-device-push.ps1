# 轮询 GitHub device flow 拿 token，拿到后立刻把 zeeho-nas 推上去
# 由 DSH 会话在后台运行；token 只落在 %TEMP%，推送完即删
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dev = Get-Content (Join-Path $Root '.devflow\device.json') -Raw | ConvertFrom-Json
$clientId = '178c6fc778ccc68e1d6a'
$deadline = (Get-Date).AddSeconds([int]$dev.expires_in)
$interval = [Math]::Max(5, [int]$dev.interval)

$token = $null
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds $interval
  $body = @{
    client_id   = $clientId
    device_code = $dev.device_code
    grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
  }
  try {
    $resp = Invoke-RestMethod -Uri 'https://github.com/login/oauth/access_token' -Method Post -Body $body `
      -Headers @{ Accept = 'application/json'; 'User-Agent' = 'zeeho-uploader' } -TimeoutSec 30
  } catch {
    Write-Output "轮询请求失败：$($_.Exception.Message)"
    continue
  }
  if ($resp.access_token) { $token = $resp.access_token; break }
  if ($resp.error -and $resp.error -ne 'authorization_pending') {
    if ($resp.error -eq 'slow_down') { $interval += 5; continue }
    Write-Output "授权失败：$($resp.error) $($resp.error_description)"
    exit 1
  }
  Write-Output "等待授权… ($($resp.error))"
}

if (-not $token) { Write-Output '设备码已过期，未拿到 token'; exit 1 }

$tf = Join-Path $env:TEMP 'zeeho_gh_token.txt'
Set-Content -Path $tf -Value $token -NoNewline -Encoding ASCII
Write-Output '已拿到 token，开始推送…'

$env:GITHUB_TOKEN = $token
Push-Location $Root
try {
  & "$Root\push-to-github.ps1" -RepoName 'zeeho-nas'
} finally {
  Pop-Location
  if ($resp -and $resp.scope) { Write-Output "token scope: $($resp.scope)" }
}

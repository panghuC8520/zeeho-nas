# 轮询 GitHub device flow 拿 token → 推送 zeeho-nas → 更新仓库简介
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dev = Get-Content (Join-Path $Root '.devflow\device.json') -Raw | ConvertFrom-Json
$clientId = '178c6fc778ccc68e1d6a'
$deadline = (Get-Date).AddSeconds([int]$dev.expires_in)
$interval = [Math]::Max(5, [int]$dev.interval)

$token = $null
$scope = ''
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
  } catch { Write-Output "轮询失败：$($_.Exception.Message)"; continue }
  if ($resp.access_token) { $token = $resp.access_token; $scope = $resp.scope; break }
  if ($resp.error -and $resp.error -ne 'authorization_pending') {
    if ($resp.error -eq 'slow_down') { $interval += 5; continue }
    Write-Output "授权失败：$($resp.error) $($resp.error_description)"; exit 1
  }
  Write-Output '等待授权…'
}
if (-not $token) { Write-Output '设备码过期，未拿到 token'; exit 1 }

Set-Content -Path (Join-Path $env:TEMP 'zeeho_gh_token.txt') -Value $token -NoNewline -Encoding ASCII
Write-Output "已拿到 token (scope=$scope)，开始推送…"

$env:GITHUB_TOKEN = $token
Push-Location $Root
try {
  & "$Root\push-to-github.ps1" -RepoName 'zeeho-nas'

  # 仓库简介：对齐上游的写法（一句话说清定位）
  $H = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'zeeho-uploader' }
  $patch = @{
    description = '极核 ZEEHO 签到面板 · NAS/Docker 版：浏览器直接管理，免代理工具常驻，支持飞牛 fnOS / 群晖 / unRAID'
    homepage    = ''
  } | ConvertTo-Json -Compress
  $null = Invoke-RestMethod -Uri 'https://api.github.com/repos/panghuC8520/zeeho-nas' -Headers $H -Method Patch -Body $patch -ContentType 'application/json'
  Write-Output '仓库简介已更新'
} finally {
  Pop-Location
}

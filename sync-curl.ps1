<#
  github.com 被墙/连不上时用的同步脚本：
  - 设备码流程走 curl + --resolve 固定可用 IP（github.com 的 TLS 握手在本机偶发失败）
  - 推送与 Release 走 api.github.com（PowerShell REST，连接正常）

  用法：
    powershell -ExecutionPolicy Bypass -File .\sync-curl.ps1 -Mode code          # 取设备码
    powershell -ExecutionPolicy Bypass -File .\sync-curl.ps1 -Mode wait -Tag v1.1.0  # 等授权并同步
#>
param(
  [ValidateSet('code', 'wait')][string]$Mode = 'wait',
  [string]$Tag = 'v1.1.0',
  [string]$Title = 'NAS 部署包',
  [string]$RepoName = 'zeeho-nas',
  [string]$ResolveIp = '140.82.121.3'
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Zip = Join-Path (Split-Path $Root -Parent) 'zeeho-nas.zip'
$devFile = Join-Path $Root '.devflow\device.json'
$clientId = '178c6fc778ccc68e1d6a'

function CurlJson([string]$Method, [string]$Path, [string]$Data) {
  $args = @('-4', '-s', '--max-time', '40', '-X', $Method, '-H', 'Accept: application/json', '-H', 'User-Agent: zeeho-sync',
    '--resolve', "github.com:443:$ResolveIp")
  if ($Data) { $args += @('-d', $Data) }
  $args += "https://github.com$Path"
  $raw = & curl.exe @args 2>$null
  if (-not $raw) { return $null }
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

if ($Mode -eq 'code') {
  $r = $null
  for ($i = 1; $i -le 5 -and -not $r; $i++) {
    $r = CurlJson 'POST' '/login/device/code' "client_id=$clientId&scope=public_repo"
    if (-not $r) { Start-Sleep -Seconds 2 }
  }
  if (-not $r) { Write-Output '取设备码失败（github.com 不可达）'; exit 1 }
  New-Item -ItemType Directory -Force -Path (Split-Path $devFile) | Out-Null
  $r | ConvertTo-Json | Set-Content $devFile -Encoding UTF8
  Write-Output "CODE=$($r.user_code)"
  Write-Output "URL=$($r.verification_uri)"
  Write-Output "EXPIRES=$([math]::Round($r.expires_in/60,0))min"
  exit 0
}

# ---- wait 模式 ----
if (-not (Test-Path $devFile)) { throw "缺少 $devFile，先跑 -Mode code" }
$dev = Get-Content $devFile -Raw | ConvertFrom-Json
$deadline = (Get-Date).AddSeconds([int]$dev.expires_in)
$interval = [Math]::Max(5, [int]$dev.interval)
$token = $null
$scope = ''
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds $interval
  $resp = CurlJson 'POST' '/login/oauth/access_token' "client_id=$clientId&device_code=$($dev.device_code)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
  if ($resp -and $resp.access_token) { $token = $resp.access_token; $scope = $resp.scope; break }
  if ($resp -and $resp.error -and $resp.error -ne 'authorization_pending') {
    if ($resp.error -eq 'slow_down') { $interval += 5; continue }
    Write-Output "授权失败：$($resp.error) $($resp.error_description)"; exit 1
  }
  Write-Output '等待授权…'
}
if (-not $token) { Write-Output '设备码过期'; exit 1 }
Write-Output "已授权 (scope=$scope)"

# 1) 推代码（只走 api.github.com）
$env:GITHUB_TOKEN = $token
Push-Location $Root
try { & "$Root\push-to-github.ps1" -RepoName $RepoName }
finally { Pop-Location }

# 2) Release + 附件
if (-not (Test-Path $Zip)) { Write-Output "找不到 $Zip，跳过 Release"; exit 0 }
$H = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'zeeho-sync' }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Repo = "panghuC8520/$RepoName"
$hash = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $Zip).Length
$notesFile = Join-Path $Root 'RELEASE_NOTES.md'
$head = if (Test-Path $notesFile) { Get-Content $notesFile -Raw -Encoding UTF8 } else { "# $Tag`n" }
$notes = $head + "`n### 🔐 校验`n`n- 文件：``zeeho-nas.zip```n- 大小：$size B`n- SHA256：``$hash```n"
$body = @{ tag_name = $Tag; target_commitish = 'main'; name = ($Tag + ' · ' + $Title); body = $notes; draft = $false; prerelease = $false } | ConvertTo-Json -Depth 5 -Compress

$rel = $null
try { $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Headers $H -Method Post -Body ($Utf8.GetBytes($body)) -ContentType 'application/json; charset=utf-8' }
catch {
  Write-Output "建 Release 失败：$($_.Exception.Message)"
  try { $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $H } catch {}
}
if (-not $rel) { exit 1 }
Write-Output "Release: $($rel.html_url)"
# 附件上传走 uploads.github.com（与 api 同域族，通常可达）
$upload = ($rel.upload_url -replace '\{\?.*\}', '') + '?name=zeeho-nas.zip'
$upH = @{ Authorization = "Bearer $token"; 'User-Agent' = 'zeeho-sync'; Accept = 'application/vnd.github+json' }
try {
  $asset = Invoke-RestMethod -Uri $upload -Headers $upH -Method Post -InFile $Zip -ContentType 'application/zip' -TimeoutSec 300
  Write-Output "附件：$($asset.name)  $($asset.size) B"
  Write-Output "下载：$($asset.browser_download_url)"
} catch { Write-Output "附件上传失败：$($_.Exception.Message)"; exit 1 }

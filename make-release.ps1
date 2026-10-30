<#
  轮询 GitHub device flow → 建 Release → 上传 zeeho-nas.zip 作为附件
  用法：powershell -ExecutionPolicy Bypass -File .\make-release.ps1 -Tag v1.1.0
  说明：Release 正文取同目录的 RELEASE_NOTES.md（没有就用一行标题）
#>
param(
  [string]$Tag = 'v1.1.0',
  [string]$Title = 'NAS 部署包'
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Zip = Join-Path (Split-Path $Root -Parent) 'zeeho-nas.zip'
if (-not (Test-Path $Zip)) { throw "找不到部署包：$Zip" }

$dev = Get-Content (Join-Path $Root '.devflow\device.json') -Raw | ConvertFrom-Json
$clientId = '178c6fc778ccc68e1d6a'
$deadline = (Get-Date).AddSeconds([int]$dev.expires_in)
$interval = [Math]::Max(5, [int]$dev.interval)

$token = $null
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds $interval
  $body = @{ client_id = $clientId; device_code = $dev.device_code; grant_type = 'urn:ietf:params:oauth:grant-type:device_code' }
  try { $resp = Invoke-RestMethod -Uri 'https://github.com/login/oauth/access_token' -Method Post -Body $body -Headers @{ Accept = 'application/json'; 'User-Agent' = 'zeeho-release' } -TimeoutSec 30 }
  catch { Write-Output "轮询失败：$($_.Exception.Message)"; continue }
  if ($resp.access_token) { $token = $resp.access_token; break }
  if ($resp.error -and $resp.error -ne 'authorization_pending') {
    if ($resp.error -eq 'slow_down') { $interval += 5; continue }
    Write-Output "授权失败：$($resp.error) $($resp.error_description)"; exit 1
  }
  Write-Output '等待授权…'
}
if (-not $token) { Write-Output '设备码过期'; exit 1 }
Write-Output "已授权 (scope=$($resp.scope))，开始建 Release $Tag…"

$H = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'zeeho-release' }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Api = 'https://api.github.com'
$Repo = 'panghuC8520/zeeho-nas'

$hash = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $Zip).Length

$notesFile = Join-Path $Root 'RELEASE_NOTES.md'
$head = if (Test-Path $notesFile) { Get-Content $notesFile -Raw -Encoding UTF8 } else { "## ZEEHO · NAS $Tag`n" }
$tail = "`n### 🔐 校验`n`n- 文件：``zeeho-nas.zip```n- 大小：$size B`n- SHA256：``$hash```n"
$notes = $head + $tail

$release = @{
  tag_name         = $Tag
  target_commitish = 'main'
  name             = ($Tag + ' · ' + $Title)
  body             = $notes
  draft            = $false
  prerelease       = $false
} | ConvertTo-Json -Depth 5 -Compress

try {
  $rel = Invoke-RestMethod -Uri "$Api/repos/$Repo/releases" -Headers $H -Method Post -Body ($Utf8.GetBytes($release)) -ContentType 'application/json; charset=utf-8'
} catch { Write-Output "建 Release 失败：$($_.Exception.Message)"; exit 1 }
Write-Output "Release: $($rel.html_url)"

$upload = ($rel.upload_url -replace '\{\?.*\}', '') + '?name=zeeho-nas.zip'
$upH = @{ Authorization = "Bearer $token"; 'User-Agent' = 'zeeho-release'; Accept = 'application/vnd.github+json' }
try {
  $asset = Invoke-RestMethod -Uri $upload -Headers $upH -Method Post -InFile $Zip -ContentType 'application/zip' -TimeoutSec 300
  Write-Output "附件上传成功：$($asset.name)  $($asset.size) B"
  Write-Output "下载地址：$($asset.browser_download_url)"
} catch { Write-Output "附件上传失败：$($_.Exception.Message)"; exit 1 }

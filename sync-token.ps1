<#
  用已有 PAT 直接同步（不经过 github.com，只打 api.github.com）
  用法：
    $env:GITHUB_TOKEN = 'ghp_xxx'
    powershell -ExecutionPolicy Bypass -File .\sync-token.ps1 -Tag v1.1.0
#>
param(
  [string]$Tag = 'v1.1.0',
  [string]$Title = 'NAS 部署包',
  [string]$RepoName = 'zeeho-nas'
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$token = $env:GITHUB_TOKEN
if (-not $token) { throw '请先设置 $env:GITHUB_TOKEN（GitHub → Settings → Developer settings → Tokens (classic) → 勾 public_repo）' }
$token = $token.Trim()

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Zip = Join-Path (Split-Path $Root -Parent) 'zeeho-nas.zip'

# 0) 先验一下 token
$me = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'zeeho-sync' }
Write-Output "token 账号：$($me.login)"

# 1) 推代码
Push-Location $Root
try { & "$Root\push-to-github.ps1" -RepoName $RepoName }
finally { Pop-Location }

# 2) Release + 附件
if (-not (Test-Path $Zip)) { Write-Output "找不到 $Zip，跳过 Release"; exit 0 }
$H = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'zeeho-sync' }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Repo = "$($me.login)/$RepoName"
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
$upload = ($rel.upload_url -replace '\{\?.*\}', '') + '?name=zeeho-nas.zip'
$upH = @{ Authorization = "Bearer $token"; 'User-Agent' = 'zeeho-sync'; Accept = 'application/vnd.github+json' }
try {
  $asset = Invoke-RestMethod -Uri $upload -Headers $upH -Method Post -InFile $Zip -ContentType 'application/zip' -TimeoutSec 300
  Write-Output "附件：$($asset.name)  $($asset.size) B"
  Write-Output "下载：$($asset.browser_download_url)"
} catch { Write-Output "附件上传失败：$($_.Exception.Message)"; exit 1 }

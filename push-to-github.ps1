# 一键把 zeeho-nas 推到 GitHub（不需要装 git，走 REST API）
#
# 用法（在项目目录下）：
#   $env:GITHUB_TOKEN = 'ghp_xxx'                 # 只放当前会话，不写进任何文件
#   pwsh -File push-to-github.ps1 -RepoName zeeho-nas
#
# 可选参数：
#   -Private              建成私有仓库（token 需要 repo 权限）
#   -Owner  your-login    推到已存在的仓库/组织下（默认用 token 所属账号）
#   -DryRun               只打印将要上传的文件，不真的调 API

[CmdletBinding()]
param(
  [string]$RepoName = 'zeeho-nas',
  [string]$Owner,
  [string]$Description = 'ZEEHO 极核签到面板的 NAS/Docker 包装层：把 Loon/Surge 脚本跑成常驻 Web 服务（上游 cluck798/ZEEHO）',
  [switch]$Private,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 默认可能还是 TLS1.0，GitHub API 必须 TLS1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$Token = $env:GITHUB_TOKEN
if (-not $Token -and -not $DryRun) { throw '请先设置 $env:GITHUB_TOKEN（GitHub → Settings → Developer settings → Personal access tokens）' }

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $Root
try {
  # ---------- 1. 收集文件（排除运行时数据与日志）----------
  $skipDirs = @('data', 'node_modules', '.git', '.devflow')
  $files = Get-ChildItem -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    $top = ($rel -split '/')[0]
    ($skipDirs -notcontains $top) -and ($rel -notmatch '\.log$')
  }
  if (-not $files) { throw '目录里没有可上传的文件' }

  Write-Host "准备上传 $($files.Count) 个文件：" -ForegroundColor Cyan
  $files | ForEach-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    Write-Host ("  {0,-40} {1,8}" -f $rel, $_.Length)
  }
  if ($DryRun) { Write-Host 'DryRun：不发请求。' -ForegroundColor Yellow; return }

  # ---------- 2. API 头 ----------
  $H = @{
    Authorization          = "Bearer $Token"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'zeeho-nas-uploader'
  }
  $Api = 'https://api.github.com'

  $me = Invoke-RestMethod -Uri "$Api/user" -Headers $H -Method Get
  $login = if ($Owner) { $Owner } else { $me.login }
  Write-Host "目标：$login/$RepoName  (token 账号: $($me.login))" -ForegroundColor Cyan

  # ---------- 3. 仓库：有就复用，没有就建 ----------
  $repoExists = $true
  try { $null = Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName" -Headers $H -Method Get }
  catch { $repoExists = $false }

  if (-not $repoExists) {
    $payload = @{ name = $RepoName; description = $Description; private = [bool]$Private; has_issues = $true; has_wiki = $false }
    $null = Invoke-RestMethod -Uri "$Api/user/repos" -Headers $H -Method Post -Body ($payload | ConvertTo-Json) -ContentType 'application/json'
    Write-Host "已创建仓库 $login/$RepoName" -ForegroundColor Green
  } else {
    Write-Host "仓库已存在，复用 $login/$RepoName" -ForegroundColor Yellow
  }

  # ---------- 3.5 空仓库（无 commit）时 Git Data API 会返回 409，先用 Contents API 落一条 commit ----------
  $headSha = $null
  try { $headSha = (Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName/git/ref/heads/main" -Headers $H -Method Get).object.sha } catch { $headSha = $null }
  if (-not $headSha) {
    $initBody = @{
      message = 'chore: init'
      branch  = 'main'
      content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('zeeho-nas'))
    } | ConvertTo-Json -Compress
    $init = Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName/contents/.gitkeep" -Headers $H -Method Put -Body $initBody -ContentType 'application/json'
    $headSha = $init.commit.sha
    Write-Host "空仓库已初始化首条 commit（$($headSha.Substring(0,7))）" -ForegroundColor Green
  }

  # ---------- 4. 逐文件建 blob ----------
  $tree = @()
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $b64 = [Convert]::ToBase64String($bytes)
    $body = @{ content = $b64; encoding = 'base64' } | ConvertTo-Json -Compress
    $blob = Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName/git/blobs" -Headers $H -Method Post -Body $body -ContentType 'application/json'
    $tree += @{ path = $rel; mode = '100644'; type = 'blob'; sha = $blob.sha }
    Write-Host "  blob ok  $rel" -ForegroundColor DarkGray
  }

  # ---------- 5. tree → commit → ref ----------
  $treeBody = @{ tree = $tree } | ConvertTo-Json -Depth 8 -Compress
  $newTree = Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName/git/trees" -Headers $H -Method Post -Body $treeBody -ContentType 'application/json'

  $parents = @()
  if ($headSha) { $parents = @($headSha) }

  $commitBody = @{
    message = "feat: ZEEHO 面板 NAS/Docker 包装层（上游脚本 v2.16.45）"
    tree    = $newTree.sha
    parents = $parents
  } | ConvertTo-Json -Depth 6 -Compress
  $commit = Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName/git/commits" -Headers $H -Method Post -Body $commitBody -ContentType 'application/json'

  if ($headSha) {
    $upd = @{ sha = $commit.sha; force = $false } | ConvertTo-Json -Compress
    $null = Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName/git/refs/heads/main" -Headers $H -Method Patch -Body $upd -ContentType 'application/json'
  } else {
    $newRef = @{ ref = 'refs/heads/main'; sha = $commit.sha } | ConvertTo-Json -Compress
    $null = Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName/git/refs" -Headers $H -Method Post -Body $newRef -ContentType 'application/json'
  }

  $url = "https://github.com/$login/$RepoName"
  Write-Host "`n完成 → $url" -ForegroundColor Green
  Write-Host "记得回 GitHub 撤销这个 token。" -ForegroundColor Yellow
} finally {
  Pop-Location
}

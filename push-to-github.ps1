# 一键把 zeeho-nas 推到 GitHub（不需要装 git，走 REST API）
#
# 用法（在项目目录下）：
#   $env:GITHUB_TOKEN = 'ghp_xxx'
#   powershell -ExecutionPolicy Bypass -File .\push-to-github.ps1 -RepoName zeeho-nas
#
# 可选：-Private  私有仓（token 需要 repo 权限）
#       -Owner    your-login（默认用 token 所属账号）
#       -DryRun   只打印将上传的文件

[CmdletBinding()]
param(
  [string]$RepoName = 'zeeho-nas',
  [string]$Owner,
  [string]$Description = '极核 ZEEHO 签到面板 · NAS/Docker 版：浏览器直接管理，免代理工具常驻，支持飞牛 fnOS / 群晖 / unRAID',
  [switch]$Private,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$Token = $env:GITHUB_TOKEN
if (-not $Token -and -not $DryRun) { throw '请先设置 $env:GITHUB_TOKEN' }

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $Root
try {
  # ---------- 1. 收集文件 ----------
  $skipDirs = @('data', 'node_modules', '.git', '.devflow')
  $files = Get-ChildItem -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    ($skipDirs -notcontains ($rel -split '/')[0]) -and ($rel -notmatch '\.log$')
  }
  if (-not $files) { throw '目录里没有可上传的文件' }

  Write-Host "准备上传 $($files.Count) 个文件：" -ForegroundColor Cyan
  $nonAscii = @()
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    if ($rel -match '[^\x00-\x7F]') { $nonAscii += $rel }
    Write-Host ("  {0,-40} {1,8}" -f $rel, $f.Length)
  }
  if ($nonAscii.Count) {
    Write-Host "⚠ 以下路径含非 ASCII 字符，Windows PowerShell 5.1 容易把文件名写成 ???：" -ForegroundColor Yellow
    $nonAscii | ForEach-Object { Write-Host "    $_" }
  }
  if ($DryRun) { Write-Host 'DryRun：不发请求。' -ForegroundColor Yellow; return }

  # ---------- 2. 头 ----------
  $H = @{
    Authorization          = "Bearer $Token"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'zeeho-nas-uploader'
  }
  $Api = 'https://api.github.com'
  $Utf8 = New-Object System.Text.UTF8Encoding($false)

  function Post-Json([string]$Uri, $Obj, [string]$Method = 'Post') {
    $json = if ($Obj -is [string]) { $Obj } else { $Obj | ConvertTo-Json -Depth 10 -Compress }
    return Invoke-RestMethod -Uri $Uri -Headers $H -Method $Method -Body ($Utf8.GetBytes($json)) -ContentType 'application/json; charset=utf-8'
  }

  $me = Invoke-RestMethod -Uri "$Api/user" -Headers $H -Method Get
  $login = if ($Owner) { $Owner } else { $me.login }
  Write-Host "目标：$login/$RepoName  (token 账号: $($me.login))" -ForegroundColor Cyan

  # ---------- 3. 仓库 ----------
  $repoExists = $true
  try { $null = Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName" -Headers $H -Method Get } catch { $repoExists = $false }
  if (-not $repoExists) {
    $null = Post-Json "$Api/user/repos" @{ name = $RepoName; description = $Description; private = [bool]$Private; has_issues = $true; has_wiki = $false }
    Write-Host "已创建仓库 $login/$RepoName" -ForegroundColor Green
  } else {
    Write-Host "仓库已存在，复用 $login/$RepoName" -ForegroundColor Yellow
  }

  # ---------- 3.5 空仓库：Git Data API 会 409，先用 Contents API 落一条 commit ----------
  $headSha = $null
  try { $headSha = (Invoke-RestMethod -Uri "$Api/repos/$login/$RepoName/git/ref/heads/main" -Headers $H -Method Get).object.sha } catch { $headSha = $null }
  if (-not $headSha) {
    $init = Post-Json "$Api/repos/$login/$RepoName/contents/.gitkeep" @{
      message = 'chore: init'
      branch  = 'main'
      content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('zeeho-nas'))
    } 'Put'
    $headSha = $init.commit.sha
    Write-Host "空仓库已初始化首条 commit（$($headSha.Substring(0,7))）" -ForegroundColor Green
  }

  # ---------- 4. blob ----------
  $tree = @()
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
    $blob = Post-Json "$Api/repos/$login/$RepoName/git/blobs" @{ content = $b64; encoding = 'base64' }
    $tree += @{ path = $rel; mode = '100644'; type = 'blob'; sha = $blob.sha }
    Write-Host "  blob ok  $rel" -ForegroundColor DarkGray
  }

  # ---------- 5. tree → commit → ref ----------
  $newTree = Post-Json "$Api/repos/$login/$RepoName/git/trees" @{ tree = $tree }
  $commit  = Post-Json "$Api/repos/$login/$RepoName/git/commits" @{
    message = "feat: ZEEHO 面板 NAS/Docker 包装层（上游脚本 v2.16.45）"
    tree    = $newTree.sha
    parents = @($headSha)
  }
  $null = Post-Json "$Api/repos/$login/$RepoName/git/refs/heads/main" @{ sha = $commit.sha; force = $false } 'Patch'

  # ---------- 6. 仓库简介（UTF-8 字节，避免 5.1 把中文写成 ?）----------
  try { $null = Post-Json "$Api/repos/$login/$RepoName" @{ description = $Description } 'Patch' } catch { Write-Host "简介更新失败（不影响代码）：$($_.Exception.Message)" -ForegroundColor Yellow }

  Write-Host "`n完成 → https://github.com/$login/$RepoName  (head $($commit.sha.Substring(0,7)))" -ForegroundColor Green
} finally {
  Pop-Location
}

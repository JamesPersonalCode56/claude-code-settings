<#
  setup-claude-code.ps1
  ----------------------
  Tự cài Claude Code (npm -g) và tự điền key/endpoint từ file .env nằm CÙNG THƯ MỤC
  với script này (Alibaba Cloud Model Studio — endpoint Anthropic-compatible, model Qwen).

  Cách chạy (trong PowerShell hoặc cmd, tại thư mục có cả script này và .env):
      powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-claude-code.ps1
      # hoặc đơn giản: setup-claude-code.cmd
      # thêm -Test để gọi thử 1 lệnh API xác minh key (tốn 1 ít token):
      #   ... -File .\setup-claude-code.ps1 -Test

  .env phải theo form của .env.example:
      BASE_URL='https://.../apps/anthropic'
      API_KEYS='sk-...'
      ANTHROPIC_MODEL='qwen3.7-max[1m]'
      ANTHROPIC_DEFAULT_HAIKU_MODEL=...  ANTHROPIC_DEFAULT_SONNET_MODEL=...
      ANTHROPIC_DEFAULT_OPUS_MODEL=...   CLAUDE_CODE_SUBAGENT_MODEL=...
#>

param([switch]$Test)

$ErrorActionPreference = 'Stop'

# --- Thư mục của script (để tìm .env cạnh nó) ---
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$envFile = Join-Path $here '.env'

Write-Host "== Claude Code setup (folder: $here) ==" -ForegroundColor Cyan

# --- 1. Yêu cầu Node.js ---
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Host "[X] Khong tim thay Node.js. Cai Node 18+ truoc: https://nodejs.org (hoac: winget install OpenJS.NodeJS.LTS)" -ForegroundColor Red
  exit 1
}
Write-Host ("[*] node " + (& node -v) + " / npm " + (& npm -v))

# --- 2. Cai / cap nhat Claude Code ---
Write-Host "[*] Dang cai @anthropic-ai/claude-code (npm -g) ..."
& npm install -g '@anthropic-ai/claude-code'
if ($LASTEXITCODE -ne 0) { Write-Host "[X] npm install that bai." -ForegroundColor Red; exit 1 }

$npmPrefix = (& npm config get prefix).Trim()
$claudeCmd = Join-Path $npmPrefix 'claude.cmd'
if (-not (Test-Path $claudeCmd)) { Write-Host "[X] Khong thay claude sau khi cai ($claudeCmd)." -ForegroundColor Red; exit 1 }
Write-Host ("[*] claude " + (& $claudeCmd --version))

# --- 3. Doc .env cung thu muc va map sang bien Claude Code ---
if (-not (Test-Path $envFile)) {
  Write-Host "[X] Khong thay .env canh script ($envFile). Copy .env.example thanh .env va dien key." -ForegroundColor Red
  exit 1
}

# .env dung ten BASE_URL/API_KEYS -> map sang bien Claude Code can.
$map  = @{ 'BASE_URL' = 'ANTHROPIC_BASE_URL'; 'API_KEYS' = 'ANTHROPIC_AUTH_TOKEN' }
$pass = @('ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL',
          'ANTHROPIC_DEFAULT_OPUS_MODEL','CLAUDE_CODE_SUBAGENT_MODEL')

$set = @()
foreach ($raw in Get-Content -LiteralPath $envFile) {
  $line = $raw.Trim()
  if ($line -eq '' -or $line.StartsWith('#')) { continue }
  if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
    $k = $matches[1]; $v = $matches[2].Trim()
    # bo dau nhay bao quanh (' hoac ")
    if ($v.Length -ge 2) {
      $f = $v[0]; $g = $v[$v.Length - 1]
      if (($f -eq [char]39 -and $g -eq [char]39) -or ($f -eq [char]34 -and $g -eq [char]34)) {
        $v = $v.Substring(1, $v.Length - 2)
      }
    }
    $target = if ($map.ContainsKey($k)) { $map[$k] } elseif ($pass -contains $k) { $k } else { $null }
    if ($target) {
      [Environment]::SetEnvironmentVariable($target, $v, 'User')  # luu vinh vien (User scope)
      Set-Item -Path ("Env:" + $target) -Value $v                 # cho phien hien tai (de -Test chay)
      $set += $target
    }
  }
}

if ($set.Count -eq 0) { Write-Host "[X] .env khong co bien nao hop le (BASE_URL/API_KEYS/...)." -ForegroundColor Red; exit 1 }
Write-Host ("[*] Da cau hinh bien: " + ($set -join ', ')) -ForegroundColor Green
Write-Host ("    Endpoint: " + $env:ANTHROPIC_BASE_URL)
Write-Host ("    Model   : " + $env:ANTHROPIC_MODEL)
Write-Host ("    Token   : (an, dai " + ($env:ANTHROPIC_AUTH_TOKEN).Length + " ky tu)")

# --- 4. (Tuy chon) Test 1 lenh API ---
if ($Test) {
  Write-Host "[*] Test key bang 1 lenh API nho ..."
  $reply = (& $claudeCmd -p "Reply with exactly this one word: KEYWORKS" 2>&1 | Out-String).Trim()
  if ($reply -match 'KEYWORKS') { Write-Host "[OK] Key hoat dong. Claude Code da san sang." -ForegroundColor Green }
  else { Write-Host ("[!] Phan hoi (kiem tra loi): " + $reply) -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "Xong. Mo terminal MOI (de nap bien moi) roi go:  claude" -ForegroundColor Cyan

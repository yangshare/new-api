# start-dev.ps1 - 一键启动 new-api 本地开发环境
# Usage: .\scripts\start-dev.ps1
# 说明：同时启动后端（Go）和前端（Rsbuild dev server），按 Ctrl+C 可停止所有服务

$ErrorActionPreference = "Stop"

# ── 颜色输出函数 ──
function Write-Info($msg)  { Write-Host "  [INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  [OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "  [WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "  [ERR]   $msg" -ForegroundColor Red }

# ── 项目路径 ──
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BackendRoot = $ProjectRoot
$FrontendDir = Join-Path $ProjectRoot "web\default"

# ── 检查必要命令 ──
function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  new-api - 本地开发环境一键启动" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# 检查 Bun
if (-not (Test-Command "bun")) {
    Write-Err "未找到 bun 命令，请先安装 Bun: https://bun.sh"
    exit 1
}
Write-Ok "Bun 已安装"

# 检查 Go（尝试自动添加到 PATH）
$goCmd = Get-Command "go" -ErrorAction SilentlyContinue
if (-not $goCmd) {
    $goPaths = @(
        "C:\Program Files\Go\bin\go.exe",
        "C:\Go\bin\go.exe",
        "$env:LOCALAPPDATA\Programs\Go\bin\go.exe"
    )
    foreach ($p in $goPaths) {
        if (Test-Path $p) {
            $goBinDir = Split-Path -Parent $p
            $env:PATH = "$goBinDir;$env:PATH"
            Write-Info "已自动添加 Go 到 PATH: $goBinDir"
            break
        }
    }
}

if (-not (Test-Command "go")) {
    Write-Err "未找到 go 命令，请确保 Go 已安装且加入 PATH"
    exit 1
}

$goVersion = & go version 2>$null
Write-Ok "Go 已安装: $goVersion"

# ── 检查 .env 文件 ──
$envFile = Join-Path $ProjectRoot ".env"
if (-not (Test-Path $envFile)) {
    Write-Warn "未找到 .env 文件，将使用默认配置"
    Write-Info "如需自定义配置，请复制 .env.example 为 .env"
} else {
    Write-Ok ".env 配置文件已加载"
}

# ── 检查前端依赖 ──
$nodeModules = Join-Path $FrontendDir "node_modules"
if (-not (Test-Path $nodeModules)) {
    Write-Info "前端依赖未安装，正在安装..."
    Push-Location (Join-Path $ProjectRoot "web")
    try {
        bun install
        if ($LASTEXITCODE -ne 0) {
            Write-Err "前端依赖安装失败"
            exit 1
        }
        Write-Ok "前端依赖安装完成"
    } finally {
        Pop-Location
    }
} else {
    Write-Ok "前端依赖已安装"
}

# ── 检查前端 embed 目录（编译要求）──
$embedDirs = @(
    (Join-Path $ProjectRoot "web\default\dist"),
    (Join-Path $ProjectRoot "web\classic\dist")
)
foreach ($d in $embedDirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Info "创建 embed 目录: $d"
    }
    $idx = Join-Path $d "index.html"
    if (-not (Test-Path $idx)) {
        '<!DOCTYPE html><html><head><title>New API</title></head><body>Dev Mode</body></html>' | Set-Content $idx -Encoding UTF8
        Write-Info "创建占位文件: $idx"
    }
}

# ── 启动后端 ──
Write-Host ""
Write-Info "正在启动后端服务..."
$backendProcess = Start-Process -FilePath "go" `
    -ArgumentList "run", "main.go" `
    -WorkingDirectory $BackendRoot `
    -WindowStyle Hidden `
    -PassThru

# 等待后端启动
$backendReady = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:3000/api/status" -Method GET -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -eq 200) {
            $backendReady = $true
            break
        }
    } catch {
        # 继续等待
    }
}

if (-not $backendReady) {
    Write-Warn "后端服务尚未响应，可能仍在启动中..."
} else {
    Write-Ok "后端服务已就绪: http://localhost:3000"
}

# ── 启动前端 ──
Write-Info "正在启动前端开发服务器..."
Write-Host ""
Write-Host "  --------------------------------------------" -ForegroundColor Green
Write-Host "  后端 API: http://localhost:3000" -ForegroundColor Green
Write-Host "  前端页面: http://localhost:5173" -ForegroundColor Green
Write-Host "  --------------------------------------------" -ForegroundColor Green
Write-Host ""
Write-Host "  按 Ctrl+C 停止所有服务..." -ForegroundColor Yellow
Write-Host ""

# 捕获退出信号，清理后端进程
$script:shutdown = $false
function Stop-AllServices {
    if ($script:shutdown) { return }
    $script:shutdown = $true

    Write-Host ""
    Write-Host "  正在停止服务..." -ForegroundColor Yellow

    if ($backendProcess -and -not $backendProcess.HasExited) {
        Write-Info "结束后端进程 (PID: $($backendProcess.Id))..."
        Stop-Process -Id $backendProcess.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Ok "所有服务已停止"
    Write-Host ""
}

# 注册退出事件
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Stop-AllServices
}

try {
    Push-Location $FrontendDir
    bun run dev
} finally {
    Pop-Location
    Stop-AllServices

    # 取消事件注册
    Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
}

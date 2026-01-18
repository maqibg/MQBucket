# Generate Bucket Status JSON
# 用于生成 status.json，供 bucket-index.html 展示版本检测结果

param(
    [string]$BucketDir = "bucket",
    [string]$OutFile = "public/status.json",
    [int]$MaxLogLength = 8192,
    [string]$Application = "",
    [string]$Token = ""
)

$ErrorActionPreference = "Stop"

# 设置 GitHub Token（如果提供）
if ($Token) {
    $env:GITHUB_TOKEN = $Token
    Write-Host "✓ 已设置 GitHub Token" -ForegroundColor Green
} elseif ($env:GITHUB_TOKEN) {
    Write-Host "✓ 使用环境变量中的 GitHub Token" -ForegroundColor Green
} else {
    Write-Warning "未设置 GitHub Token，API 限流为 60 次/小时"
}

# 初始化结果结构
$result = @{
    schemaVersion = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    source = "ci"
    repo = @{
        name = "MQBucket"
        owner = "maqibg"
        ref = "main"
        commit = ""
    }
    environment = @{
        scoopCheckver = @{
            path = ""
            version = "unknown"
        }
    }
    summary = @{
        total = 0
        latest = 0
        outdated = 0
        failed = 0
    }
    apps = @()
}

# 获取 Git 信息
try {
    $result.repo.commit = (git rev-parse HEAD 2>$null)
    $result.repo.ref = (git rev-parse --abbrev-ref HEAD 2>$null)
} catch {
    Write-Warning "无法获取 Git 信息: $_"
}

# 查找 Scoop checkver.ps1
$scoopHome = $env:SCOOP_HOME
if (-not $scoopHome) {
    # 尝试常见路径
    $possiblePaths = @(
        "$env:USERPROFILE\scoop",
        "C:\ProgramData\scoop",
        "D:\Software\Scoop"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path "$path\apps\scoop\current\bin\checkver.ps1") {
            $scoopHome = $path
            break
        }
    }
}

if (-not $scoopHome) {
    Write-Error "找不到 Scoop 安装目录，请设置 SCOOP_HOME 环境变量"
    exit 1
}

$checkverPath = "$scoopHome\apps\scoop\current\bin\checkver.ps1"
if (Test-Path $checkverPath) {
    $result.environment.scoopCheckver.path = $checkverPath
} else {
    Write-Error "找不到 Scoop checkver.ps1: $checkverPath"
    exit 1
}

# 获取所有 manifest 文件
if ($Application) {
    # 单个应用检测
    $manifestPath = Join-Path $BucketDir "$Application.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Error "找不到应用 manifest: $manifestPath"
        exit 1
    }
    $manifests = @(Get-Item $manifestPath)
    Write-Host "开始检测单个应用: $Application"
} else {
    # 全部应用检测
    $manifests = Get-ChildItem -Path $BucketDir -Filter "*.json" | Where-Object { $_.Name -ne "app-name.json.template" }
    if ($Token -or $env:GITHUB_TOKEN) {
        Write-Host "开始检测 $($manifests.Count) 个应用（并行模式：10个/批，间隔 2 秒）..." -ForegroundColor Cyan
    } else {
        Write-Host "开始检测 $($manifests.Count) 个应用（串行模式，每次间隔 2 秒）..." -ForegroundColor Yellow
    }
}
$result.summary.total = $manifests.Count

# 检测函数
function Test-AppVersion {
    param($manifest, $checkverPath, $bucketDir, $maxLogLength)

    $appName = $manifest.BaseName
    $startTime = Get-Date

    # 读取 manifest 获取当前版本
    $manifestContent = Get-Content $manifest.FullName -Raw | ConvertFrom-Json
    $bucketVersion = $manifestContent.version

    # 解析 checkver 配置
    $checkverInfo = @{
        mode = "unknown"
        url = $null
        regex = $null
        jsonpath = $null
        script = $false
    }

    if ($manifestContent.checkver) {
        $cv = $manifestContent.checkver
        if ($cv -is [string]) {
            if ($cv -eq "github") {
                $checkverInfo.mode = "github"
            } else {
                $checkverInfo.mode = "regex"
                $checkverInfo.regex = $cv
            }
        } elseif ($cv -is [hashtable] -or $cv -is [PSCustomObject]) {
            if ($cv.github) {
                $checkverInfo.mode = "github"
                $checkverInfo.url = $cv.github
            } elseif ($cv.url) {
                $checkverInfo.mode = "url"
                $checkverInfo.url = $cv.url
            }
            if ($cv.regex) { $checkverInfo.regex = $cv.regex }
            if ($cv.jsonpath) { $checkverInfo.jsonpath = $cv.jsonpath }
            if ($cv.script) { $checkverInfo.script = $true }
        }
    }

    # 执行 checkver
    $checkverOutput = ""
    $checkverError = ""
    $latestVersion = $bucketVersion
    $status = "failed"
    $message = $null

    try {
        $output = & pwsh -NoProfile -Command "& '$checkverPath' -App '$appName' -Dir '$bucketDir' 2>&1"
        $checkverOutput = ($output | Out-String).Trim()

        # 解析输出
        if ($checkverOutput -match "^$appName`: (.+)$") {
            $versionInfo = $matches[1]

            if ($versionInfo -match "^([\d\.\-\w]+)$") {
                $latestVersion = $matches[1]
                $status = "latest"
            } elseif ($versionInfo -match "^([\d\.\-\w]+) \(scoop version is ([\d\.\-\w]+)\)") {
                $latestVersion = $matches[1]
                $status = "outdated"
                $message = "新版本可用: $latestVersion (当前: $bucketVersion)"
            } else {
                $status = "failed"
                $message = $versionInfo
            }
        } elseif ($checkverOutput -match "ERROR") {
            $status = "failed"
            $message = ($checkverOutput -split "`n" | Select-Object -First 3) -join " "
        } else {
            $status = "failed"
            $message = "无法解析 checkver 输出"
        }
    } catch {
        $checkverError = $_.Exception.Message
        $status = "failed"
        $message = "执行失败: $checkverError"
    }

    $duration = ((Get-Date) - $startTime).TotalMilliseconds

    # 限制日志长度
    if ($checkverOutput.Length -gt $maxLogLength) {
        $checkverOutput = $checkverOutput.Substring(0, $maxLogLength) + "`n... (truncated)"
    }
    if ($checkverError.Length -gt $maxLogLength) {
        $checkverError = $checkverError.Substring(0, $maxLogLength) + "`n... (truncated)"
    }

    # 返回应用信息（使用 PSCustomObject 避免字符串化）
    [pscustomobject]@{
        name = $appName
        manifestPath = "bucket/$($manifest.Name)"
        homepage = $manifestContent.homepage
        description = $manifestContent.description
        bucketVersion = $bucketVersion
        latestVersion = $latestVersion
        status = $status
        checkedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        durationMs = [int]$duration
        autoupdate = @{
            present = [bool]$manifestContent.autoupdate
            hint = $null
        }
        checkver = $checkverInfo
        message = $message
        log = @{
            stdout = if ($checkverOutput) { $checkverOutput } else { $null }
            stderr = if ($checkverError) { $checkverError } else { $null }
        }
    }
}

# 主检测循环
$allApps = @()

if (($Token -or $env:GITHUB_TOKEN) -and $manifests.Count -gt 1) {
    # 批次模式：10个一批，间隔2秒（串行执行，兼容 PowerShell 5.1）
    $batchSize = 10
    $batches = [Math]::Ceiling($manifests.Count / $batchSize)

    for ($i = 0; $i -lt $batches; $i++) {
        $start = $i * $batchSize
        $end = [Math]::Min($start + $batchSize, $manifests.Count)
        $batch = $manifests[$start..($end-1)]

        Write-Host "批次 $($i+1)/$batches (检测 $($batch.Count) 个应用)..." -ForegroundColor Cyan

        # 串行执行当前批次（兼容 PowerShell 5.1）
        foreach ($manifest in $batch) {
            $appInfo = Test-AppVersion -manifest $manifest -checkverPath $checkverPath -bucketDir $BucketDir -maxLogLength $MaxLogLength
            $allApps += $appInfo
            $color = switch ($appInfo.status) {
                "latest" { "Green" }
                "outdated" { "Yellow" }
                "failed" { "Red" }
                default { "Gray" }
            }
            Write-Host "  $($appInfo.name) [$($appInfo.status)] $($appInfo.latestVersion)" -ForegroundColor $color
        }

        # 批次间延迟
        if ($i -lt $batches - 1) {
            Start-Sleep -Seconds 2
        }
    }
} else {
    # 串行模式（无token或单个应用）
    foreach ($manifest in $manifests) {
        if ($manifests.IndexOf($manifest) -gt 0) {
            Start-Sleep -Seconds 2
        }

        Write-Host "检测 $($manifest.BaseName) ..." -NoNewline
        $appInfo = Test-AppVersion -manifest $manifest -checkverPath $checkverPath -bucketDir $BucketDir -maxLogLength $MaxLogLength
        $allApps += $appInfo

        $color = switch ($appInfo.status) {
            "latest" { "Green" }
            "outdated" { "Yellow" }
            "failed" { "Red" }
            default { "Gray" }
        }
        Write-Host " [$($appInfo.status)] $($appInfo.latestVersion)" -ForegroundColor $color
    }
}

# 添加所有应用到结果并更新统计
$result.apps = $allApps

foreach ($appInfo in $allApps) {
    switch ($appInfo.status) {
        "latest" { $result.summary.latest++ }
        "outdated" { $result.summary.outdated++ }
        "failed" { $result.summary.failed++ }
    }
}


# 确保输出目录存在
$outDir = Split-Path $OutFile -Parent
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# 输出 JSON
$result | ConvertTo-Json -Depth 10 | Set-Content $OutFile -Encoding UTF8

Write-Host "`n✅ 检测完成！" -ForegroundColor Green
Write-Host "总计: $($result.summary.total) | 最新: $($result.summary.latest) | 需更新: $($result.summary.outdated) | 失败: $($result.summary.failed)"
Write-Host "结果已保存至: $OutFile"

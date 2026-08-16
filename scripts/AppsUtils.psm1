#Requires -Version 5.1
Set-StrictMode -Version 3.0

<#
.SYNOPSIS
    Scoop 辅助模块：安全执行外部命令、UTF-8 文件输出、持久化数据挂载
.DESCRIPTION
    提供 Invoke-ExternalCommand2、Out-UTF8File、Mount-ExternalRuntimeData、Dismount-ExternalRuntimeData
    用于 Scoop bucket 中应用的安装/卸载脚本。
#>

# 辅助函数：确保日志目录存在
function Format-LogPath {
    param([string]$Path)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $Path
}

<#
.SYNOPSIS
    执行外部命令，支持参数转义、日志记录、管理员权限等
.PARAMETER FilePath
    要执行的程序路径
.PARAMETER ArgumentList
    参数数组
.PARAMETER RunAs
    使用管理员权限运行
.PARAMETER Quiet
    静默运行（隐藏窗口）
.PARAMETER Activity
    显示的活动消息（例如 "Installing..."）
.PARAMETER ContinueExitCodes
    可接受的退出码字典，用于忽略特定错误
.PARAMETER LogPath
    输出日志文件路径
.OUTPUTS
    bool - 命令是否成功执行
#>
function Invoke-ExternalCommand2 {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,
        [Parameter(Position = 1)]
        [Alias('Args')]
        [string[]]$ArgumentList,
        [Parameter(ParameterSetName = 'UseShellExecute')]
        [switch]$RunAs,
        [Parameter(ParameterSetName = 'UseShellExecute')]
        [switch]$Quiet,
        [Alias('Msg')]
        [string]$Activity,
        [Alias('cec')]
        [hashtable]$ContinueExitCodes,
        [Parameter(ParameterSetName = 'Default')]
        [Alias('Log')]
        [string]$LogPath
    )

    if ($Activity) {
        Write-Host "$Activity " -NoNewline
    }

    # 确保日志目录存在
    if ($LogPath) {
        $LogPath = Format-LogPath -Path $LogPath
    }

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo.FileName = $FilePath
    $Process.StartInfo.UseShellExecute = $false
    $redirectToLogFile = $false

    # 处理日志参数
    if ($LogPath) {
        if ($FilePath -match '^msiexec(.exe)?$') {
            $ArgumentList += "/lwe `"$LogPath`""
        } else {
            $redirectToLogFile = $true
            $Process.StartInfo.RedirectStandardOutput = $true
            $Process.StartInfo.RedirectStandardError = $true
        }
    }

    # 管理员权限
    if ($RunAs) {
        $Process.StartInfo.UseShellExecute = $true
        $Process.StartInfo.Verb = 'RunAs'
    }

    # 静默模式
    if ($Quiet) {
        $Process.StartInfo.UseShellExecute = $true
        $Process.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    }

    # 构造参数
    if ($ArgumentList.Length -gt 0) {
        if ($FilePath -match '^((cmd|cscript|wscript|msiexec)(\.exe)?|.*\.(bat|cmd|js|vbs|wsf))$') {
            $Process.StartInfo.Arguments = $ArgumentList -join ' '
        } elseif ($Process.StartInfo.PSObject.Properties.Name -contains 'ArgumentList') {
            # .NET Core / PowerShell 6+ 原生支持 ArgumentList
            $ArgumentList | ForEach-Object { $Process.StartInfo.ArgumentList.Add($_) }
        } else {
            # PowerShell 5.1 手动转义
            $escapedArgs = $ArgumentList | ForEach-Object {
                # 转义反斜杠和双引号（参考微软文档）
                $s = $_ -replace '(\\+)"', '$1$1"'
                $s = $s -replace '(\\+)$', '$1$1'
                $s = $s -replace '"', '\"'
                $s
            }
            $Process.StartInfo.Arguments = $escapedArgs -join ' '
            Write-Debug "Arguments: $($Process.StartInfo.Arguments)"
        }
    }

    # 启动进程
    try {
        [void]$Process.Start()
    } catch {
        if ($Activity) {
            Write-Host 'error.' -ForegroundColor DarkRed
        }
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        return $false
    }

    # 异步读取输出（避免死锁）
    if ($redirectToLogFile) {
        $stdoutTask = $Process.StandardOutput.ReadToEndAsync()
        $stderrTask = $Process.StandardError.ReadToEndAsync()
    }

    $Process.WaitForExit()

    # 写入日志
    if ($redirectToLogFile) {
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        Out-UTF8File -FilePath $LogPath -Append -InputObject $stdout
        Out-UTF8File -FilePath $LogPath -Append -InputObject $stderr
    }

    # 检查退出码
    if ($Process.ExitCode -ne 0) {
        if ($ContinueExitCodes -and $ContinueExitCodes.ContainsKey($Process.ExitCode)) {
            if ($Activity) {
                Write-Host 'done.' -ForegroundColor DarkYellow
            }
            Write-Host $ContinueExitCodes[$Process.ExitCode] -ForegroundColor DarkYellow
            return $true
        } else {
            if ($Activity) {
                Write-Host 'error.' -ForegroundColor DarkRed
            }
            Write-Host "Exit code was $($Process.ExitCode)!" -ForegroundColor DarkRed
            return $false
        }
    }

    if ($Activity) {
        Write-Host 'done.' -ForegroundColor Green
    }
    return $true
}

<#
.SYNOPSIS
    将输入对象以 UTF-8 编码写入文件（支持流式管道）
.PARAMETER FilePath
    目标文件路径
.PARAMETER Append
    追加模式（默认覆盖）
.PARAMETER NoNewLine
    不添加换行符
.PARAMETER InputObject
    要写入的内容（从管道或参数传入）
.EXAMPLE
    "Hello" | Out-UTF8File -FilePath .\log.txt -Append
#>
function Out-UTF8File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [ValidateScript({ Test-Path (Split-Path $_ -Parent) -PathType Container })]
        [string]$FilePath,
        [switch]$Append,
        [switch]$NoNewLine,
        [Parameter(ValueFromPipeline = $true)]
        [PSObject]$InputObject
    )

    begin {
        # 使用 StreamWriter 以 UTF-8 无 BOM 格式，一次打开，多次写入
        $streamWriter = [System.IO.StreamWriter]::new(
            $FilePath,
            $Append,
            [System.Text.UTF8Encoding]::new($false)
        )
        $streamWriter.AutoFlush = $true
    }

    process {
        if ($InputObject -ne $null) {
            $str = $InputObject.ToString()
            if ($NoNewLine) {
                $streamWriter.Write($str)
            } else {
                $streamWriter.WriteLine($str)
            }
        }
    }

    end {
        $streamWriter.Dispose()
    }
}

<#
.SYNOPSIS
    挂载外部运行时数据（将应用数据目录链接到持久化目录）
.PARAMETER Source
    持久化目录路径（通常为 $persist_dir）
.PARAMETER Target
    应用实际使用的数据目录路径
.DESCRIPTION
    若 Source 不存在则创建；若 Target 存在则迁移其内容到 Source（若非 Junction）；
    最后创建 Junction 链接 Target -> Source。
#>
function Mount-ExternalRuntimeData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Source,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Target
    )

    # 确保 Source 目录存在
    if (-not (Test-Path $Source)) {
        New-Item -ItemType Directory -Path $Source -Force | Out-Null
    }

    # 处理已存在的 Target
    if (Test-Path $Target) {
        $item = Get-Item $Target -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'Junction') {
            # 若已是 Junction，直接删除（数据在 Source 中）
            Remove-Item $Target -Force
        } else {
            # 普通目录或文件，迁移内容到 Source，然后删除原 Target
            try {
                Get-ChildItem $Target -Force | Move-Item -Destination $Source -Force -ErrorAction Stop
                Remove-Item $Target -Force -ErrorAction Stop
            } catch {
                Write-Error "迁移 '$Target' 内容到 '$Source' 失败: $($_.Exception.Message)"
                return
            }
        }
    }

    # 创建 Junction 链接
    try {
        New-Item -ItemType Junction -Path $Target -Target $Source -Force | Out-Null
    } catch {
        Write-Error "创建 Junction 链接 '$Target' -> '$Source' 失败: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    卸载外部运行时数据（删除 Junction 链接）
.PARAMETER Target
    应用数据目录路径（Junction 所在位置）
.DESCRIPTION
    仅当 Target 是 Junction 时才删除，避免误删用户数据。
#>
function Dismount-ExternalRuntimeData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Target
    )

    if (Test-Path $Target) {
        $item = Get-Item $Target -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'Junction') {
            Remove-Item $Target -Force
            Write-Debug "已删除 Junction: $Target"
        } else {
            Write-Warning "目标 '$Target' 不是 Junction，保留原目录。"
        }
    }
}

# 导出模块成员
Export-ModuleMember -Function `
    Invoke-ExternalCommand2,
    Out-UTF8File,
    Mount-ExternalRuntimeData,
    Dismount-ExternalRuntimeData

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MQBucket is a Scoop bucket repository for Windows package management. Scoop is a command-line installer for Windows, and this bucket contains application manifests (JSON files) that define how to install, update, and uninstall various applications.

## Repository Structure

```
bucket/           # App manifests (*.json) - one file per application
bin/              # PowerShell wrapper scripts for Scoop maintenance tools
scripts/          # Shared PowerShell utilities (AppsUtils.psm1)
deprecated/       # Retired manifests kept for reference
.github/          # CI workflows and issue/PR templates
```

## Common Commands

All commands should be run from Git Bash, invoking PowerShell as needed:

```bash
# Run Pester-based bucket validation tests
pwsh -File bin/test.ps1

# Format all manifest JSON files (run before committing)
pwsh -File bin/formatjson.ps1

# Check for broken URLs in manifests
pwsh -File bin/checkurls.ps1

# Check for hash mismatches
pwsh -File bin/checkhashes.ps1

# Check for new versions (use -? for options)
pwsh -File bin/checkver.ps1 -?
pwsh -File bin/checkver.ps1 <app-name>
pwsh -File bin/checkver.ps1 *

# Smoke test: install an app locally
scoop bucket add mqbucket <path-to-repo>
scoop install mqbucket/<app>
```

## Manifest Structure

Manifests are JSON files in `bucket/` directory. Key fields:

- `version`: Current version string
- `description`: Brief app description
- `homepage`: Project homepage URL
- `license`: License identifier or object with `identifier` field
- `architecture`: Download URLs and hashes per architecture (64bit, 32bit, arm64)
- `checkver`: Version checking configuration (typically `{"github": "https://github.com/..."}`)
- `autoupdate`: URL patterns for automatic updates
- `persist`: Files/directories to preserve across updates
- `shortcuts`: Desktop/start menu shortcuts
- `pre_install`/`post_install`: Installation scripts
- `bin`: Executables to add to PATH

Use `bucket/app-name.json.template` as a starting point for new manifests.

## Utilities Module (scripts/AppsUtils.psm1)

Provides helper functions for complex manifest scripts:

- `Mount-ExternalRuntimeData $Source $Target`: Create junction links for persistent data
- `Dismount-ExternalRuntimeData $Target`: Remove junction links
- `Invoke-ExternalCommand2`: Enhanced external command execution with logging

## Coding Standards

- Follow `.editorconfig`: UTF-8, CRLF, 4-space indent (2-space for YAML)
- Always run `bin/formatjson.ps1` before committing manifest changes
- Keep one app per manifest file, filename matches canonical app name
- Update `hash` field whenever changing download URLs
- **Update `bucket-index.html`** whenever adding/removing/updating a bucket manifest to keep the installation commands page in sync

## Commit Message Format

```
<app-name>: Update to version <x.y.z>
```

Keep one app/version bump per commit when possible.

## Testing Requirements

- Framework: Pester 5 (requires PowerShell 5.1+ with BuildHelpers and Pester modules)
- CI runs tests on both Windows PowerShell and PowerShell Core
- Run `bin/test.ps1` locally before submitting PRs
- Excavator workflow auto-updates manifests every 4 hours via GitHub Actions

## Key Patterns

1. **GitHub-based version checking**: Most manifests use `"checkver": {"github": "https://github.com/owner/repo"}` for automatic version detection

2. **Persistent data**: Use `persist` array for config files and data directories that should survive updates

3. **Junction links**: For apps that require data in specific locations, use the `Mount-ExternalRuntimeData` function from AppsUtils.psm1

4. **Multi-architecture support**: Define separate URLs/hashes under `architecture.64bit`, `architecture.32bit`, `architecture.arm64`

## 创建新Bucket的完整流程

### 1. 获取GitHub Releases信息

使用Python脚本自动获取releases信息（需要GitHub token）：

```bash
# 在PowerShell中设置token
$env:GITHUB_TOKEN = "your_token_here"

# 运行脚本获取releases信息
cd scripts
uv run --with requests get_releases.py your_token_here
```

脚本会输出：
- 版本号（tag_name）
- 下载链接（browser_download_url）
- 文件名

### 2. 创建Manifest文件

在 `bucket/` 目录创建 `app-name.json`，包含：
- 基本信息（version, description, homepage, license）
- 下载链接（url）
- hash字段（先填"PLACEHOLDER"）
- 架构配置（architecture）
- 持久化配置（persist, post_install）

### 3. 计算Hash值

```bash
pwsh -File bin/checkhashes.ps1 app-name
```

脚本会自动下载文件并输出正确的hash值，然后更新manifest文件。

### 4. 格式化JSON

```bash
pwsh -File bin/formatjson.ps1
```

### 5. 验证Manifest

```bash
pwsh -File bin/test.ps1
```

### 6. 更新索引页面

更新 `bucket-index.html`，添加新应用的安装命令。

### 完整示例

```bash
# 1. 获取releases信息
cd scripts && uv run --with requests get_releases.py $env:GITHUB_TOKEN

# 2. 创建manifest（手动编辑bucket/app-name.json）

# 3. 计算hash
cd .. && pwsh -File bin/checkhashes.ps1 app-name

# 4. 格式化
pwsh -File bin/formatjson.ps1

# 5. 测试
pwsh -File bin/test.ps1

# 6. 提交
git add bucket/app-name.json bucket-index.html
git commit -m "app-name: Add version x.y.z"
```

## Bucket 编写注意事项

### 安装包类型处理

#### 1. Electron NSIS 安装包
Electron 应用的 NSIS 安装包通常有嵌套结构：
```json
"url": "https://example.com/app-setup.exe#/dl.7z",
"pre_install": [
    "Expand-7zipArchive \"$dir\`$PLUGINSDIR\app-64.7z\" \"$dir\" -Removal",
    "Remove-Item \"$dir\`$*\" -Force -Recurse -ErrorAction SilentlyContinue"
]
```
- 使用 `#/dl.7z` 后缀让 Scoop 用 7z 解压 NSIS 包
- 主程序在 `$PLUGINSDIR\app-64.7z` 中，需要二次解压
- 删除 `$PLUGINSDIR`、`$R0` 等临时目录

#### 2. Tauri NSIS 安装包
Tauri 应用的 NSIS 包直接解压出可执行文件，**不需要二次解压**：
```json
"url": "https://example.com/app-setup.exe#/dl.7z",
"pre_install": "Remove-Item \"$dir\`$*\", \"$dir\uninstall.exe\" -Force -Recurse -ErrorAction SilentlyContinue"
```

#### 3. MSI 安装包
MSI 包可能有嵌套目录，**关键：`extract_dir` 必须放在 `architecture` 内部**：
```json
"architecture": {
    "64bit": {
        "url": "https://example.com/app.msi",
        "hash": "...",
        "extract_dir": "PFiles/AppFolder"
    }
}
```

**分析 MSI 结构**：
```bash
# 查看 MSI 内部目录结构
7z l app.msi | head -50

# 或者先安装测试，查看实际解压路径
scoop install mqbucket/app-name
ls "D:\Software\Scoop\apps\app-name\current"
```

#### 4. 便携版 ZIP/7z
最简单的形式，通常不需要特殊处理：
```json
"url": "https://example.com/app-portable.zip",
"extract_dir": "app-folder"
```

### 用户数据持久化

#### Scoop persist 的限制
- `persist` 只能处理**安装目录内**的相对路径
- 不能直接使用 `$env:APPDATA` 等外部路径

#### 外部数据目录持久化方案（推荐）
使用 `post_install` 创建 Junction 链接，将外部路径指向 Scoop persist：

```json
"post_install": [
    "$source = Join-Path $env:APPDATA 'AppName'",
    "$target = Join-Path $persist_dir 'data'",
    "ensure $target",
    "",
    "if (Test-Path $source) {",
    "    $item = Get-Item -LiteralPath $source -Force",
    "    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {",
    "        Write-Host \"检测到已存在的联接点：$source，跳过创建\"",
    "        return",
    "    }",
    "    & robocopy $source $target /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null",
    "    $backup = \"$source.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')\"",
    "    Move-Item -LiteralPath $source -Destination $backup -Force",
    "}",
    "",
    "New-Item -Path $source -ItemType Junction -Value $target | Out-Null"
],
"persist": "data"
```

**效果**：
- 真实数据存储在: `scoop\apps\AppName\persist\data\`
- Junction 链接: `%APPDATA%\AppName\` → `persist\data\`

### 常见应用框架的数据存储位置

| 框架 | 默认数据路径 | 确定方式 |
|------|-------------|----------|
| Electron | `%APPDATA%\<productName>\` | 查看 `electron-builder.yml` 的 `productName` |
| Tauri v2 | `%LOCALAPPDATA%\<identifier>\` | **查看 `tauri.conf.json` 的 `identifier`（不是 productName）** |
| .NET WPF/WinForms | `%APPDATA%\<CompanyName>\<ProductName>\` | 查看 AssemblyInfo 或 app.config |
| Flutter | `%APPDATA%\<appName>\` | 查看 pubspec.yaml 或 path_provider 配置 |

### 分析项目的步骤

1. **克隆源码**：`git clone --depth 1 <repo-url>`

2. **识别技术栈**：
   - `package.json` + `electron` → Electron
   - `src-tauri/` + `tauri.conf.json` → Tauri
   - `pubspec.yaml` + `flutter` → Flutter
   - `*.csproj` → .NET

3. **查找数据存储位置**：
   - 搜索 `persist`、`localStorage`、`appDataDir`、`APPDATA` 等关键词
   - 查看配置文件（electron-builder.yml、tauri.conf.json 等）

4. **检查安装包结构**：
   ```bash
   7z l app-setup.exe | head -50
   ```

5. **测试安装**：验证目录结构和可执行文件路径

### 常见问题排查

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `Can't shim 'app.exe': File doesn't exist` | 可执行文件路径错误或 extract_dir 配置错误 | 1. 检查解压后的实际目录结构<br>2. 确认 extract_dir 在 architecture 内部<br>3. 参考 Github-Store.json 的写法 |
| `extract_dir` 不生效 | extract_dir 放在了 architecture 外部 | **必须将 extract_dir 移到 architecture.64bit 内部** |
| `Failed to extract app-64.7z` | 不存在嵌套的 7z | Tauri 等框架不需要二次解压 |
| `文件名、目录名或卷标语法不正确` | persist 使用了外部路径 | 改用 post_install + Junction 方案 |
| 哈希错误 | 开发者覆盖了同版本文件 | 重新计算哈希或等待新版本 |
| Scoop bucket 未更新 | 本地 bucket 未同步远程更改 | 在 bucket 目录执行 `git pull` |

### 测试流程注意事项

1. **提交并推送**：
   ```bash
   git add bucket/app-name.json bucket-index.html
   git commit -m "app-name: Add version x.y.z"
   git push
   ```

2. **更新本地 Scoop bucket**：
   ```bash
   cd "D:\Software\Scoop\buckets\mqbucket"
   git pull
   ```

3. **测试安装**：
   ```bash
   scoop uninstall app-name
   scoop install mqbucket/app-name
   ```

4. **验证持久化**：
   - 检查 persist 目录：`ls "D:\Software\Scoop\persist\app-name"`
   - 检查 Junction 链接（如果有）：`pwsh -Command "Get-Item -Path 'C:\Users\...\AppData\...' -Force | Format-List FullName, LinkType, Target"`

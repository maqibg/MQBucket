# Scoop Bucket 编写完整指南

> 基于官方文档和实际项目经验整理

## 目录

1. [基础概念](#1-基础概念)
2. [Manifest 结构详解](#2-manifest-结构详解)
3. [checkver 版本检测](#3-checkver-版本检测)
4. [autoupdate 自动更新](#4-autoupdate-自动更新)
5. [Hash 提取方法](#5-hash-提取方法)
6. [常见模式与最佳实践](#6-常见模式与最佳实践)
7. [开发工作流程](#7-开发工作流程)

---

## 1. 基础概念

### 什么是 Bucket？
Bucket 是一个 Git 仓库，包含一系列 JSON 文件（manifests），每个 manifest 描述一个应用的安装方式。

### 什么是 Manifest？
Manifest 是一个 JSON 文件，定义了：
- 从哪里下载应用
- 如何安装/卸载
- 如何检测新版本
- 如何自动更新

---

## 2. Manifest 结构详解

### 2.1 必需字段

```json
{
    "version": "1.0.0",           // 版本号（必需）
    "url": "https://...",         // 下载链接（必需，除非在 architecture 中定义）
    "hash": "sha256:abc..."       // 文件哈希（必需）
}
```

### 2.2 基础信息字段

```json
{
    "version": "1.0.0",
    "description": "应用的简短描述（一行）",
    "homepage": "https://example.com",
    "license": "MIT",                    // 或使用对象格式
    "license": {
        "identifier": "GPL-3.0-only",
        "url": "https://..."
    },
    "notes": "安装后的提示信息",         // 可以是字符串或数组
    "notes": [
        "第一行提示",
        "第二行提示"
    ]
}
```

### 2.3 下载与安装字段

```json
{
    "url": "https://example.com/app.zip",
    "hash": "sha256值（64位十六进制）",

    // 多架构支持
    "architecture": {
        "64bit": {
            "url": "https://.../app-x64.zip",
            "hash": "..."
        },
        "32bit": {
            "url": "https://.../app-x86.zip",
            "hash": "..."
        },
        "arm64": {
            "url": "https://.../app-arm64.zip",
            "hash": "..."
        }
    },

    // 解压设置
    "extract_dir": "app-1.0.0",          // 从压缩包中提取的目录
    "extract_to": "subfolder"            // 解压到的目标子目录
}
```

### 2.4 安装脚本字段

```json
{
    // 安装前执行
    "pre_install": [
        "if (!(Test-Path \"$persist_dir\")) { New-Item \"$persist_dir\" -ItemType Directory | Out-Null }"
    ],

    // 安装后执行
    "post_install": [
        "Write-Host '安装完成！'"
    ],

    // 自定义安装程序
    "installer": {
        "file": "setup.exe",             // 安装程序文件
        "args": ["/S", "/D=$dir"],       // 安装参数
        "keep": true                     // 安装后保留安装程序
    },

    // 使用脚本代替安装程序
    "installer": {
        "script": [
            "Expand-7zipArchive \"$dir\\nested.7z\" \"$dir\" -Removal"
        ]
    },

    // 卸载程序
    "uninstaller": {
        "file": "uninstall.exe",
        "args": ["/S"]
    },

    // 卸载前执行
    "pre_uninstall": "Stop-Process -Name 'app' -ErrorAction SilentlyContinue",

    // 卸载后执行
    "post_uninstall": "Remove-Item \"$env:APPDATA\\app\" -Recurse -Force -ErrorAction SilentlyContinue"
}
```

### 2.5 可执行文件与快捷方式

```json
{
    // 添加到 PATH 的可执行文件
    "bin": "app.exe",                    // 单个文件
    "bin": ["app.exe", "tool.exe"],      // 多个文件
    "bin": [
        ["app.exe", "myapp"],            // [原文件, 别名]
        ["app.exe", "myapp", "--flag"]   // [原文件, 别名, 默认参数]
    ],

    // 添加到 PATH 的目录
    "env_add_path": "bin",
    "env_add_path": ["bin", "tools"],

    // 设置环境变量
    "env_set": {
        "JAVA_HOME": "$dir"
    },

    // 开始菜单快捷方式
    "shortcuts": [
        ["app.exe", "应用名称"],                    // [可执行文件, 快捷方式名]
        ["app.exe", "应用名称", "--arg"],           // 带参数
        ["app.exe", "应用名称", "--arg", "icon.ico"] // 带图标
    ]
}
```

### 2.6 数据持久化

```json
{
    // 持久化文件/目录（跨版本保留）
    "persist": "data",                   // 单个目录
    "persist": ["data", "config"],       // 多个
    "persist": [
        "data",
        ["config.ini", "settings.ini"]   // [原文件名, persist中的名称]
    ]
}
```

### 2.7 依赖关系

```json
{
    "depends": "git",                    // 运行时依赖
    "depends": ["git", "nodejs"],

    "suggest": {                         // 可选建议
        "vcredist": "extras/vcredist2022"
    }
}
```

### 2.8 特殊安装类型

```json
{
    // InnoSetup 安装程序
    "innosetup": true,

    // PowerShell 模块
    "psmodule": {
        "name": "ModuleName"
    }
}
```

---

## 3. checkver 版本检测

### 3.1 GitHub 简写（最常用）

```json
{
    // 最简形式 - 自动从 releases 获取版本
    "checkver": "github",

    // 指定仓库
    "checkver": {
        "github": "https://github.com/owner/repo"
    },

    // 自定义正则（处理 v 前缀等）
    "checkver": {
        "github": "https://github.com/owner/repo",
        "regex": "v([\\d.]+)"
    }
}
```

### 3.2 网页正则匹配

```json
{
    // 从主页匹配
    "checkver": {
        "url": "https://example.com/download",
        "regex": "Version:\\s*([\\d.]+)"
    },

    // 使用命名捕获组
    "checkver": {
        "url": "https://example.com",
        "regex": "v(?<version>[\\d.]+)-(?<build>\\d+)"
    }
}
```

### 3.3 JSON API

```json
{
    "checkver": {
        "url": "https://api.github.com/repos/owner/repo/releases/latest",
        "jsonpath": "$.tag_name",
        "regex": "v([\\d.]+)"
    },

    // 多层 JSON
    "checkver": {
        "url": "https://api.example.com/versions",
        "jsonpath": "$..releases[0].version"
    }
}
```

### 3.4 自定义脚本（复杂场景）

```json
{
    "checkver": {
        "script": [
            "$page = Invoke-WebRequest 'https://example.com'",
            "$page.Content -match 'version-(\\d+\\.\\d+)'",
            "$Matches.1"
        ],
        "regex": "([\\d.]+)"
    }
}
```

### 3.5 命名捕获组的高级用法

```json
{
    "checkver": {
        "url": "https://cdn.kde.org/ci-builds/",
        "regex": "release-(?<major>[\\d.]+).*?build-(?<build>\\d+)",
        "replace": "${major}-${build}"
    }
}
```

---

## 4. autoupdate 自动更新

### 4.1 基础配置

```json
{
    "autoupdate": {
        "url": "https://example.com/app-$version.zip"
    }
}
```

### 4.2 多架构配置

```json
{
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://example.com/app-$version-x64.zip"
            },
            "32bit": {
                "url": "https://example.com/app-$version-x86.zip"
            }
        }
    }
}
```

### 4.3 版本变量

| 变量 | 说明 | 示例（版本 1.2.3） |
|------|------|-------------------|
| `$version` | 完整版本 | 1.2.3 |
| `$underscoreVersion` | 下划线分隔 | 1_2_3 |
| `$dashVersion` | 短横线分隔 | 1-2-3 |
| `$cleanVersion` | 无分隔符 | 123 |
| `$majorVersion` | 主版本 | 1 |
| `$minorVersion` | 次版本 | 2 |
| `$patchVersion` | 补丁版本 | 3 |
| `$preReleaseVersion` | 预发布版本 | beta1 |

### 4.4 URL 变量

| 变量 | 说明 |
|------|------|
| `$url` | 完整下载 URL |
| `$baseurl` | URL 的基础部分（去除文件名） |
| `$basename` | 文件名（不含路径） |

### 4.5 捕获组变量

```json
{
    "checkver": {
        "regex": "v(?<major>\\d+)\\.(?<minor>\\d+)"
    },
    "autoupdate": {
        "url": "https://example.com/release-$matchMajor/app-$version.zip"
    }
}
```

### 4.6 动态 extract_dir

```json
{
    "autoupdate": {
        "url": "https://example.com/app-$version.zip",
        "extract_dir": "app-$version"
    }
}
```

---

## 5. Hash 提取方法

### 5.1 直接下载计算（默认）

如果不指定 hash 配置，autoupdate 会下载文件并计算 SHA256。

### 5.2 从 .sha256 文件获取

```json
{
    "autoupdate": {
        "url": "https://example.com/app-$version.zip",
        "hash": {
            "url": "$url.sha256"
        }
    }
}
```

### 5.3 从 checksums 文件正则提取

```json
{
    "autoupdate": {
        "hash": {
            "url": "$baseurl/checksums.txt",
            "regex": "$sha256\\s+$basename"
        }
    }
}
```

### 5.4 从 JSON 提取

```json
{
    "autoupdate": {
        "hash": {
            "mode": "json",
            "url": "https://api.example.com/hashes.json",
            "jsonpath": "$.files['$basename'].sha256"
        }
    }
}
```

### 5.5 从 XML 提取

```json
{
    "autoupdate": {
        "hash": {
            "mode": "xpath",
            "url": "https://example.com/meta.xml",
            "xpath": "//file[@name='$basename']/@sha256"
        }
    }
}
```

### 5.6 SourceForge 自动检测

SourceForge URL 会自动提取 SHA1 哈希，无需配置：

```json
{
    "autoupdate": {
        "url": "https://downloads.sourceforge.net/project/app/v$version/app-$version.zip"
    }
}
```

### 5.7 FossHub 自动检测

FossHub URL 同样自动处理。

---

## 6. 常见模式与最佳实践

### 6.1 处理 NSIS 安装程序

```json
{
    "url": "https://example.com/setup.exe#/dl.7z",
    "pre_install": [
        "Expand-7zipArchive \"$dir\\`$PLUGINSDIR\\app.7z\" \"$dir\" -Removal",
        "Remove-Item \"$dir\\`$*\" -Force -Recurse -ErrorAction SilentlyContinue"
    ]
}
```

### 6.2 处理 MSI 安装程序

```json
{
    "url": "https://example.com/app.msi",
    "installer": {
        "script": [
            "$msi = \"$dir\\$(fname $url)\"",
            "Invoke-ExternalCommand msiexec @('/a', $msi, '/qn', \"TARGETDIR=$dir\") -RunAs | Out-Null",
            "Remove-Item $msi"
        ]
    }
}
```

### 6.3 Junction 链接持久化外部数据

```json
{
    "installer": {
        "script": [
            "Import-Module $(Join-Path $(Find-BucketDirectory -Root -Name bucketname) scripts/AppsUtils.psm1)",
            "Mount-ExternalRuntimeData -Source \"$persist_dir\\data\" -Target \"$env:APPDATA\\AppName\""
        ]
    },
    "uninstaller": {
        "script": [
            "Import-Module $(Join-Path $(Find-BucketDirectory -Root -Name bucketname) scripts/AppsUtils.psm1)",
            "Dismount-ExternalRuntimeData -Target \"$env:APPDATA\\AppName\""
        ]
    }
}
```

### 6.4 便携模式配置

```json
{
    "pre_install": [
        "ensure $persist_dir",
        "if (!(Test-Path \"$persist_dir\\config.ini\")) {",
        "    New-Item \"$persist_dir\\config.ini\" -ItemType File | Out-Null",
        "}",
        "\"portable_mode=true\" | Out-File \"$dir\\portable.ini\" -Encoding utf8"
    ],
    "persist": "config.ini"
}
```

### 6.5 处理带版本号的 extract_dir

```json
{
    "extract_dir": "app-1.0.0",
    "checkver": "github",
    "autoupdate": {
        "url": "https://github.com/owner/repo/releases/download/v$version/app-$version.zip",
        "extract_dir": "app-$version"
    }
}
```

### 6.6 多文件下载

```json
{
    "url": [
        "https://example.com/app.zip",
        "https://example.com/plugin.zip"
    ],
    "hash": [
        "hash1...",
        "hash2..."
    ]
}
```

---

## 7. 开发工作流程

### 7.1 创建新 Manifest

1. 复制模板：
```bash
cp bucket/app-name.json.template bucket/myapp.json
```

2. 填写基本信息（version, description, homepage, license）

3. 添加下载链接和哈希值

4. 配置 checkver 和 autoupdate

5. 格式化并测试

### 7.2 获取文件哈希

```powershell
# 下载并计算哈希
(Get-FileHash -Algorithm SHA256 "app.zip").Hash.ToLower()

# 或使用 checkver 自动更新
pwsh -File bin/checkver.ps1 myapp -u
```

### 7.3 验证 Manifest

```bash
# 格式化 JSON
pwsh -File bin/formatjson.ps1

# 运行测试
pwsh -File bin/test.ps1

# 检查 URL 有效性
pwsh -File bin/checkurls.ps1 myapp

# 检查哈希值
pwsh -File bin/checkhashes.ps1 myapp
```

### 7.4 测试 autoupdate

```powershell
# 模拟版本更新（修改 version 为旧版本后执行）
pwsh -File bin/checkver.ps1 myapp -u

# 强制更新
pwsh -File bin/checkver.ps1 myapp -f -u
```

### 7.5 本地安装测试

```powershell
# 添加本地 bucket
scoop bucket add mqbucket D:\Code\codeSpace\MQBucket

# 安装应用
scoop install mqbucket/myapp

# 检查安装
scoop info mqbucket/myapp

# 卸载
scoop uninstall myapp
```

---

## 可用变量参考

| 变量 | 说明 |
|------|------|
| `$dir` | 应用安装目录 |
| `$persist_dir` | 持久化数据目录 |
| `$version` | 应用版本 |
| `$app` | 应用名称 |
| `$architecture` | 当前架构 (32bit/64bit/arm64) |
| `$fname` | 下载的文件名 |
| `$url` | 下载 URL |
| `$global` | 是否全局安装 |

---

## 参考资源

- [App Manifests Wiki](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
- [App Manifest Autoupdate Wiki](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifest-Autoupdate)
- [Creating an app manifest](https://github.com/ScoopInstaller/scoop/wiki/Creating-an-app-manifest)
- [Scoop Schema (JSON Schema)](https://github.com/ScoopInstaller/scoop/blob/master/schema.json)

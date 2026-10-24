<#
.SYNOPSIS
  一键设置本机 Android 工具链环境变量（点源执行，仅当前进程有效）
.EXAMPLE
  . .\scripts\env.ps1
#>
$ErrorActionPreference = 'Stop'

# ---- adb / platform-tools ----
$adb = $env:ADB
if (-not $adb) {
  $sdkRoots = @($env:ANDROID_SDK, "$env:LOCALAPPDATA\Android\Sdk", 'C:\Android\Sdk')
  foreach ($s in $sdkRoots) {
    $c = Join-Path $s 'platform-tools\adb.exe'
    if (Test-Path $c) { $adb = $c; break }
  }
}
if (-not $adb) { $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if ($adb) { $env:ADB = $adb; $env:PATH = "$(Split-Path $adb);$env:PATH" }

# ---- build-tools (zipalign / apksigner / aapt) ----
if ($adb) {
  $sdk = Split-Path (Split-Path $adb)
  $bt = Join-Path $sdk 'build-tools'
  if (Test-Path $bt) {
    $latest = Get-ChildItem $bt -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) { $env:PATH = "$($latest.FullName);$env:PATH" }
  }
}

# ---- JDK ----
$java = $env:JAVA_HOME
if (-not $java) {
  foreach ($c in @('G:\DeepSeek Harness\Tool\jdk-17','C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot')) {
    if (Test-Path (Join-Path $c 'bin\java.exe')) { $java = $c; break }
  }
}
if ($java) { $env:JAVA_HOME = $java; $env:PATH = "$java\bin;$env:PATH" }

# ---- apktool ----
$apktool = $env:APKTOOL_HOME
if (-not $apktool) {
  foreach ($c in @('G:\DeepSeek Harness\Root\tools\apktool','G:\DeepSeek Harness\Tool\apktool')) {
    if (Test-Path (Join-Path $c 'apktool.bat')) { $apktool = $c; break }
  }
}
if ($apktool) { $env:APKTOOL_HOME = $apktool; $env:PATH = "$apktool;$env:PATH" }

# ---- Python Scripts (frida / objection) ----
$pyScripts = $env:PY_SCRIPTS
if (-not $pyScripts) {
  $cands = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Directory -ErrorAction SilentlyContinue |
           ForEach-Object { Join-Path $_.FullName 'Scripts' } | Where-Object { Test-Path $_ }
  if ($cands) { $pyScripts = $cands[-1] }
}
if ($pyScripts) { $env:PY_SCRIPTS = $pyScripts; $env:PATH = "$pyScripts;$env:PATH" }

# ---- 本机额外工具 ----
$extra = 'G:\DeepSeek Harness\Root\tools'
if (Test-Path $extra) { $env:PATH = "$extra;$env:PATH" }

Write-Host "[env] adb        : $adb"
Write-Host "[env] JAVA_HOME  : $java"
Write-Host "[env] apktool    : $apktool"
Write-Host "[env] py-scripts : $pyScripts"
Write-Host '[env] PATH 已更新（仅当前进程）'
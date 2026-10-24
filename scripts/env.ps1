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
  $sdkRoots = @($env:ANDROID_SDK, $env:ANDROID_HOME,
                 (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
                 (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk'),
                 'C:\Android\Sdk') | Where-Object { $_ }
  foreach ($s in $sdkRoots) {
    $c = Join-Path $s 'platform-tools\adb.exe'
    if (Test-Path $c) { $adb = $c; break }
  }
}
if (-not $adb) { $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $adb) {
  Write-Host '[env] ⚠ 找不到 adb。请设置 $env:ANDROID_SDK 或把 platform-tools 加进 PATH' -ForegroundColor Red
} else {
  $env:ADB = $adb
  $env:PATH = "$(Split-Path $adb);$env:PATH"
}

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
if (-not ($java -and (Test-Path (Join-Path $java 'bin\java.exe')))) { $java = $null }
if (-not $java) {
  $cands = @('G:\DeepSeek Harness\Tool\jdk-17',
             'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot') | Where-Object { $_ }
  $adopt = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like 'jdk-17*' } | Select-Object -First 1
  if ($adopt) { $cands += $adopt.FullName }
  foreach ($c in $cands) { if (Test-Path (Join-Path $c 'bin\java.exe')) { $java = $c; break } }
}
if ($java) { $java = $java.TrimEnd('\\'); $env:JAVA_HOME = $java; $env:PATH = "$java\bin;$env:PATH" }

# ---- apktool ----
$apktool = $env:APKTOOL_HOME
if (-not ($apktool -and (Test-Path (Join-Path $apktool 'apktool.bat')))) { $apktool = $null }
if (-not $apktool) {
  foreach ($c in @('G:\DeepSeek Harness\Root\tools\apktool','G:\DeepSeek Harness\Tool\apktool')) {
    if (Test-Path (Join-Path $c 'apktool.bat')) { $apktool = $c; break }
  }
}
if ($apktool) { $env:APKTOOL_HOME = $apktool; $env:PATH = "$apktool;$env:PATH" }

# ---- Python Scripts (frida / objection) ----
$pyScripts = $env:PY_SCRIPTS
if (-not ($pyScripts -and (Test-Path (Join-Path $pyScripts 'frida-ps.exe')))) { $pyScripts = $null }
if (-not $pyScripts) {
  $base = Join-Path $env:LOCALAPPDATA 'Programs\Python'
  if (Test-Path $base) {
    $cands = Get-ChildItem $base -Directory | ForEach-Object { Join-Path $_.FullName 'Scripts' } |
             Where-Object { Test-Path (Join-Path $_ 'frida-ps.exe') }
    if ($cands) { $pyScripts = @($cands)[-1] }
  }
}
if ($pyScripts) { $env:PY_SCRIPTS = $pyScripts; $env:PATH = "$pyScripts;$env:PATH" }

# ---- 本项目自带工具 ----
$extra = 'G:\DeepSeek Harness\Root\tools'
if (Test-Path $extra) { $env:PATH = "$extra;$env:PATH" }

Write-Host "[env] adb        : $adb"
Write-Host "[env] JAVA_HOME  : $java"
Write-Host "[env] apktool    : $apktool"
Write-Host "[env] py-scripts : $pyScripts"
Write-Host '[env] PATH 已更新（仅当前进程）'
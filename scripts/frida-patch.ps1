<#
.SYNOPSIS
  Frida Gadget 打补丁 —— 本机 frida-server 不可用（华为锁 SELinux），
  这是唯一可用的 Frida 路线：把 gadget 直接打进 APK。
.EXAMPLE
  .\scripts\frida-patch.ps1 -Package com.example.app -Install
#>
param(
  [string]$Package,
  [string]$Apk,
  [string]$OutDir = 'G:\DeepSeek Harness\Root\capture\frida',
  [switch]$Install,
  [switch]$NoNetSec
)
$ErrorActionPreference = 'Stop'
$ADB = $env:ADB; if (-not $ADB) { $ADB = (Get-Command adb).Source }
$devArg = if ($env:PHONE_SERIAL) { @('-s', $env:PHONE_SERIAL) } else { @() }
if (-not $env:PY_SCRIPTS) { throw '请先执行 . .\scripts\env.ps1' }
$OBJ = Join-Path $env:PY_SCRIPTS 'objection.exe'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $Apk) {
  if (-not $Package) { throw '必须指定 -Package 或 -Apk' }
  $remote = ((& $ADB @devArg shell "pm path $Package") -join '') -replace '^package:', ''
  $remote = $remote.Trim()
  if (-not $remote) { throw "设备上找不到 $Package" }
  $Apk = Join-Path $OutDir "$Package.apk"
  & $ADB @devArg pull $remote $Apk
}

$extra = if ($NoNetSec) { @() } else { @('-N') }
& $OBJ patchapk -s $Apk -a arm64-v8a @extra

$patched = Join-Path (Split-Path $Apk) ((Split-Path $Apk -Leaf) -replace '\.apk$', '.objection.apk')
if (Test-Path $patched) { Write-Host "补丁完成: $patched" -ForegroundColor Green }

if ($Install -and $Package) {
  & $ADB @devArg uninstall $Package
  & $ADB @devArg install $patched
  Write-Host "已安装。启动后执行: objection -g $Package explore" -ForegroundColor Green
} elseif ($Package) {
  Write-Host '手动安装：' -ForegroundColor Yellow
  Write-Host "  adb uninstall $Package"
  Write-Host "  adb install '$patched'"
  Write-Host "  objection -g $Package explore    # 进去后敲: android sslpinning disable"
}
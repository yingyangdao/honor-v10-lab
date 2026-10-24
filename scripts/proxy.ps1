<#
.SYNOPSIS
  手机代理抓包环境 —— 用 adb reverse 把电脑代理端口映射到手机 127.0.0.1
  （手机与电脑不在同一网段时，这是唯一可行的办法）
.EXAMPLE
  .\scripts\proxy.ps1 on 8080
  .\scripts\proxy.ps1 off
#>
param(
  [Parameter(Position=0)][string]$Action = 'status',
  [int]$Port = 8080
)
$ErrorActionPreference = 'Stop'
$ADB = $env:ADB; if (-not $ADB) { $ADB = (Get-Command adb).Source }
$devArg = if ($env:PHONE_SERIAL) { @('-s', $env:PHONE_SERIAL) } else { @() }

switch ($Action.ToLower()) {
  'on' {
    & $ADB @devArg reverse "tcp:$Port" "tcp:$Port"
    & $ADB @devArg shell "settings put global http_proxy 127.0.0.1:$Port"
    Write-Host "代理已开启: 手机 -> 127.0.0.1:$Port -> 电脑:$Port" -ForegroundColor Green
    Write-Host "别忘了让电脑上的 mitmproxy/Charles/Fiddler 监听 $Port" -ForegroundColor Yellow
  }
  'off' {
    & $ADB @devArg shell 'settings put global http_proxy :0'
    Write-Host '代理已关闭' -ForegroundColor Green
  }
  default {
    Write-Host '== 手机代理 ==' -ForegroundColor Cyan; & $ADB @devArg shell 'settings get global http_proxy'
    Write-Host '== reverse ==' -ForegroundColor Cyan; & $ADB @devArg reverse --list
    Write-Host '== forward ==' -ForegroundColor Cyan; & $ADB @devArg forward --list
  }
}
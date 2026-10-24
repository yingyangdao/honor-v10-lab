<#
.SYNOPSIS
  荣耀V10（BKL-AL20）设备控制台 —— 日常调试/查询一站式封装
.EXAMPLE
  . .\scripts\env.ps1
  .\scripts\phone.ps1 status
  .\scripts\phone.ps1 su "id"
#>
param(
  [Parameter(Position=0)][string]$Action = 'status',
  [Parameter(Position=1, ValueFromRemainingArguments=$true)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
if (-not $env:ADB) { $env:ADB = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $env:ADB) { throw '找不到 adb，请先执行 . .\scripts\env.ps1' }
$ADB = $env:ADB
$devArg = if ($env:PHONE_SERIAL) { @('-s', $env:PHONE_SERIAL) } else { @() }
function Sh([string]$c)     { & $ADB @devArg shell $c }
function ShRoot([string]$c) { & $ADB @devArg shell "su -c '$c'" }

switch ($Action.ToLower()) {
  'status' {
    Write-Host '== devices ==' -ForegroundColor Cyan; & $ADB devices -l
    Write-Host '== 基本信息 ==' -ForegroundColor Cyan
    Sh "getprop ro.product.model; getprop ro.build.display.id; getprop ro.build.version.release"
    Write-Host '== Bootloader 真实状态（读 /proc/cmdline；getprop 的值被 Magisk 伪装过）==' -ForegroundColor Cyan
    $cmdline = ((Sh "su -c 'cat /proc/cmdline'") -join ' ')
    foreach ($k in @('bootlock','userlock','androidboot.verifiedbootstate','androidboot.veritymode')) {
      $m = [regex]::Match($cmdline, ($k + '=(\S+)'))
      if ($m.Success) { Write-Host ('  ' + $k.PadRight(32) + ' = ' + $m.Groups[1].Value) }
    }
    Write-Host '== getprop（已被伪装，不可信）==' -ForegroundColor DarkGray
    Sh "getprop ro.boot.flash.locked; getprop ro.boot.verifiedbootstate"
    Write-Host '== Root ==' -ForegroundColor Cyan; ShRoot 'id'
    Write-Host '== Magisk ==' -ForegroundColor Cyan; ShRoot 'magisk -v; magiskhide --status'
    Write-Host '== 模块 ==' -ForegroundColor Cyan; ShRoot 'ls /data/adb/modules'
    Write-Host '== 第三方应用 ==' -ForegroundColor Cyan; Sh 'pm list packages -3'
    Write-Host '== 已冻结 ==' -ForegroundColor Cyan; Sh 'pm list packages -d'
    Write-Host '== 负载 ==' -ForegroundColor Cyan; Sh 'uptime'
  }
  'su'      { ShRoot ($Rest -join ' ') }
  'sh'      { Sh ($Rest -join ' ') }
  'shell'   { & $ADB @devArg shell }
  'modules' { ShRoot "for m in /data/adb/modules/*/module.prop; do echo == \$m; grep -E '^(id|name|version)=' \$m; done" }
  'apps'    { Sh 'pm list packages -3' }
  'reboot'  { & $ADB @devArg reboot; Write-Host '已发送重启' }
  'push'    { & $ADB @devArg push $Rest[0] $Rest[1] }
  'pull'    { & $ADB @devArg pull $Rest[0] $Rest[1] }
  'install' {
    $zip = $Rest[0]
    if (-not (Test-Path $zip)) { throw "找不到 $zip" }
    & $ADB @devArg push $zip /data/local/tmp/_mod.zip
    & $ADB @devArg push (Join-Path $PSScriptRoot 'install-module.sh') /data/local/tmp/inst.sh
    ShRoot 'sh /data/local/tmp/inst.sh /data/local/tmp/_mod.zip'
  }
  'ssh' {
    & $ADB @devArg forward tcp:8022 tcp:8022
    Write-Host '端口转发已建立，连接 127.0.0.1:8022（用户名 u0_a123）' -ForegroundColor Green
    & ssh -p 8022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL u0_a123@127.0.0.1
  }
  default {
    Write-Host '用法: phone.ps1 <动作> [参数]' -ForegroundColor Yellow
    Write-Host '  status / su <命令> / sh <命令> / shell / modules / apps'
    Write-Host '  install <zip> / push <本地> <远端> / pull <远端> <本地> / ssh / reboot'
  }
}
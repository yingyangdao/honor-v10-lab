<#
.SYNOPSIS
  被动抓包（tcpdump）—— 抓手机所有网卡流量，导出 pcap 给 Wireshark
.EXAMPLE
  .\scripts\capture.ps1 start
  .\scripts\capture.ps1 stop
#>
param(
  [Parameter(Position=0)][string]$Action = 'help',
  [string]$Out = 'G:\DeepSeek Harness\Root\capture\cap.pcap',
  [string]$Filter = ''
)
$ErrorActionPreference = 'Stop'
$ADB = $env:ADB; if (-not $ADB) { $ADB = (Get-Command adb).Source }
$devArg = if ($env:PHONE_SERIAL) { @('-s', $env:PHONE_SERIAL) } else { @() }
$TCPDUMP = '/data/data/com.termux/files/usr/bin/tcpdump'
$LDPATH  = '/data/data/com.termux/files/usr/lib'
$REMOTE  = '/sdcard/_cap.pcap'

switch ($Action.ToLower()) {
  'start' {
    & $ADB @devArg shell "su -c 'pkill -f tcpdump; rm -f $REMOTE; LD_LIBRARY_PATH=$LDPATH nohup $TCPDUMP -i any -s 0 -w $REMOTE $Filter >/dev/null 2>&1 &'"
    Start-Sleep -Seconds 2
    & $ADB @devArg shell "su -c 'ps -A | grep tcpdump'"
    Write-Host '抓包已开始。停止: .\scripts\capture.ps1 stop' -ForegroundColor Green
  }
  'stop' {
    & $ADB @devArg shell "su -c 'pkill -f tcpdump'"
    Start-Sleep -Seconds 2
    New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
    & $ADB @devArg pull $REMOTE $Out
    Write-Host "已保存到 $Out —— 用 Wireshark 打开" -ForegroundColor Green
  }
  'live' { & $ADB @devArg shell "su -c 'LD_LIBRARY_PATH=$LDPATH $TCPDUMP -i any -nn $Filter'" }
  default {
    Write-Host '用法: capture.ps1 <start|stop|live> [-Out 路径] [-Filter 表达式]' -ForegroundColor Yellow
    Write-Host '过滤例子: "port 443" / "host 1.2.3.4" / "tcp and not port 22"'
  }
}
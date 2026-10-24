@echo off
REM 连接手机 Termux 的 SSH（自动建立 adb 端口转发）
"C:\Users\wangyang\AppData\Local\Android\Sdk\platform-tools\adb.exe" -s P7CDU18425013192 forward tcp:8022 tcp:8022 >nul 2>&1
echo 正在连接 Termux (端口 8022)...
ssh termux

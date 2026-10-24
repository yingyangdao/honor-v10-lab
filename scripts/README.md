# scripts/ 脚本索引

> 先点源 `env.ps1` 设置环境变量（每条 pwsh 命令都是新进程，变量不跨命令保留）。

```powershell
cd 'G:\DeepSeek Harness\Root'
. .\scripts\env.ps1
```

| 脚本 | 作用 | 例子 |
|---|---|---|
| `env.ps1` | 一键把 adb / build-tools / JDK / apktool / frida 加进 PATH | `. .\scripts\env.ps1` |
| `phone.ps1` | 设备控制台：状态、root、模块、应用、推拉、SSH | `.\scripts\phone.ps1 status` |
| `capture.ps1` | tcpdump 被动抓包（启停 + 拉回电脑） | `.\scripts\capture.ps1 start` |
| `proxy.ps1` | 用 `adb reverse` 开代理抓包（跨网段可用） | `.\scripts\proxy.ps1 on 8080` |
| `frida-patch.ps1` | Frida Gadget 打补丁（本机唯一可用的 Frida 路线） | `.\scripts\frida-patch.ps1 -Package com.x.y` |
| `install-module.sh` | 手机端 Magisk 模块安装器（兼容 Magisk 20.1） | `.\scripts\phone.ps1 install mod.zip` |

## 常见组合

```powershell
# 看设备状态
.\scripts\phone.ps1 status

# 抓一个 App 的 HTTPS 明文
.\scripts\proxy.ps1 on 8080              # 另开窗口: mitmweb --listen-port 8080
.\scripts\frida-patch.ps1 -Package com.target.app -Install

# 抓不走代理的流量
.\scripts\capture.ps1 start
.\scripts\capture.ps1 stop               # 自动拉回 capture\cap.pcap
```
---
name: honor-v10-lab
description: 荣耀V10(BKL-AL20)安卓实验机（G:\DeepSeek Harness\Root）：已 Root 的 EMUI 9.1 备用机，长期插在电脑上做开发/调试/抓包/破解。提供设备控制台脚本、抓包链路、Frida Gadget 注入、Magisk 模块安装器，以及华为 EMUI 专属坑的解决方案
whenToUse: 需要用这台荣耀V10做任何事时——查设备状态、执行 root 命令、抓 HTTPS 包、绕 SSL Pinning、装 Magisk 模块、SSH 登录手机、分析 App、刷机救砖、查华为机型踩坑
---

# 荣耀V10 安卓实验机（G:\DeepSeek Harness\Root）

一台**已经 Root 好、长期插在电脑上**的荣耀V10，当开发/调试/抓包/破解的实验机用。

## 设备档案

| 项 | 值 |
|---|---|
| 型号 | HONOR BKL-AL20（荣耀V10） |
| 芯片 | 海思麒麟 970（arm64-v8a） |
| 系统 | Android 9 / EMUI 9.1.0.337(C00E333R1P1) |
| 安全补丁 | 2019-12-01 |
| 序列号 | P7CDU18425013192 |
| Bootloader | **已解锁**（`ro.boot.flash.locked=0`） |
| Root | **Magisk 20.1**（装在 `recovery_ramdisk`，本机没有独立 boot 分区） |
| SELinux | Enforcing（**华为锁死了策略写接口**） |

## ⚠️ 五条铁律（违反必翻车）

1. **`pm` / `am` / `settings` 不能用 root 跑** —— 会报 `Failed transaction (2147483646)`。
   必须用 shell 身份：`adb shell pm ...`（不要 `su -c 'pm ...'`）
2. **frida-server 用不了** —— 华为锁 SELinux，改用 **Frida Gadget**（`objection patchapk`）
3. **别用 Magisk Manager 的「安装/修复运行环境」** —— 本机没 boot 分区，会把 recovery_ramdisk 搞坏
4. **别用 `magisk --sqlite` 跑带子查询的 SQL** —— 会把 magiskd 搞崩，root 全失效
5. **toybox 的 `dd` 不认 `bs=1M`** —— 写 `bs=1048576`

## 快速上手（每个新会话第一步）

```powershell
cd 'G:\DeepSeek Harness\Root'
. .\scripts\env.ps1              # 把 adb / JDK17 / apktool / frida 加进 PATH
.\scripts\phone.ps1 status        # 看设备状态
```

## 现成脚本（G:\DeepSeek Harness\Root\scripts\）

| 脚本 | 作用 |
|---|---|
| `env.ps1` | 一键设置工具链环境变量（必须点源执行） |
| `phone.ps1` | 设备控制台：`status` / `su <cmd>` / `sh <cmd>` / `modules` / `apps` / `install <zip>` / `push` / `pull` / `ssh` / `reboot` |
| `capture.ps1` | tcpdump 被动抓包：`start` / `stop` / `live` |
| `proxy.ps1` | `adb reverse` 代理抓包（跨网段可用）：`on <port>` / `off` / `status` |
| `frida-patch.ps1` | Frida Gadget 打补丁：`-Package <包名> -Install` |
| `install-module.sh` | 手机端 Magisk 模块安装器（兼容 Magisk 20.1） |

## 常见任务怎么做

### 查设备 / 执行 root 命令
```powershell
.\scripts\phone.ps1 status
.\scripts\phone.ps1 su "ls /data/adb/modules"
.\scripts\phone.ps1 su "magisk -v"
```

### 抓某个 App 的 HTTPS 明文
```powershell
.\scripts\proxy.ps1 on 8080
# 另开窗口：mitmweb --listen-port 8080
# 手机上操作 App
```

### 绕 SSL Pinning
```powershell
.\scripts\frida-patch.ps1 -Package com.target.app -Install
# 手机启动 App 后：
objection -g com.target.app explore
# 进去敲：android sslpinning disable
```

### 抓不走代理的流量
```powershell
.\scripts\capture.ps1 start
.\scripts\capture.ps1 stop     # 拉回 capture\cap.pcap
```

### 装 Magisk 模块
```powershell
.\scripts\phone.ps1 install .\mod.zip
adb reboot
```

### SSH 登录手机（当服务器用）
```powershell
.\scripts\phone.ps1 ssh        # 自动建 tcp:8022 转发并登录
# 用户名 u0_a123 / 密码 termux2026 / 端口 8022
```

## 手机里已装的东西

| 应用 | 包名 | 用途 |
|---|---|---|
| Magisk Manager | `com.topjohnwu.magisk` | Root 管理、模块、MagiskHide |
| EdXposed Manager | `org.meowcat.edxposed.manager` | Xposed 模块（框架已激活） |
| AdAway | `org.adaway` | 全机去广告（7.1 万条规则） |
| Termux | `com.termux` | 终端 + SSH + tcpdump |
| Termux:Boot | `com.termux.boot` | 开机自动跑脚本 |
| MT管理器 | `bin.mt.plus` | Root 文件管理 |

**Magisk 模块**：`busybox-ndk` / `MagiskHidePropsConf` / `cacerts` / `hosts` / `riru-core` / `riru_edxposed`

## 关键路径

| 东西 | 路径 |
|---|---|
| 系统 CA 证书 | `/system/etc/security/cacerts/037aaf60.0`（mitmproxy CA） |
| 证书模块 | `/data/adb/modules/cacerts/` |
| tcpdump | `/data/data/com.termux/files/usr/bin/tcpdump` |
| frida-server | `/data/adb/frida/frida-server`（**装了但用不了**） |
| Magisk 工具集 | `/data/adb/magisk/` |
| 开机脚本 | `/data/adb/service.d/` |
| 分区备份 | 手机 `/sdcard/hw_backup/`，电脑 `phone_backup\` |

## 分区表（本机没有 boot）

```
kernel           -> /dev/block/sdd38
recovery_ramdisk -> /dev/block/sdd40    ← Magisk 在这里
fastboot         -> /dev/block/sdd28
oeminfo          -> /dev/block/sdd6     ← 解锁状态
nvme             -> /dev/block/sdd4
vbmeta           -> /dev/block/sdd49
userdata         -> /dev/block/sdd64
```

## 详细文档（G:\DeepSeek Harness\Root\docs\）

| 文档 | 什么时候看 |
|---|---|
| `00-快速开始.md` | 第一次用 |
| `04-Magisk完全指南.md` | 模块原理、排障 |
| `06-功能入口与控制手册.md` | 某个功能在哪、怎么开关 |
| `07-抓包能力配置与验证.md` | 证书、Pinning、tcpdump |
| `08-Frida与抓包完全教程.md` | Frida Gadget / objection 实战 |
| `14-踩坑记录.md` | **遇到任何奇怪问题先查这个** |

## 华为 EMUI 专属坑速查

| 症状 | 原因 | 解法 |
|---|---|---|
| `Failed transaction (2147483646)` | 用 root 跑了 `pm`/`am` | 改用 `adb shell pm ...` |
| `Unable to save SELinux policy` | 华为锁 SELinux | 用 Frida Gadget，别用 frida-server |
| `setenforce: Invalid argument` | 同上 | 别折腾 |
| `No daemon is currently running!` | magiskd 崩了 | 重启手机 |
| `dd: block size '1M'` | toybox dd | `bs=1048576` |
| `E: Unable to locate package tcpdump` | 不在 Termux 主仓库 | 先 `pkg install root-repo` |
| `bad addr or host: <NULL>` | 在 magisk 域跑 Termux 程序 | 在 Termux App 里跑 |
| ssh 密钥认证 Permission denied | Windows OpenSSH 9.5 的 hostbound bug | 用密码或 `tools\plink.exe` |
| 手机很卡 / 点不动 | SD 卡媒体文件被反复扫描 | SD 卡根目录放 `.nomedia` |
| 模块装不上 `Please install Magisk v20.4+` | 20.1 缺 `install_module` | 用 `scripts/install-module.sh` |

## 注意事项

- **不要**升级 Magisk 到 24+：本机没 boot 分区、没 fastboot 兜底，刷坏就失去 root
- **不要**用 Magisk Manager 的「修复运行环境」
- 抓包前先确认：证书装了没 → 代理开了没 → 有没有 Pinning → 是不是绕过代理
- 改任何系统文件都用 **Magisk 模块挂载**，不要 remount /system

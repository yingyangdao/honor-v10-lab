# 荣耀V10 (BKL-AL20) Root 与长期调试环境

> 一台 2017 年的荣耀V10，从**无法解锁的"废手机"**，变成**长期插在电脑上做开发/调试/抓包的实验机**。
> 本仓库记录了完整过程、全部踩坑、可复用脚本，以及一套 DeepSeek Harness 技能插件。

[![Device](https://img.shields.io/badge/Device-HONOR%20BKL--AL20-blue)]()
[![Android](https://img.shields.io/badge/Android-9%20%2F%20EMUI%209.1.0.337-green)]()
[![Magisk](https://img.shields.io/badge/Magisk-20.1-orange)]()
[![Root](https://img.shields.io/badge/Root-OK-success)]()
[![License](https://img.shields.io/badge/License-MIT-yellow)]()

---

## 一、这台机器现在能干什么

| 能力 | 状态 | 实现方式 |
|---|---|---|
| **Root** | ✅ | Magisk 20.1（装在 `recovery_ramdisk`，本机没有独立 boot 分区） |
| **Bootloader 解锁** | ✅ | 软件测试点（SWTP）方式，**不需要解锁码** |
| **隐藏 Root** | ✅ | MagiskHide（Magisk 20.1 时代的方案） |
| **Xposed 框架** | ✅ | EdXposed v0.5.2.2 + Riru v23.9 |
| **系统级 CA 证书** | ✅ | 自建 `cacerts` Magisk 模块（mitmproxy CA） |
| **全机去广告** | ✅ | AdAway + `hosts` 模块（7.1 万条规则） |
| **被动抓包** | ✅ | Termux tcpdump 4.99.7 |
| **Frida 注入** | ✅ | **Frida Gadget**（frida-server 在华为上不可用，见下） |
| **SSH 服务** | ✅ | Termux sshd，端口 8022 |
| **文件管理** | ✅ | MT管理器 |
| **分区备份** | ✅ | oeminfo / modem / nvm 等 12 个分区 |

---

## 二、这台机器最大的三个坑（精华）

### 坑 1：华为锁死了 SELinux 策略写接口 → frida-server 用不了

```
frida-server -v
→ Unable to save SELinux policy to the kernel: Out of memory

# 换成 Magisk 自己的工具，同样失败（证明不是 frida 的问题）
magiskpolicy --live "allow magisk magisk_file file read"
→ write failed with 12: Out of memory

setenforce 0
→ setenforce: Couldn't set enforcing status to '0': Invalid argument
```

**结论**：任何需要在运行期改 SELinux 策略的工具在华为上全部失效。
**解法**：改用 **Frida Gadget**（把 `libfrida-gadget.so` 打进 APK，不需要改 SELinux）。
参考 [frida#1039](https://github.com/frida/frida/issues/1039)。

### 坑 2：华为上 `pm` / `am` 不能用 root 跑

```bash
adb shell su -c 'pm list packages'
→ cmd: Failure calling service package: Failed transaction (2147483646)
```

**解法**：`pm` / `am` 一律用 **shell 身份**（直接 `adb shell pm ...`，不要 `su -c`）。
这个坑会让"黑域"这类靠 `pm disable` 的工具失效。

### 坑 3：`magisk --sqlite` 带子查询会把 magiskd 搞崩

```bash
adb shell su -c 'magisk --sqlite "REPLACE INTO policies (...) VALUES (...,(select ...))"'
→ read (4 != 0) failed with 0: Success
# 之后 magiskd 死亡，root 全部失效（重启后恢复）
```

**解法**：加 su 授权走 Magisk Manager 界面，别手搓 SQL。

---

## 三、目录结构

```
.
├── README.md                 ← 你在这里
├── LICENSE
├── .gitignore
├── docs/                     ← 全部文档（见下方索引）
│   └── assets/               ← 文档插图
├── scripts/                  ← 可复用脚本（见 scripts/README.md）
│   ├── env.ps1               ← 一键设置工具链环境变量
│   ├── phone.ps1             ← 设备控制台（状态/root/模块/应用/SSH）
│   ├── capture.ps1           ← tcpdump 被动抓包
│   ├── proxy.ps1             ← adb reverse 代理抓包
│   ├── frida-patch.ps1       ← Frida Gadget 打补丁
│   └── install-module.sh     ← 手机端 Magisk 模块安装器
├── skills/                   ← DeepSeek Harness 技能插件
│   └── honor-v10-lab/SKILL.md
├── tools/        (gitignore) ← 工具链：frida / apktool / plink / kirintool / hut ...
├── firmware/     (gitignore) ← 官方固件 UPDATE.APP
├── phone_backup/ (gitignore) ← 分区备份（26 个分区 + 12 个 NV 分区）
└── archive/      (gitignore) ← 探索期的一次性脚本（留档）
```

---

## 四、快速开始

### 4.1 电脑端环境

```powershell
cd 'G:\DeepSeek Harness\Root'
. .\scripts\env.ps1            # 把 adb / JDK / apktool / frida 加进 PATH
.\scripts\phone.ps1 status      # 看手机现在什么状态
```

需要预装（脚本会自动探测路径，也可用环境变量覆盖）：
- **adb**（Android SDK platform-tools）
- **JDK 17**（apktool / objection 需要）
- **Python 3.11** + `pip install frida frida-tools objection`
- **apktool**（`objection patchapk` 需要）

### 4.2 抓一个 App 的 HTTPS 明文

```powershell
# ① 让手机信任你的抓包证书（把 CA 放进 cacerts 模块，重启）
#    详见 docs/07-抓包能力配置与验证.md

# ② 开代理（手机和电脑不同网段也能用）
.\scripts\proxy.ps1 on 8080
#    另开一个窗口：mitmweb --listen-port 8080

# ③ 如果 App 有 SSL Pinning，用 Frida Gadget 解掉
.\scripts\frida-patch.ps1 -Package com.target.app -Install
#    手机上启动 App 后：objection -g com.target.app explore
#    进去敲：android sslpinning disable

# ④ 手机上操作 App，mitmweb 里就能看到明文
```

### 4.3 抓不走代理的流量

```powershell
.\scripts\capture.ps1 start
# ...操作 App...
.\scripts\capture.ps1 stop        # 自动拉回 capture\cap.pcap，用 Wireshark 打开
```

---

## 五、文档索引

| # | 文档 | 内容 |
|---|---|---|
| 00 | [快速开始](docs/00-快速开始.md) | 5 分钟上手 |
| 01 | [设备档案与 Root 方案](docs/01-设备档案与Root方案.md) | 硬件规格、分区表、解锁原理 |
| 02 | [解锁与 Root 全过程](docs/02-解锁与Root全过程.md) | SWTP 软件测试点完整流程 |
| 03 | [实施方案](docs/03-实施方案.md) | 详细实施计划 |
| 04 | [Magisk 完全指南](docs/04-Magisk完全指南.md) | 模块原理、安装、排障 |
| 05 | [模块安装报告](docs/05-模块安装报告.md) | 4 个模块的安装与验证 |
| 06 | [功能入口与控制手册](docs/06-功能入口与控制手册.md) | 每个功能在哪、怎么开关 |
| 07 | [抓包能力配置与验证](docs/07-抓包能力配置与验证.md) | 系统 CA / Pinning / tcpdump |
| 08 | [Frida 与抓包完全教程](docs/08-Frida与抓包完全教程.md) | Frida Gadget / objection 实战 |
| 09 | [固件下载渠道全网排查](docs/09-固件下载渠道全网排查.md) | 9.1.0.337 固件来源 |
| 10 | [固件 9.1.0.337 获取渠道](docs/10-固件9.1.0.337获取渠道.md) | 下载链接汇总 |
| 11 | [固件最终排查结果](docs/11-固件最终排查结果.md) | 结论 |
| 12 | [eRecovery 抓包教程](docs/12-eRecovery抓包教程.md) | 抓 eRecovery 的请求 |
| 13 | [HwOUC 逆向报告](docs/13-HwOUC逆向报告.md) | 华为 OTA 客户端分析 |
| 14 | [踩坑记录](docs/14-踩坑记录.md) | **所有坑的完整清单** |

---

## 六、关键技术备忘

### 分区布局（本机没有 `boot`，ramdisk 在 `recovery_ramdisk`）

```
kernel           -> /dev/block/sdd38
recovery_ramdisk -> /dev/block/sdd40    ← Magisk 装在这里
fastboot         -> /dev/block/sdd28
oeminfo          -> /dev/block/sdd6     ← 解锁状态存这里
nvme             -> /dev/block/sdd4
vbmeta           -> /dev/block/sdd49
userdata         -> /dev/block/sdd64
```

### Magisk 20.1 的安装模块姿势

20.1 **没有** `magisk --install-module`，必须手动跑模块 zip 里的 `update-binary`：

```sh
export BOOTMODE=true MAGISK_VER=20.1 MAGISK_VER_CODE=20100
export ARCH=arm64 IS64BIT=true API=28
export TMPDIR=/dev/tmp MAGISKTMP=/sbin/.magisk NVBASE=/data/adb
sh META-INF/com/google/android/update-binary 3 1 "$ZIP"
```

已封装成 [scripts/install-module.sh](scripts/install-module.sh)。

### 常用 adb 命令

```bash
# 查询（不要用 su！）
adb shell pm list packages -3          # 第三方应用
adb shell pm list packages -d          # 已冻结
adb shell settings get global http_proxy

# root 操作
adb shell su -c 'ls /data/adb/modules'
adb shell su -c 'magisk -v'

# 端口转发
adb forward tcp:8022 tcp:8022          # 电脑 → 手机（SSH）
adb reverse tcp:8080 tcp:8080          # 手机 → 电脑（代理抓包）
```

---

## 七、免责声明

本项目仅供**设备所有者对自己的设备**进行学习研究使用。
解锁 Bootloader、刷入 Magisk、修改系统分区会导致**保修失效**，并有一定**变砖风险**。
请务必先做完整分区备份。因使用本项目造成的任何损失，作者不承担责任。

---

## 八、License

[MIT](LICENSE)

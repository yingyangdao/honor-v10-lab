# 荣耀V10 Magisk 完全指南

> **适用设备**：HONOR BKL-AL20（荣耀V10）/ Kirin 970 / arm64-v8a
> **系统**：EMUI 9.1.0.337 / Android 9 (SDK 28) / 内核 4.9.148
> **Magisk**：v20.1 (20100) / Magisk Manager v7.5.1
> **SELinux**：Enforcing
> **编写时间**：2026-10-24

---

# 第一部分 · 原理篇

## 1.1 Magisk 到底是什么

Magisk 不是"一个 App"，而是**一套系统级改造框架**，由 4 个部分组成：

| 组件 | 位置 | 作用 |
|---|---|---|
| **magiskinit** | 打包进 recovery_ramdisk，启动时替换 \`/init\` | 最早期接管启动，挂载 magisk 分区 |
| **magiskd** | 常驻守护进程（root 身份） | 管理 root 授权、模块、Hide |
| **magisk** | 命令行工具 | 你敲的 \`magisk\` 命令 |
| **Magisk Manager** | 普通 App | 图形界面，操作上面三个 |

## 1.2 核心思想：Systemless（无系统修改）

**传统 Root（SuperSU 时代）的问题**：
\`\`\`
直接往 /system 里塞 su 二进制 → 系统分区被改 → OTA 更新失败 → 变砖
\`\`\`

**Magisk 的解法**：
\`\`\`
/system 分区一个字节都不动
    ↓
启动时用 overlayfs / bind mount 把模块文件"叠"到 /system 上
    ↓
系统以为自己看到了修改后的文件，实际磁盘上什么都没变
\`\`\`

**好处**：
- ✅ 随时可以完全卸载，系统恢复原样
- ✅ OTA 更新不会因为系统被改而失败
- ✅ 出问题拔掉模块就好，不用重刷系统

## 1.3 Magisk 启动流程（你这台机器的真实日志）

\`\`\`
① BootROM
     ↓  加载 XLOADER（我们恢复过的那个）
② XLOADER
     ↓  加载 FASTBOOT / UCE
③ fastboot → 引导内核
     ↓  读 recovery_ramdisk 里的 magiskinit（替换了原厂 /init）
④ magiskinit
     ↓  解析内核 cmdline，判断是正常启动还是 recovery
     ↓  挂载 /data，读取 /data/adb/magisk/
⑤ magiskd 启动
     ↓
   ┌─ post-fs-data 阶段（阻塞式，其他进程会等）
   │   * Initializing Magisk environment
   │   * Mounting mirrors          ← 挂载 /system /vendor /product 镜像
   │   * Setting up internal busybox
   │   * Running post-fs-data.d scripts
   │   * Running module post-fs-data scripts
   │   * Loading modules            ← 把模块文件 overlay 到系统
   │   * Starting MagiskHide        ← 启动隐藏守护
   └─
     ↓
   ┌─ late_start 阶段（非阻塞）
   │   * Running service.d scripts
   │   * Running module service scripts
   └─
     ↓
⑥ boot_complete → 系统可用
\`\`\`

**你这台机器的实际日志**（\`/cache/magisk.log\`）：
\`\`\`
Magisk v20.1(20100) daemon started
* Device API level: 28
** post-fs-data mode running
* Initializing Magisk environment
* Mounting mirrors
* Setting up internal busybox
* Running post-fs-data.d scripts
* Running module post-fs-data scripts
* Loading modules
* Starting MagiskHide
  hide_policy: Hiding sensitive props
  hide_list init: [com.google.android.gms/com.google.android.gms.unstable]
** late_start service mode running
** boot_complete triggered
\`\`\`

## 1.4 华为 EMUI 的特殊之处（非常重要）

### 普通安卓 vs 华为

| | 普通安卓 | 华为 EMUI 9 |
|---|---|---|
| boot 分区 | 有（kernel + ramdisk） | **没有** |
| recovery 分区 | 有 | **没有独立 recovery 分区** |
| ramdisk 在哪 | boot 分区里 | **recovery_ramdisk 分区** |
| Magisk 刷哪 | boot | **recovery_ramdisk** |

### 这意味着什么

\`\`\`
普通安卓:  电源键 → boot 分区 → 系统（带 Magisk）
           音量+ + 电源 → recovery 分区 → recovery

华为EMUI9: 电源键 → kernel + recovery_ramdisk → 系统（带 Magisk）
           音量+ + 电源 → kernel + recovery_ramdisk → recovery 模式
\`\`\`

**你的实测结果：正常开机（电源键）就带 Root** ✅ —— 所以不用担心"要不要按音量+"的问题。

### 华为的「双锁」机制

华为 Bootloader 有**两层锁**（这是它比其他厂商难解的原因）：

| 锁 | 存储位置 | 作用 | 解锁后 |
|---|---|---|---|
| **FBlock** | rdmode NV 项 | 控制能否刷写分区 | \`unlocked\` |
| **USER Lock** | oeminfo bootinfo NV 项 | 控制能否启动非签名镜像 | \`unlocked\` |

**你现在的状态**（\`fastboot oem check-rootinfo\`）：
\`\`\`
item: fblock,   status: unlocked, credible: Y
item: userlock, status: unlocked, credible: Y
status: RISK
\`\`\`

## 1.5 你这台机器的 Magisk 文件布局

\`\`\`
/sbin/                           ← tmpfs（内存盘，重启消失）
  magisk            149848       主二进制
  magiskinit        345412       启动 init
  magiskhide -> ./magisk         MagiskHide 入口
  magiskpolicy -> ./magiskinit   SELinux 策略工具
  su -> ./magisk                 Root 入口
  .magisk/                       运行时挂载点

/data/adb/                       ← 持久化（重启保留）
  magisk/                        ★ Magisk 工具集（我们手工重建的）
    magisk            149848
    magiskboot        303088     镜像解包/打包
    magiskinit        365892
    magiskinit64      345412
    busybox          1070668
    util_functions.sh  12988
    boot_patch.sh       6403
    addon.d.sh          2048
    magisk.apk       2095876
    chromeos/                    伪装 ChromeOS 签名工具
  magisk.db                      root 授权数据库
  modules/                       ★ 模块安装目录（当前为空）
  post-fs-data.d/                早期启动脚本
  service.d/                     后期启动脚本
\`\`\`

---

# 第二部分 · Magisk Manager 界面详解

## 2.1 首页

打开 Magisk Manager，从上到下：

| 区块 | 显示内容 | 说明 |
|---|---|---|
| **Magisk** | \`已安装 20.1 (20100)\` | 当前 Magisk 版本 |
| | \`最新版 22.1 (22100)\` + \`更新\`按钮 | ⚠️ **不要点！** 见 6.1 |
| **Magisk Manager** | \`已安装 7.5.1\` | Manager 自己的版本 |
| **MagiskHide** | 开关状态 | 隐藏 root 的总开关 |
| **系统级 hosts** | 开关状态 | AdAway 等去广告必需 |
| **保持 AVB 2.0/dm-verity** | 开关 | 见 3.7 |
| **保持强制加密** | 开关 | 见 3.7 |

## 2.2 侧边栏菜单（左上角三条杠）

\`\`\`
├─ 主页
├─ 超级用户        ← 管理 root 授权（哪些 App 能用 root）
├─ 模块            ← 安装/卸载模块
├─ 下载            ← 在线模块商店（⚠️ 已失效，见 3.2）
├─ 日志            ← 查看 magisk.log
├─ 设置
└─ 卸载 Magisk     ← 完全卸载
\`\`\`

## 2.3 设置项逐条解释

### Root 相关
| 设置 | 建议 | 说明 |
|---|---|---|
| **超级用户访问** | \`仅限应用和 ADB\` | 控制谁能用 root |
| **超级用户通知** | 开 | 有 App 请求 root 时弹提示 |
| **超级用户超时** | \`10 分钟\` | 授权有效期 |

### MagiskHide 相关
| 设置 | 建议 | 说明 |
|---|---|---|
| **MagiskHide** | 开 | 总开关 |
| **隐藏 Magisk Manager** | 按需 | 把 Manager 自己改名换图标，躲避检测 |
| **MagiskHide 应用列表** | 按需勾选 | 对哪些 App 隐藏 root |

### 系统相关
| 设置 | 建议 | 说明 |
|---|---|---|
| **系统级 hosts** | 用 AdAway 时开 | 把 /system/etc/hosts 变成可写 |
| **保持 AVB 2.0/dm-verity** | **开** | 保留 dm-verity 校验 |
| **保持强制加密** | **开** | 保留 /data 加密 |
| **核心功能模式** | 关 | 开启后禁用所有模块（救急用） |

### 其他
| 设置 | 说明 |
|---|---|
| **语言** | 可切换中文 |
| **主题** | 深色/浅色 |
| **清除 Repo 缓存** | 在线模块列表出问题时用 |

---

# 第三部分 · 核心功能实操

## 3.1 Root 权限管理

### 授予 App Root
1. App 第一次请求 root → 手机弹出提示
2. 选择：
   - **允许**（本次）— 一次性
   - **永久允许** — 记住选择
   - **拒绝**
3. 建议：**只有确定可信的 App 才给永久允许**

### 手动管理
\`\`\`
Magisk Manager → 超级用户
  ├─ 已授权列表（可以撤销）
  ├─ 被拒绝列表
  └─ 点击条目可以改变授权状态
\`\`\`

### 命令行测试 Root
\`\`\`bash
adb shell su -c id
# 期望输出: uid=0(root) gid=0(root) context=u:r:magisk:s0
\`\`\`

## 3.2 模块安装

### ⚠️ 重要：在线商店已失效

**官方模块仓库（Magisk-Modules-Repo）在 2023 年归档**，\`repo.json\` 已删除（我实测返回 404）。所以 Manager 里的「**下载**」页面会显示空白或报错。

### 正确的安装方式：手动下载 → 本地安装

\`\`\`
① 在电脑/手机浏览器打开模块的 GitHub 页面
② 下载 Release 里的 .zip 文件
③ 传到手机
④ Magisk Manager → 模块 → 「从本地安装」→ 选 zip
⑤ 重启手机
\`\`\`

### 命令行安装
\`\`\`bash
adb push module.zip /sdcard/
adb shell su -c 'magisk --install-module /sdcard/module.zip'
adb reboot
\`\`\`

### 模块目录结构
\`\`\`
/data/adb/modules/<模块ID>/
  module.prop         模块信息（名称、版本、作者）
  post-fs-data.sh     早期启动脚本
  service.sh          后期启动脚本
  system/             要 overlay 到 /system 的文件
  system.prop         要设置的属性
  uninstall.sh        卸载时执行
  disable             存在此文件 = 模块被禁用
  remove              存在此文件 = 下次重启时删除
\`\`\`

### 模块出问题怎么办（不进系统就能救）
\`\`\`bash
# 方法1：创建 disable 文件禁用模块
adb shell su -c 'touch /data/adb/modules/<模块ID>/disable'

# 方法2：创建 remove 文件删除模块
adb shell su -c 'touch /data/adb/modules/<模块ID>/remove'

# 方法3：开启核心功能模式（禁用全部模块）
adb shell su -c 'touch /cache/.disable_magisk'
adb reboot
# 关掉：adb shell su -c 'rm /cache/.disable_magisk'
\`\`\`

## 3.3 MagiskHide（隐藏 Root）

### 为什么需要
银行 App、支付宝、微信支付、游戏反作弊会检测 root，检测到就拒绝运行。

### 原理
\`\`\`
MagiskHide 会对勾选的 App 做三件事：
① 卸载 /sbin 下的 magisk 相关挂载点（该 App 看不到）
② 修改该进程的 SELinux 上下文（伪装成普通 App）
③ 隐藏敏感系统属性（ro.debuggable、ro.secure 等）
\`\`\`

### 配置步骤
\`\`\`
① Magisk Manager → 设置 → 打开 MagiskHide 开关
② 侧边栏 → MagiskHide
③ 勾选需要隐藏的 App
④ 重启手机
\`\`\`

### 验证是否生效
\`\`\`bash
# 查看当前 hide 列表
adb shell su -c 'magiskhide ls'

# 测试某个 App
adb shell su -c 'magiskhide test com.example.app'
\`\`\`

### 推荐的隐藏对象
\`\`\`
支付宝          com.eg.android.AlipayGphone
微信            com.tencent.mm
云闪付          com.unionpay
各大银行 App
三国志战略版    com.aligames.sgzzlb.huawei    ← 你装的那个游戏
Google Play 服务 com.google.android.gms
\`\`\`

## 3.4 系统级 hosts（去广告基础）

### 原理
\`\`\`
Android 的 DNS 解析会先查 /etc/hosts
把广告域名的 IP 改成 0.0.0.0 → 广告加载失败
但 /system 是只读的 → Magisk 用 bind mount 把可写的 hosts 叠上去
\`\`\`

### 开启步骤
\`\`\`
Magisk Manager → 设置 → 打开「系统级 hosts」
\`\`\`

### 验证
\`\`\`bash
adb shell su -c 'mount | grep hosts'
# 应该看到 /data/adb/modules/hosts/system/etc/hosts 挂载到 /system/etc/hosts
\`\`\`

### 之后配合 AdAway 使用
见第五部分第 21 项。

## 3.5 日志查看

\`\`\`bash
# Magisk 主日志
adb shell su -c 'cat /cache/magisk.log'

# 实时跟踪
adb shell su -c 'tail -f /cache/magisk.log'

# 模块安装日志
adb shell su -c 'cat /data/adb/magisk/install.log'
\`\`\`

## 3.6 完全卸载 Magisk

### 方法一：Manager 界面
\`\`\`
Magisk Manager → 侧边栏 → 卸载 Magisk → 完全卸载
\`\`\`

### 方法二：命令行
\`\`\`bash
adb shell su -c 'magisk --remove-modules'   # 先删模块
# 然后需要重新刷原厂 recovery_ramdisk
\`\`\`

### ⚠️ 你这台机器的特别注意
卸载后需要**重新刷原厂 recovery_ramdisk**，否则开机会卡：
\`\`\`bash
# 进 COM 1.0 → Kirin-Tool VCOM Unlock → 然后：
fastboot flash recovery_ramdisk "G:\DeepSeek Harness\Root\tools\firmware\REC_337\9.1.0.337\RECOVERY_RAMDIS.img"
fastboot reboot
\`\`\`

## 3.7 「保持 AVB 2.0 / 保持强制加密」到底要不要开

| 设置 | 开 | 关 |
|---|---|---|
| **保持 AVB 2.0/dm-verity** | 系统分区保持完整性校验 | 关闭校验（某些模块需要） |
| **保持强制加密** | /data 保持加密 | 关闭加密（性能略好，但安全性下降） |

**你的建议**：**两个都保持开启**。
- 你是日常使用，安全性更重要
- 关闭加密后如果忘记密码，数据完全暴露
- 而且你的卡死问题已经通过清理存储解决了，不需要靠关加密提升性能


---

# 第四部分 · 命令行大全

> 所有命令通过 \`adb shell su -c '命令'\` 执行，或在手机的 Termux/终端里直接执行

## 4.1 magisk 命令全集

### 信息查询
\`\`\`bash
magisk -v                      # 版本号（20.1:MAGISK）
magisk -V                      # 版本码（20100）
magisk --path                  # magisk 运行时路径
magisk --list                  # 列出内置 applet（su/resetprop/magiskhide）
magisk --sqlite "SELECT * FROM settings"    # 查询配置数据库
\`\`\`

### 模块管理
\`\`\`bash
magisk --install-module <zip路径>    # 安装模块
magisk --remove-modules              # 删除所有标记为 remove 的模块
magisk --modules                     # 列出已装模块
\`\`\`

### MagiskHide
\`\`\`bash
magiskhide enable                    # 开启 Hide
magiskhide disable                   # 关闭 Hide
magiskhide ls                        # 列出隐藏的进程
magiskhide add <包名> <进程名>        # 添加
magiskhide rm <包名> <进程名>         # 移除
magiskhide test <包名>                # 测试某 App 是否被隐藏
\`\`\`

### 属性操作（resetprop）
\`\`\`bash
resetprop                            # 列出所有属性
resetprop <属性名>                    # 读取属性
resetprop <属性名> <值>               # 设置属性（会触发 init 的 property_service）
resetprop -n <属性名> <值>            # 设置属性（不触发，直接改内存）
resetprop --delete <属性名>           # 删除属性
resetprop -p                          # 持久化（写入 /data/property）
\`\`\`

### 其他
\`\`\`bash
magisk --unlock-blocks               # 解锁被锁的块设备
magisk --remove-modules               # 清理待删模块
magisk --daemon                       # 手动启动守护进程
magisk --post-fs-data                 # 手动跑 post-fs-data 阶段
magisk --service                      # 手动跑 service 阶段
magisk --boot-complete                # 手动触发 boot_complete
\`\`\`

## 4.2 magiskboot（镜像工具）

\`\`\`bash
magiskboot unpack boot.img           # 解包镜像
    # 产出: kernel / ramdisk.cpio / dtb / second / extra
magiskboot repack boot.img           # 重新打包
magiskboot cpio ramdisk.cpio <操作>  # 操作 cpio 归档
    # ls / cat / add / rm / mkdir / extract / test / restore
    # 例: magiskboot cpio ramdisk.cpio "add 750 init magiskinit"
magiskboot compress <格式> <文件>     # 压缩（gzip/lz4/xz）
magiskboot decompress <文件>          # 解压
magiskboot hexpatch <文件> <查找> <替换>   # 十六进制补丁
magiskboot sha1 <文件>                # 计算 SHA1
magiskboot dtb <文件> patch           # 修补 dtb 里的 fstab
magiskboot cleanup                    # 清理临时文件
\`\`\`

**实用例子：备份当前 recovery_ramdisk 的 ramdisk**
\`\`\`bash
adb shell su -c 'cd /data/local/tmp && magiskboot unpack /dev/block/by-name/recovery_ramdisk'
adb shell su -c 'cp /data/local/tmp/ramdisk.cpio /sdcard/'
adb pull /sdcard/ramdisk.cpio
\`\`\`

## 4.3 实用脚本（放进 /data/adb/service.d/ 开机自动执行）

### 脚本 1：开机自动关闭华为安全扫描（省电省 CPU）
\`\`\`bash
#!/system/bin/sh
# 文件名: /data/adb/service.d/10-disable-security-scan.sh
sleep 60
pm disable com.huawei.systemmanager/.optimize.process.ProtectActivity 2>/dev/null
pm disable com.huawei.systemmanager/.mainscreen.MainScreenActivity 2>/dev/null
# 关闭病毒扫描
settings put global hw_security_scan_enabled 0 2>/dev/null
\`\`\`

### 脚本 2：开机自动清理缓存
\`\`\`bash
#!/system/bin/sh
# 文件名: /data/adb/service.d/20-clean-cache.sh
sleep 120
rm -rf /data/local/tmp/* 2>/dev/null
rm -rf /cache/* 2>/dev/null
log -t MagiskClean "cache cleaned at $(date)"
\`\`\`

### 脚本 3：性能模式（锁定大核频率）
\`\`\`bash
#!/system/bin/sh
# 文件名: /data/adb/service.d/30-perf.sh
sleep 90
# 查看可用频率
# cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
echo "schedutil" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
echo "schedutil" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor 2>/dev/null
\`\`\`

**设置权限（必须）**：
\`\`\`bash
adb shell su -c 'chmod 755 /data/adb/service.d/*.sh'
adb shell su -c 'chown root:root /data/adb/service.d/*.sh'
\`\`\`

## 4.4 华为专项命令

### 查看 rootinfo（安全账本）
\`\`\`bash
# 需要重启到 fastboot
adb reboot bootloader
fastboot oem check-rootinfo
fastboot oem get-bootinfo
\`\`\`

### 查看/修改 oeminfo
\`\`\`bash
adb shell su -c 'dd if=/dev/block/by-name/oeminfo of=/sdcard/oeminfo.img'
adb pull /sdcard/oeminfo.img
# ⚠️ 修改 oeminfo 有变砖风险，改前务必备份
\`\`\`

### 查看分区布局
\`\`\`bash
adb shell su -c 'ls -la /dev/block/by-name/'
adb shell su -c 'cat /proc/partitions'
\`\`\`

### 备份任意分区
\`\`\`bash
adb shell su -c 'dd if=/dev/block/by-name/<分区名> of=/sdcard/<分区名>.img'
adb pull /sdcard/<分区名>.img
\`\`\`


---

# 第五部分 · 100 项精选功能与设置

> **兼容性图例**
> ✅ = 你这台机器（Magisk 20.1 / Android 9 / EMUI 9.1）可直接用
> ⚠️ = 需要额外条件（会说明）
> ❌ = 不支持（需要 Zygisk / Magisk 24+ / Android 10+）

---

## 一、Root 权限与授权管理（1-10）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 1 | **超级用户授权** | 给 App root 权限 | Manager → 超级用户，App 请求时点"永久允许" | ✅ |
| 2 | **Root 授权审计** | 查看哪些 App 有 root、什么时候用的 | Manager → 超级用户 → 已授权列表 | ✅ |
| 3 | **临时授权** | 只给一次，用完失效 | 请求时选"允许"（不勾永久） | ✅ |
| 4 | **撤销 Root** | 发现可疑 App 立刻收回权限 | Manager → 超级用户 → 点条目 → 删除 | ✅ |
| 5 | **ADB Root 开关** | 控制 \`adb shell su\` 能否用 | 设置 → 超级用户访问 → "仅限应用和 ADB" | ✅ |
| 6 | **Root 请求通知** | 有 App 偷偷要 root 时弹提示 | 设置 → 超级用户通知 → 开 | ✅ |
| 7 | **授权超时** | 授权 N 分钟后自动失效 | 设置 → 超级用户超时 → 10 分钟 | ✅ |
| 8 | **多用户隔离** | 访客/分身用户不给 root | 默认行为，无需配置 | ✅ |
| 9 | **su 命令直用** | 脚本里直接调 \`su -c\` | \`su -c '命令'\` | ✅ |
| 10 | **magisk.db 备份** | 备份授权数据库 | \`su -c 'cp /data/adb/magisk.db /sdcard/'\` | ✅ |

---

## 二、MagiskHide 隐藏与对抗检测（11-20）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 11 | **MagiskHide 总开关** | 隐藏 root 的核心功能 | 设置 → MagiskHide → 开 | ✅ |
| 12 | **按 App 隐藏** | 只对特定 App 隐藏 | Manager → MagiskHide → 勾选 | ✅ |
| 13 | **隐藏 Magisk Manager 自身** | 把 Manager 改名换图标 | 设置 → 隐藏 Magisk Manager | ✅ |
| 14 | **隐藏敏感属性** | 伪装 ro.debuggable/ro.secure | MagiskHide 自动处理 | ✅ |
| 15 | **SELinux 上下文伪装** | 让被隐藏 App 看不到 magisk 域 | MagiskHide 自动处理 | ✅ |
| 16 | **卸载 /sbin 挂载点** | 对目标 App 隐藏 magisk 挂载 | MagiskHide 自动处理 | ✅ |
| 17 | **银行 App 绕过** | 让银行 App 正常运行 | 把银行 App 加入 MagiskHide 列表 | ✅ |
| 18 | **支付宝/微信支付绕过** | 让支付功能正常 | 加入 Hide 列表 | ✅ |
| 19 | **游戏反作弊绕过** | 让游戏不检测 root | 加入 Hide 列表（如三国志战略版） | ✅ |
| 20 | **MagiskHide Props Config 模块** | 改设备指纹，过 SafetyNet/Play 认证 | 装模块 → 终端跑 \`props\` 选指纹 | ✅ |

---

## 三、去广告与隐私防护（21-30）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 21 | **系统级 hosts** | 全 App 去广告的基础 | 设置 → 系统级 hosts → 开 | ✅ |
| 22 | **AdAway 去广告** | 屏蔽全网广告域名 | 装 AdAway → 启用 → 下载 hosts 源 | ✅ |
| 23 | **自定义 hosts 源** | 用国内更快的源 | AdAway → 主机源 → 加 \`https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts\` | ✅ |
| 24 | **App 内广告拦截** | 拦掉开屏/横幅广告 | AdAway + 系统级 hosts 组合 | ✅ |
| 25 | **YouTube 去广告** | 看 YT 无广告 | ⚠️ 需 YouTube Vanced（独立 App，不用 Magisk） | ⚠️ |
| 26 | **应用权限审计** | 看哪些 App 偷要权限 | 设置 → 应用 → 权限管理，或装 AppOpsX | ✅ |
| 27 | **禁用后台自启** | 阻止 App 后台偷偷跑 | 设置 → 应用启动管理 → 全部手动 | ✅ |
| 28 | **冻结预装应用** | 让预装 App 彻底不跑 | \`su -c 'pm disable-user --user 0 <包名>'\` | ✅ |
| 29 | **隐私沙盒** | 给 App 喂假数据 | 装 XPrivacyLua（需 EdXposed） | ⚠️ |
| 30 | **WiFi 密码查看** | 看已保存的 WiFi 密码 | \`su -c 'cat /data/misc/wifi/WifiConfigStore.xml'\` | ✅ |

---

## 四、系统性能与省电（31-40）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 31 | **查看 CPU 频率** | 实时看各核心频率 | \`su -c 'cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq'\` | ✅ |
| 32 | **切换 CPU 调度器** | 平衡性能/省电 | \`su -c 'echo schedutil > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor'\` | ✅ |
| 33 | **锁大核频率** | 游戏时保性能 | 写入 scaling_min_freq / scaling_max_freq | ✅ |
| 34 | **关闭华为安全扫描** | 干掉吃 194% CPU 的进程 | \`su -c 'pm disable-user --user 0 com.huawei.systemmanager'\` | ✅ |
| 35 | **关闭应用市场后台** | 阻止它偷偷下载 | \`su -c 'pm disable-user --user 0 com.huawei.appmarket'\` | ✅ |
| 36 | **查看唤醒锁** | 找出耗电元凶 | \`su -c 'dumpsys power | grep -i wake'\` | ✅ |
| 37 | **查看电池统计** | 哪个 App 最耗电 | \`su -c 'dumpsys batterystats --charged'\` | ✅ |
| 38 | **Fstrim 手动执行** | 给 UFS 做垃圾回收，提速 | \`su -c 'fstrim -v /data'\` | ✅ |
| 39 | **调整 swappiness** | 减少 swap 换入换出 | \`su -c 'echo 60 > /proc/sys/vm/swappiness'\` | ✅ |
| 40 | **清理内存缓存** | 释放缓存 | \`su -c 'sync; echo 3 > /proc/sys/vm/drop_caches'\` | ✅ |

---

## 五、存储空间管理（41-50）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 41 | **查看真实占用** | 找出谁在吃空间 | \`su -c 'du -sh /data/* 然后 sort -h'\` | ✅ |
| 42 | **清理 Dalvik 缓存** | 释放几个 GB | \`su -c 'rm -rf /data/dalvik-cache/*'\`（重启后重建） | ✅ |
| 43 | **清理应用缓存** | 批量清所有 App 缓存 | \`su -c 'pm trim-caches 999G'\` | ✅ |
| 44 | **清理日志** | 删掉系统日志 | \`su -c 'rm -rf /data/log/* /data/anr/*'\` | ✅ |
| 45 | **清理 tombstone** | 删崩溃转储 | \`su -c 'rm -rf /data/tombstones/*'\` | ✅ |
| 46 | **查找大文件** | 定位超大文件 | \`su -c 'find /data -type f -size +100M -exec ls -lh {} \\;'\` | ✅ |
| 47 | **移动 App 到 SD 卡** | 释放内置存储 | ⚠️ 需要 App2SD 类工具 + 外置卡 | ⚠️ |
| 48 | **删除预装 APK** | 彻底移除占空间预装 | \`su -c 'rm /system/app/<名字>.apk'\`（有风险，建议用 pm disable） | ⚠️ |
| 49 | **存储分析** | 图形化看空间分布 | 装 DiskUsage | ✅ |
| 50 | **定期自动清理** | 写 service.d 脚本定时清 | 见 4.3 脚本 2 | ✅ |


---

## 六、界面美化与个性化（51-60）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 51 | **换字体** | 全系统字体替换 | 装「字体模块」或 Magisk 字体模块 zip | ✅ |
| 52 | **换开机动画** | 自定义 bootanimation | 替换 \`/system/media/bootanimation.zip\` | ✅ |
| 53 | **状态栏图标定制** | 改信号/WiFi/电池图标 | 装 EMUI 主题或 Xposed 模块 | ⚠️ |
| 54 | **沉浸式状态栏** | 全屏体验 | 设置里开，或装模块 | ✅ |
| 55 | **DPI 调整** | 改界面元素大小 | \`su -c 'wm density 420'\`（默认约 480） | ✅ |
| 56 | **分辨率调整** | 省电（降分辨率） | \`su -c 'wm size 1080x2160'\` | ✅ |
| 57 | **动画速度** | 让系统感觉更快 | 开发者选项 → 动画缩放 → 0.5x | ✅ |
| 58 | **深色模式** | Android 9 原生支持 | 设置 → 显示 → 深色模式 | ✅ |
| 59 | **自定义开机音** | 换开机音乐 | 替换 \`/system/media/audio/ui/*.ogg\` | ✅ |
| 60 | **导航栏定制** | 改按键布局 | 装模块或改 \`build.prop\` | ⚠️ |

---

## 七、华为 EMUI 专项优化（61-70）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 61 | **彻底关闭省电精灵** | EMUI 最大的性能杀手 | \`su -c 'pm disable-user --user 0 com.huawei.powergenie'\` | ✅ |
| 62 | **关闭华为推送** | 省电省内存 | \`su -c 'pm disable-user --user 0 com.huawei.android.pushagent'\` | ⚠️ 会影响推送 |
| 63 | **关闭 HiCloud 同步** | 停止后台同步 | 设置 → 账号 → 关闭云同步 | ✅ |
| 64 | **关闭应用市场自动更新** | 阻止偷跑流量 | \`su -c 'pm disable-user --user 0 com.huawei.appmarket'\` | ✅ |
| 65 | **关闭系统更新提示** | 避免误点 OTA | \`su -c 'pm disable-user --user 0 com.huawei.android.hwouc'\` | ✅ **强烈推荐** |
| 66 | **关闭用户体验计划** | 停止上报数据 | 设置 → 系统 → 用户体验改进计划 → 关 | ✅ |
| 67 | **关闭杂志锁屏** | 省流量省电 | 设置 → 桌面和壁纸 → 杂志锁屏 → 关 | ✅ |
| 68 | **关闭智能助手** | 减少后台 | 设置 → 智能助手 → 关 | ✅ |
| 69 | **查看 EMUI 白名单** | 看哪些 App 被允许后台 | \`su -c 'dumpsys activity 然后 grep -i hw'\` | ✅ |
| 70 | **修改 EMUI 后台策略** | 让 App 不被杀 | 设置 → 电池 → 启动管理 → 手动管理 | ✅ |

---

## 八、自动化与脚本（71-80）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 71 | **开机自动脚本** | 开机跑任意命令 | 放 \`.sh\` 到 \`/data/adb/service.d/\` | ✅ |
| 72 | **早期启动脚本** | 比 service.d 更早执行 | 放 \`/data/adb/post-fs-data.d/\` | ✅ |
| 73 | **定时任务** | 定时执行脚本 | Termux + cron，或写死循环脚本 | ✅ |
| 74 | **自动备份** | 定期备份指定目录 | 脚本 + \`tar\` + \`rsync\` | ✅ |
| 75 | **自动清理** | 每天清理缓存 | 见 4.3 脚本 2 | ✅ |
| 76 | **开机自动改属性** | 每次开机设置特定 prop | \`resetprop -n\` 写进脚本 | ✅ |
| 77 | **日志自动上传** | 出问题自动存日志 | 脚本 + curl 上传 | ✅ |
| 78 | **Tasker + Root** | 图形化自动化 | 装 Tasker，用 Run Shell 调 su | ✅ |
| 79 | **Termux 定时任务** | 手机当服务器 | Termux + \`pkg install cronie\` | ✅ |
| 80 | **MacroDroid 自动化** | 更简单的自动化 | 装 MacroDroid，用 root 动作 | ✅ |

---

## 九、开发调试与抓包（81-90）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 81 | **系统级抓包** | 抓所有 App 的 HTTPS 流量 | 装 NetCapture/HttpCanary + 装系统证书 | ✅ |
| 82 | **安装系统级 CA 证书** | 让抓包工具能解 HTTPS | \`su -c 'cp ca.pem /system/etc/security/cacerts/'\` + chmod 644 | ✅ |
| 83 | **绕过 SSL Pinning** | 抓有证书锁定的 App | 装 JustTrustMe（需 EdXposed） | ⚠️ |
| 84 | **查看 App 数据目录** | 看任意 App 私有文件 | \`su -c 'ls /data/data/<包名>/'\` | ✅ |
| 85 | **提取 App APK** | 从手机导出已装 App | \`su -c 'cp /data/app/<路径>/base.apk /sdcard/'\` | ✅ |
| 86 | **查看 App 内存详情** | 分析内存占用 | \`su -c 'dumpsys meminfo <包名>'\` | ✅ |
| 87 | **查看 Activity 栈** | 调试界面跳转 | \`su -c 'dumpsys activity activities'\` | ✅ |
| 88 | **查看网络连接** | 看 App 连了哪些 IP | \`su -c 'netstat -anp'\` | ✅ |
| 89 | **logcat 过滤** | 只看关心的日志 | \`su -c 'logcat -s TAG'\` | ✅ |
| 90 | **EdXposed 框架** | Xposed 模块支持 | 装 Riru + EdXposed（**不是** LSPosed） | ⚠️ 需 Riru |

---

## 十、备份、安全与救砖（91-100）

| # | 功能 | 作用 | 怎么做 | 兼容 |
|---|---|---|---|---|
| 91 | **分区备份** | 备份任意分区 | \`su -c 'dd if=/dev/block/by-name/X of=/sdcard/X.img'\` | ✅ |
| 92 | **App 数据备份** | 备份 App 的私有数据 | \`su -c 'tar czf /sdcard/app.tgz /data/data/<包名>'\` | ✅ |
| 93 | **完整 nandroid 式备份** | 备份 system/data/boot | 脚本 dd 所有关键分区 | ✅ |
| 94 | **备份 oeminfo** | 保存设备身份信息 | \`dd if=/dev/block/by-name/oeminfo\` | ✅ **改前必做** |
| 95 | **备份 modem** | 保存基带 | \`dd if=/dev/block/by-name/modem_fw\` | ✅ |
| 96 | **救砖：进 COM 1.0** | 系统起不来时 | Kirin-Tool → VCOM Operations → Unlock | ✅ |
| 97 | **救砖：刷回原厂** | 恢复所有分区 | \`fastboot flash <分区> <镜像>\` | ✅ |
| 98 | **救砖：BD 工程固件** | 终极手段 | IDT + BD 包（我们已备份） | ✅ |
| 99 | **关闭 OTA 防变砖** | 阻止系统自动更新覆盖 Magisk | \`pm disable-user --user 0 com.huawei.android.hwouc\` | ✅ **必做** |
| 100 | **应急 Magisk 开关** | 模块搞崩系统时救急 | 进 recovery 建 \`/cache/.disable_magisk\` | ✅ |

---

# 第六部分 · 兼容性红线（哪些绝对不能用）

## 6.1 ❌ 不要升级 Magisk

| 项目 | 说明 |
|---|---|
| **现状** | Magisk 20.1 + Manager 7.5.1，**已验证完全可用** |
| **Manager 提示可升级到 22.1** | **不要点！** |
| **风险** | 升级会重写 recovery_ramdisk，华为机型上没有 boot 分区，极易变砖 |
| **例外** | 除非你准备好完整救砖流程，否则永远不要升 |

## 6.2 ❌ 不能用 Zygisk 系的一切

**Zygisk 是 Magisk 24.0+ 的功能，你的 20.1 没有。** 以下全部不可用：

| 模块 | 需要 | 替代方案 |
|---|---|---|
| **Shamiko** | Zygisk | 用 MagiskHide（20.1 自带） |
| **LSPosed (Zygisk 版)** | Zygisk | 用 **EdXposed**（Riru 版） |
| **PlayIntegrityFix** | Zygisk + Magisk 24+ | 用 MagiskHide Props Config |
| **Tricky Store** | Zygisk | 无 |
| **ReZygisk** | Magisk 26+ | 无 |
| **Universal SafetyNet Fix (新版)** | Zygisk | 用旧版或 Props Config |

## 6.3 ⚠️ 需要 Riru 的模块（可用但要先装 Riru）

\`\`\`
Riru v22 ~ v25 支持 Magisk 20.1
  ↓
EdXposed（不是 LSPosed）
  ↓
JustTrustMe / XPrivacyLua / 各种 Xposed 模块
\`\`\`

**Riru 下载**：https://github.com/RikkaApps/Riru/releases （选 v25.x 或更早）
**EdXposed 下载**：https://github.com/ElderDrivers/EdXposed/releases

## 6.4 ⚠️ Android 版本限制

| 功能 | 需要 |
|---|---|
| 原生深色模式 | Android 10+（你是 9，只能用主题实现） |
| 存储沙盒 (Scoped Storage) | Android 10+ |
| 动态分区 | Android 10+ |
| 部分新版 App | 可能要求 Android 10+ |

## 6.5 ❌ 在线模块商店已失效

**官方仓库 2023 年归档**，\`repo.json\` 返回 404（我实测过）。

**解决方案**：
1. 手动从 GitHub 下载模块 zip → Manager「从本地安装」
2. 或用 Alt Repo 手动浏览：https://github.com/Magisk-Modules-Alt-Repo
3. 见第七部分的精选直链清单

---

# 第七部分 · 精选模块直链清单

> 全部已验证链接可访问（2026-10-24）

## 7.1 强烈推荐（你这台机器优先装）

| 模块 | 作用 | 链接 |
|---|---|---|
| **MagiskHide Props Config** | 改设备指纹，过 SafetyNet/Play 认证 | https://github.com/Magisk-Modules-Repo/MagiskHidePropsConf |
| **Busybox for Android NDK** | 完整 Linux 命令行工具 | https://github.com/Magisk-Modules-Repo/busybox-ndk |
| **AdAway**（APK，不是模块） | 去广告 | https://github.com/AdAway/AdAway/releases |
| **Systemless Hosts** | 去广告基础（Manager 内置开关） | Magisk Manager → 设置 → 系统级 hosts |
| **Termux**（APK） | 手机上的 Linux 终端 | https://f-droid.org/packages/com.termux/ |

## 7.2 进阶（需要 Riru）

| 模块 | 作用 | 链接 |
|---|---|---|
| **Riru** | Xposed 框架基础 | https://github.com/RikkaApps/Riru/releases |
| **EdXposed** | Xposed 框架（Android 9 版） | https://github.com/ElderDrivers/EdXposed/releases |
| **JustTrustMe** | 绕过 SSL Pinning（配合抓包） | https://github.com/Fuzion24/JustTrustMe |
| **XPrivacyLua** | 隐私沙盒，喂假数据 | https://github.com/M66B/XPrivacyLua |

## 7.3 音效

| 模块 | 作用 | 链接 |
|---|---|---|
| **ViPER4Android FX** | 顶级音效处理 | https://github.com/Magisk-Modules-Repo/ViPER4Android-FX |

## 7.4 浏览更多模块

| 来源 | 链接 | 说明 |
|---|---|---|
| **Alt Repo**（活跃） | https://github.com/Magisk-Modules-Alt-Repo | 社区替代仓库，比原仓库更大 |
| **Alt Repo JSON** | https://raw.githubusercontent.com/Magisk-Modules-Alt-Repo/json/main/modules.json | 模块清单（62 KB） |
| **MMRL**（模块管理器 App） | https://mmrl.dev | 第三方模块商店 App |

## 7.5 安装通用步骤

\`\`\`bash
# 1. 电脑上下载模块 zip
# 2. 推到手机
adb push module.zip /sdcard/Download/

# 3. 用命令行安装（比界面快）
adb shell su -c 'magisk --install-module /sdcard/Download/module.zip'

# 4. 重启
adb reboot

# 5. 验证
adb shell su -c 'ls /data/adb/modules/'
adb shell su -c 'cat /cache/magisk.log | tail -30'
\`\`\`

**出问题**：
\`\`\`bash
# 禁用某个模块
adb shell su -c 'touch /data/adb/modules/<模块ID>/disable'

# 禁用全部模块（核心功能模式）
adb shell su -c 'touch /cache/.disable_magisk'
\`\`\`


---

# 附录 A · 针对你的个性化推荐 TOP 10

> 基于你的实际情况：荣耀V10 当备用机 / 装了三国志战略版 / 有 NetCapture 抓包工具 / 曾经卡死

| 排名 | 做什么 | 为什么对你最重要 | 命令/操作 |
|---|---|---|---|
| **1** | **关闭系统 OTA 更新** | 防止手滑点更新导致 Magisk 被覆盖变砖 | \`su -c 'pm disable-user --user 0 com.huawei.android.hwouc'\` |
| **2** | **装 AdAway 去广告** | 全 App 去广告，最直观的体验提升 | 装 APK → 开系统级 hosts → 启用 |
| **3** | **把游戏加进 MagiskHide** | 防止三国志战略版的反作弊检测 root | Manager → MagiskHide → 勾选游戏 |
| **4** | **关闭华为安全扫描** | 实测它吃 194% CPU，是卡顿元凶之一 | \`su -c 'pm disable-user --user 0 com.huawei.systemmanager'\` |
| **5** | **装 Busybox 模块** | 抓包/脚本/调试都要用它 | 装 busybox-ndk 模块 |
| **6** | **装系统级 CA 证书** | 让 NetCapture 能解 HTTPS（Android 7+ 默认不信用户证书） | 见下方附录 C |
| **7** | **写自动清理脚本** | 防止存储再次爆满导致卡死复发 | 见 4.3 脚本 2 |
| **8** | **装 MagiskHide Props Config** | 改设备指纹，过 SafetyNet，部分 App 才能用 | 装模块 → 终端跑 \`props\` |
| **9** | **备份 oeminfo 和 modem** | 这两个分区丢了就彻底变砖 | \`dd if=/dev/block/by-name/oeminfo of=/sdcard/\` |
| **10** | **装 Termux** | 把这台备用机变成小服务器（下载机/监控/脚本） | F-Droid 装 Termux |

---

# 附录 B · 应急速查表

## B.1 系统起不来怎么办

| 症状 | 原因 | 解决 |
|---|---|---|
| 卡在开机 Logo | 模块冲突 | 进 recovery 建 \`/cache/.disable_magisk\` |
| 反复重启 | 模块搞崩 | 同上，或用 \`/data/adb/modules/<ID>/disable\` |
| 黑屏 + 电脑出现 COM 口 | 引导器损坏 | Kirin-Tool VCOM Unlock → 刷回原厂 XLOADER |
| 卡在 Orange State 画面 | /data 损坏 | 进系统恢复 → 低级格式化数据分区 |
| 完全没反应 | 需要测试点 | BD 工程固件 + IDT |

## B.2 关键文件位置速查

\`\`\`
Magisk 日志          /cache/magisk.log
Magisk 工具          /data/adb/magisk/
模块目录             /data/adb/modules/
开机脚本             /data/adb/service.d/
早期脚本             /data/adb/post-fs-data.d/
禁用全部模块         /cache/.disable_magisk   （创建这个文件）
root 授权数据库      /data/adb/magisk.db
\`\`\`

## B.3 电脑上的救砖资源

\`\`\`
原厂 48 个分区镜像      G:\DeepSeek Harness\Root\tools\unlock_ws\dload337\dload\
9.1.0.337 完整固件      G:\DeepSeek Harness\Root\tools\firmware\BASE337\UPDATE.APP
BD 工程固件（终极）      G:\DeepSeek Harness\Root\tools\firmware\BD\
Kirin-Tool v2.4.2       G:\DeepSeek Harness\Root\tools\kirintool\...\Kirin-Tool.exe
解锁后可用的恢复镜像     G:\DeepSeek Harness\Root\phone_backup\partitions_after_root\
\`\`\`

---

# 附录 C · 三个高价值实操（带完整命令）

## C.1 安装系统级 CA 证书（抓包必备）

Android 7 以后，App 默认**不信任用户安装的证书**，所以抓 HTTPS 必须把证书装到系统区。

\`\`\`bash
# 1. 准备证书（从 NetCapture/Charles/Fiddler 导出 .pem 格式）
#    文件名必须是 <证书哈希>.0 的格式

# 2. 计算哈希（在电脑上，需要 openssl）
#    openssl x509 -inform PEM -subject_hash_old -in ca.pem | head -1
#    假设得到 9a5ba575

# 3. 改名并推送
#    mv ca.pem 9a5ba575.0
adb push 9a5ba575.0 /sdcard/

# 4. 挂载 /system 为可写并复制
adb shell su -c 'mount -o rw,remount /system'
adb shell su -c 'cp /sdcard/9a5ba575.0 /system/etc/security/cacerts/'
adb shell su -c 'chmod 644 /system/etc/security/cacerts/9a5ba575.0'
adb shell su -c 'chown root:root /system/etc/security/cacerts/9a5ba575.0'

# 5. 重启
adb reboot

# 6. 验证
adb shell su -c 'ls -la /system/etc/security/cacerts/ | grep 9a5ba575'
\`\`\`

**注意**：这是唯一需要**真的写 /system** 的操作（不能 systemless，因为证书要在系统启动早期可用）。改完记得备份。

## C.2 批量冻结预装应用（省电省内存）

\`\`\`bash
# 先列出所有第三方/预装包
adb shell pm list packages -s > packages.txt

# 冻结单个（可随时解冻，安全）
adb shell su -c 'pm disable-user --user 0 com.huawei.appmarket'

# 解冻
adb shell su -c 'pm enable com.huawei.appmarket'

# 批量冻结（示例：华为全家桶）
adb shell su -c 'for p in com.huawei.appmarket com.huawei.hwread.al com.huawei.android.thememanager com.huawei.gamebox com.huawei.videoeditor com.huawei.himovie; do pm disable-user --user 0 $p; done'

# 查看已冻结的
adb shell pm list packages -d
\`\`\`

**推荐冻结清单（保守版，不影响正常使用）**：
\`\`\`
com.huawei.appmarket          应用市场
com.huawei.android.hwouc      系统更新   ★ 必冻
com.huawei.gamebox            游戏中心
com.huawei.himovie            华为视频
com.huawei.hwread.al          华为阅读
com.huawei.android.thememanager  主题
com.huawei.videoeditor        视频编辑
com.huawei.browser            华为浏览器
com.huawei.music              华为音乐
\`\`\`

## C.3 把备用机变成 Linux 服务器

\`\`\`bash
# 1. 装 Termux（F-Droid 版本，别用 Play 版）
#    https://f-droid.org/packages/com.termux/

# 2. 在 Termux 里：
pkg update && pkg upgrade
pkg install openssh python nodejs git curl wget nano

# 3. 启动 SSH 服务（默认端口 8022）
sshd
# 查看用户名
whoami
# 查看 IP
ifconfig | grep inet

# 4. 电脑上连接
#    ssh -p 8022 u0_aXXX@<手机IP>

# 5. 设置开机自动启动 SSH（用 Magisk 脚本）
#    创建 /data/adb/service.d/40-termux-ssh.sh：
\`\`\`

\`\`\`bash
#!/system/bin/sh
sleep 120
su -l u0_a122 -c '/data/data/com.termux/files/usr/bin/sshd' 2>/dev/null
\`\`\`

\`\`\`bash
# 6. 给它 root 权限（可选，用于系统级操作）
#    在 Termux 里：su -c '命令'
\`\`\`

---

# 附录 D · 你这台机器的专属信息卡

\`\`\`
设备型号      HONOR BKL-AL20（荣耀V10）
芯片          HiSilicon Kirin 970 (arm64-v8a, 8核)
系统          EMUI 9.1.0.337(C00E333R1P1) / Android 9 (SDK 28)
内核          Linux 4.9.148 aarch64
安全补丁      2019-12-01
SELinux       Enforcing
内存          6 GB (5.7 GB 可用)
存储          53 GB /data（当前用 9.1 GB，剩 44 GB）

Bootloader    unlocked（fblock + userlock 双解锁）
Root          Magisk v20.1 (20100) + Manager v7.5.1
解锁码        485737783237ffff
ramdisk 分区  recovery_ramdisk（华为无 boot 分区）
启动方式      电源键 = 带 Root 的正常系统

Magisk 路径   /data/adb/magisk/
日志          /cache/magisk.log
\`\`\`

---

**文档结束 · 祝使用愉快**

> 有任何问题，把 \`/cache/magisk.log\` 和你的操作步骤发我，我帮你分析。

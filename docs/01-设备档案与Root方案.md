# 荣耀 V10 (BKL-AL20) 规格检测 + Root 方案调研报告

> 生成时间：2026-10-22（Asia/Shanghai）
> 设备序列号：P7CDU18425013192 ｜ 检测方式：adb（Android SDK Platform-Tools 37.0.1）

---

## 第一部分：设备详细规格

### 1.1 身份信息

| 项目 | 值 |
|---|---|
| 品牌 / 厂商 | HONOR / HUAWEI |
| 市场名 | 荣耀 V10 (Honor V10) |
| 型号 | BKL-AL20（全网通） |
| 设备代号 | HWBKL / BKL |
| 序列号 | P7CDU18425013192 |
| 产品区域码 | C00（中国大陆公开版） |
| 定制信息 | C00E333R1P1 |

### 1.2 核心硬件

| 项目 | 值 | 说明 |
|---|---|---|
| SoC | HiSilicon Kirin 970 (kirin970) | 10nm，含 NPU |
| CPU | 8 核 ARM64 (aarch64) | 4×Cortex-A73 2.36GHz + 4×Cortex-A53 1.8GHz |
| ABI | arm64-v8a, armeabi-v7a, armeabi | |
| GPU | ARM Mali-G72 MP12 | OpenGL ES 3.2 (196610) |
| 内存 | 5,835,420 kB ≈ 5.56 GiB | → **6GB LPDDR4X 版本** |
| ZRAM | 2,293,756 kB 总 / 已用 852,416 kB | 内存压缩交换 |
| 存储 | /data 53 GB | → **64GB UFS 2.1 版本** |
| 屏幕 | 1080 × 2160，480dpi（403.411 ppi） | 5.99 英寸 IPS LCD，60Hz，18:9 |
| 电池 | Li-poly，3750mAh（典型值） | health=2(良好)，当前 30%，3.84V，32°C |
| 充电 | USB 供电，Max 500mA / 4.75V | 支持 5V/4.5A 超级快充（需原装充电头） |
| 摄像头 | 2 个逻辑相机（后置/前置） | 后置 2000万黑白 + 1600万彩色，前置 1300万 |
| 传感器 | accelerometer-lsm6ds3-c (ST)、指纹、霍尔等 | 指纹在正面 Home 键 |
| 耳机 | hi3660_HI6403_CARD Headset Jack | 有 3.5mm 耳机孔 |
| 基带 | 21C20B369S009C000 | 双卡双待 (dsds)，LTE |

### 1.3 系统与构建

| 项目 | 值 |
|---|---|
| Android 版本 | 9 (API 28) |
| EMUI 版本 | EmotionUI_9.1.0 |
| 构建号 | BKL-AL20 9.1.0.337(C00E333R1P1) |
| 指纹 | HONOR/BKL-AL20/HWBKL:9/HUAWEIBKL-AL20/9.1.0.337C00:user/release-keys |
| 内核 | Linux 4.9.148 aarch64（2019-12-13 构建） |
| 构建日期 | 2019-12-13 12:10:24 CST |
| 安全补丁 | **2019-12-01** |
| 构建类型 | user / release-keys（正式版，非 eng） |
| 语言/区域 | zh-Hans-CN |
| 加密 | File-Based Encryption (FBE) 已启用 |
| 用户 | 1 个（汪洋） |
| 应用数 | 255 个包（其中第三方 42 个） |

### 1.4 安全 / 引导状态（关键）

| 项目 | 值 | 含义 |
|---|---|---|
| ro.boot.verifiedbootstate | **green** | 验证启动通过，系统未被篡改 |
| ro.boot.flash.locked | **1** | **Bootloader 已锁定** |
| ro.boot.vbmeta.device_state | **locked** | vbmeta 锁定 |
| ro.boot.veritymode | enforcing | dm-verity 强制校验开启 |
| SELinux | Enforcing | |
| ro.oem_unlock_supported | 1 | 硬件支持解锁 |
| ro.secure / ro.debuggable | 1 / 0 | 正式版，无 root adb |
| fastboot oem get-bootinfo | **locked** | 引导器确认锁定 |
| fastboot oem check-rootinfo | **SAFE** | 未检测到 root 或篡改 |
| fastboot getvar / flashing 等 | **Command not allowed** | 锁定状态下大部分 fastboot 命令被拒 |

### 1.5 分区表（/dev/block/by-name）

磁盘 sdd（UFS），关键分区：

```
sdd38 kernel              引导内核
sdd39 eng_system          工程模式系统
sdd40 recovery_ramdisk    ★ Recovery 的 ramdisk（华为无独立 boot 分区）
sdd41 recovery_vendor
sdd42/43 dts / dto        设备树
sdd47 recovery_vbmeta
sdd48 erecovery_vbmeta
sdd49 vbmeta              ★ 验证启动元数据
sdd53 version             版本信息
sdd54 vendor
sdd55 preload             预装
sdd56 cust                定制
sdd57 odm
sdd58 cache
sdd61 product
sdd62 system
sdd63 patch               ★ 华为补丁分区
sdd64 userdata            ★ 用户数据（53GB）
sdc1  frp                 恢复出厂保护
sdc2  persist
sdd6  oeminfo             ★ 机型/区域信息
sdd14 veritykey
sdd25 hisee_img / sdd26 hhee / sdd33 teeos   安全子系统
sdd1/2 vrl / vrl_backup
```

**重要：华为 EMUI 9 机型没有独立的 boot 和 ramdisk 分区**（内核在 kernel，ramdisk 只在 recovery_ramdisk），这直接决定了 Root 的实现方式（见第三部分）。

---

## 第二部分：卡死原因初步诊断

采集到的异常信号：

| 指标 | 数值 | 判断 |
|---|---|---|
| /data 占用 | **47 GB / 53 GB = 89%**，仅剩 5.9 GB | ⚠️ 存储严重吃紧 |
| 应用本体 | 20.4 GB | |
| 应用数据 | 14.6 GB | |
| 照片 | 8.3 GB | |
| 视频 | 2.5 GB | |
| 音频 | 1.6 GB | |
| Load Average | **41.40 / 31.69 / 15.14**（8 核） | ⚠️ 严重超载（正常应 < 8） |
| kswapd0 / f2fs_gc | 持续占用 CPU | ⚠️ 内存回收 + 闪存垃圾回收互相抢 I/O |
| ZRAM 交换 | 852 MB 已换出 | ⚠️ 内存压力大 |
| 主要 I/O | system_server 404 major faults，com.huawei.hidisk 6.8% CPU | ⚠️ I/O 阻塞 |
| DropBox 异常 | system_server_wtf: No service published for: connectivity (HwWifiStateMachine) | ⚠️ 系统服务启动异常 |
| 第三方应用 | 42 个 | 常驻后台多 |

**结论（初步）**：卡死不是单一原因，而是 **存储接近写满 + 老化的 UFS + 内存压缩交换 + 大量后台应用** 共同造成的 I/O 雪崩。EMUI 9.1 在 /data 剩余空间低于 10% 时，f2fs 的 GC 会与正常读写严重争抢，典型表现就是“随机卡死几十秒”。

**这意味着：修复卡死其实不需要 Root** —— 清理存储 / 恢复出厂 / 重刷固件就能解决绝大部分问题。Root 是“废物利用”的额外目标。

---

## 第三部分：Root / 解锁方案调研

### 3.0 前提事实

1. **华为官方解锁码通道已于 2018-07-25 永久关闭**，官方渠道无解。
2. 本机 Bootloader = **locked**，fastboot 绝大部分命令返回 Command not allowed，**必须先解锁 BL 才能 Root**。
3. 麒麟 970 无法用老牌工具 PotatoNV 解锁（PotatoNV 仅支持 Kirin 620/65x/925/935/950/955/960）。
4. 所有非官方解锁都需要让手机进入 **COM 1.0（VCOM）底层模式**，路径有两条：
   - **SWTP（软件测试点）**：无需拆机，要求安全补丁 ≤ 2021-01 → **本机 2019-12，满足！**
   - **硬件测试点**：拆机后用镊子把主板测试点短接到地。

---

### 方案 A：Kirin-Tool（免费，★首选）

- **来源**：GitHub kethily-daniel/Kirin-Tool（source-available 许可）｜官网 kirintool.cfd ｜Telegram t.me/kirintoolsupport
- **教程**：XDA 帖 4768171《PERMANENT bootloader unlock for Kirin 710/710F/970/980》（2025-11 发布，2026-10-09 更新）
- **支持范围**：Kirin 620 ~ 990 5G；**明确支持 Kirin 970**，要求 **EMUI 9.1.0.XXX 及以下** → **本机 9.1.0.337 完全命中**
- **仓库内已内置 hisi970 引导器**：loaders/hisi970/{xloader.ktl, fastboot.ktl, uce.ktl, null.ktl}
- **两种进入 COM 1.0 的方式**：
  - **A1｜SWTP 软件测试点（推荐，不拆机）**
    1. 安装 HiSuite（只为拿 USB 更新模式驱动）
    2. 下载 **BKL-AL20 C00 且版本 ≥ 9.1.0.337** 的官方固件，解压出 dload/update_sd_base/update.app
    3. Kirin-Tool 选 CPU = 970 → VCOM operations → 勾 software testpoint → 选中 update.app
    4. 手机关机 → 同时按住 **音量+ 和 音量-** 插 USB → 进 recovery → 选 Update mode → USB update mode
    5. Kirin-Tool 点 Enter → 手机显示 update success 后黑屏 → 成功进入 COM 1.0
  - **A2｜硬件测试点（SWTP 失败时兜底）**：拆后盖，用镊子把测试点短接到地（金属屏蔽罩）同时插 USB，设备管理器出现 USB SER 或 HUAWEI USB COM 1.0；若显示 USB SER 需手动装 COM1 驱动（hw_quser.inf）
- **解锁动作**：Kirin-Tool → CPU=970 → VCOM operations → Unlock → 切到 Security tools → Unlock → 提示时按一下电源键 → 完成
- **需要下载**：XDA 附件 Kirin-Tool-v2.3.2.zip(58.4MB)、COM 1 DRIVER.7z(8.9MB)、Test points.7z(9.1MB)
- **风险**：变砖；解锁后可能出现“托盘下拉打不开”等 bug，需补刷 kernel；NM/SD 卡数据可能丢失

---

### 方案 B：Huawei-Unlock-Tool / HUT（免费开源）

- **来源**：GitHub werasik2aa/Huawei-Unlock-Tool，Telegram t.me/+TztmQ7N2xz9lN2Uy
- **支持**：620 / 620(CAM) / 65x_a / 65x_b / 710 / 810 / 925 / 935 / 950 / 955 / 960 / **970**（980 理论支持）
- **硬性要求**：**必须 EMUI 8 或 9** → 本机 EMUI 9.1 满足
- **功能**：Bootloader 解锁 / FRP 解锁、分区管理、整机 ROM 刷写与备份、oeminfo 编译/反编译、update.app 提取与 EDL 9008 刷写、Rawprogram0.xml 生成、HISI Flash/FRP 工具
- **原理**：内置 PotatoNV 源码 + 4PDA 的 Moongamer QCOM 解锁逻辑
- **定位**：可作为**方案 A 的备用/交叉验证工具**；也可在解锁后用于刷机与救砖

---

### 方案 C：付费商业工具（省事但花钱）

| 工具 | 费用 | 对本机支持 | 说明 |
|---|---|---|---|
| **HCU Client + DC Phoenix** | **$19 / 3 天** | Kirin 970 ✓ | DC Phoenix 把手机打进“软件测试点”模式 → HCU 读取/切换 Bootloader lock 与 FRP → DC Phoenix 退出测试点模式。**目前公认最稳** |
| **ChimeraTool** | 订阅制 | **明确列出 HUAWEI Honor V10 BKL-AL20** | Unlock/Relock Bootloader、FRP 移除、Repair IMEI、Read/Write Cert (Fastboot)、Load Factory Fastboot、USB 固件更新 |
| **SigmaKey / Octoplus** | 按次/订阅 | Kirin 970 ✓ | 多为维修店工具链 |

优点：图形化、成功率高、有售后。缺点：收费、需联网激活、工具来源无法审计（存在被投毒风险）。

---

### 方案 D：PotatoNV —— ❌ 不适用

仅支持 Kirin 620 / 650 / 655 / 658 / 659 / 925 / 935 / 950 / 960。**Kirin 970 明确不在支持列表**，直接排除。

### 方案 E：官方解锁码 —— ❌ 已关闭

华为 2018-07-25 关闭解锁码申请页面，无官方路径。

---

### 3.6 解锁之后的 Root 路线（华为特有，重点）

因为 **华为 EMUI 9 没有 boot / ramdisk 分区**，所以不能照搬“修补 boot.img”的通用做法。

**路线 R1：Magisk 修补 recovery_ramdisk（推荐，无需第三方 Recovery）**
1. 从官方固件 update.app 中提取原厂 recovery_ramdisk.img（用 HuaweiUpdateExtractor）
2. 装 Magisk App → 设置里**打开 Recovery Mode**（因为检测到 Ramdisk = No）→ 修补 recovery_ramdisk.img → 得到 magisk_patched-xxxxx.img
3. fastboot flash recovery_ramdisk magisk_patched-xxxxx.img
4. **每次开机按住 音量+ + 电源** 进 recovery → Magisk 引导系统 → 获得 Root
5. 代价：正常开机无 Root，必须走 recovery 组合键；可装 Magisk 模块（Zygisk + Shamiko 隐藏 Root）

**路线 R2：刷第三方 TWRP + Magisk**
- 荣耀 V10 有适配 EMUI 8/9 的 TWRP 3.2.x，刷入 recovery_ramdisk 后卡刷 Magisk.zip
- 优点：可备份/刷机更方便；缺点：TWRP 与 EMUI 9.1 兼容性参差

**Magisk 版本建议**：EMUI 9 上 **v23.0** 兼容性最好（v24+ 对 legacy recovery 模式支持有变化，v26+ 基本移除），也有教程用 v20.4。

**必要收尾**：解锁后需处理 dm-verity / AVB（Kirin-Tool 解锁流程通常已处理，或 fastboot flashing unlock / 刷入已去除 verity 的 vbmeta）。

---

### 3.7 固件来源（SWTP 与提取镜像都需要）

- **免费**：Firmware Finder / HiSuite Proxy（按型号 BKL-AL20 + 版本号直接拉官方固件）
- **第三方站**：givemerom、HalabTech、onfix.cn、donghairom（部分收费/需注册）
- **本机需要的版本**：**BKL-AL20，C00 定制，≥ 9.1.0.337**（当前是 9.1.0.337 C00E333R1P1）

---

## 第四部分：建议执行路线（等你确认）

| 阶段 | 内容 | 风险 | 是否需要 Root | 预计耗时 |
|---|---|---|---|---|
| **0** | 全量备份（照片 8.3G / 视频 2.5G / 应用数据）+ 记录 IMEI、oeminfo、分区表 | 无 | 否 | 30-90 分钟 |
| **1** | **修复卡死**：清理 /data 至剩余 > 20%，或直接恢复出厂设置 | 低（会清数据，已备份） | 否 | 30 分钟 |
| **2** | **解锁 Bootloader**：Kirin-Tool + SWTP（失败则转硬件测试点） | **中高**（变砖/状态不可逆/清数据） | 否 | 1-3 小时 |
| **3** | **Root**：Magisk 修补 recovery_ramdisk 并刷入 | 中 | 是 | 1 小时 |
| **4** | 废物利用：去广告、装模块、当备用机/软路由/监控/服务器 | 低 | 是 | 按需 |

### ⚠️ 必须先确认的风险点

1. **数据大概率全清**：解锁命令本身是否强制擦除没有 100% 保证，但三条证据都指向“会清”：(a) XDA 指南明确要求解锁后 `format userdata`；(b) 本机是 FBE 加密，密钥由 Keymaster 封装且与引导状态绑定，green → orange 后大概率拒绝解密，系统会强制恢复出厂；(c) dm-verity 处于 enforcing。**按“一定会清空”准备，先备份。**
2. **解锁状态不可逆 —— 更正上次的说法**：“硬件熔断 eFuse”这个说法我上次讲过头了。公开资料（bootloader-unlock-wall-of-shame 等）显示华为的锁状态存放在 OEMINFO/NVME 安全区 + 安全引擎（hisee/hhee/teeos）里，走的是分区 + RSA 签名（RDLOCK）路线，**没有证据**表明麒麟 970 解锁会烧断硅片熔丝（那是三星 KNOX 的机制）。但“不可逆”是真的：回锁也恢复不成“从未解锁”，`fastboot oem check-rootinfo` 会留下带时间戳的永久 RISK 记录。另外本机是 2017 年机型，**保修早已过期**，这条风险对你无实际影响。
3. **变砖风险**：Kirin 970 解锁存在“能解锁但系统异常”的报告（如托盘无法下拉），需要补刷 kernel 甚至重刷全量固件。**本机是唯一一台机器的话，请谨慎**。
4. **需要拆机**：如果 SWTP 失败，就必须拆后盖短接测试点（后盖为玻璃，有碎裂风险）。
5. **固件获取**：SWTP 需要与机型/版本匹配的官方 update.app，如果找不到 ≥ 9.1.0.337 的 C00 固件，SWTP 走不通，只能拆机。

### 建议

- **如果首要目标是“让手机不卡”**：先做阶段 0 + 1，大概率就好了，不需要冒险解锁。
- **如果确定要“废物利用”**（刷模块、当服务器、跑脚本）：再走阶段 2 + 3，推荐 **方案 A（Kirin-Tool，免费）**，付费方案 C（HCU + DC Phoenix $19）作为保底。

---

## 附：信息来源

- XDA：[PERMANENT bootloader unlock for Kirin 710/710F/970/980 (updated guide)](https://xdaforums.com/t/bootloader-unlock-permanent-bootloader-unlock-for-kirin-710-710f-970-and-980-socs-updated-guide.4768171/)
- GitHub：[kethily-daniel/Kirin-Tool](https://github.com/kethily-daniel/Kirin-Tool)
- GitHub：[werasik2aa/Huawei-Unlock-Tool](https://github.com/werasik2aa/Huawei-Unlock-Tool)
- GitHub：[kitsuned/PotatoNV Discussion #155](https://github.com/kitsuned/PotatoNV/discussions/155)
- 博客：[How to unlock the bootloader on Huawei P20-PRO without code](https://blog.pasqualefiorillo.it/how-to-unlock-bootloader-on-huawei-p20-pro-clt-l09-without-code/)
- ChimeraTool：[Huawei Honor V10 BKL-AL20 支持列表](https://chimeratool.com/en/models/huawei-honor-v10-bkl-al20)
- XDA 资讯：[Bootloader unlock method for Huawei and Honor devices with Kirin SoCs](https://www.xda-developers.com/huawei-honor-bootloader-unlock-potatonv/)
- 博客园：[Honor V10 BKL-AL20 ROOT（Magisk方式）](https://www.cnblogs.com/zhaojjiang/p/9600763.html)
- Xhy's Blog：[emui9 安装 Magisk 框架](https://xhyeax.github.io/2019/04/02/emui9-magisk-install/)
- CSDN：[无需 TWRP 实现 Magisk 刷入（以华为荣耀 V9 为例）](https://blog.csdn.net/beizishaizi/article/details/125445900)
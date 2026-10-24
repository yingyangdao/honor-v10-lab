# 荣耀V10 (BKL-AL20) 解锁 + Root 完整报告

**完成时间**: 2026-10-24 02:52
**设备**: HONOR BKL-AL20 (荣耀V10) / Kirin 970
**系统**: EMUI 9.1.0.337(C00E333R1P1) / Android 9 / 安全补丁 2019-12-01

---

## 一、最终状态

| 项目 | 状态 | 验证命令 | 结果 |
|---|---|---|---|
| Bootloader | **已解锁** | `getprop ro.boot.flash.locked` | `0` |
| 引导验证状态 | **orange（已解锁）** | `getprop ro.boot.verifiedbootstate` | `orange` |
| Root | **完全可用** | `su -c id` | `uid=0(root) context=u:r:magisk:s0` |
| Magisk 版本 | **v20.1 (20100)** | `magisk -v` | `20.1:MAGISK` |
| Magisk Manager | **v7.5.1** | — | 已安装 |
| MagiskHide | **可用** | `magisk --list` | `magiskhide` 在列 |
| magiskboot | **可用** | `magiskboot` | `MagiskBoot v20.1` |
| busybox | **可用** | `busybox` | `BusyBox v1.31.1-topjohnwu` |
| 系统版本 | **未变** | `getprop ro.build.display.id` | `BKL-AL20 9.1.0.337(C00E333R1P1)` |
| 存储 | **已修复** | `df -h /data` | 53G 总 / 用 9.1G / **剩 44G (18%)** |

---

## 二、卡死问题根因与修复

### 根因
**数据分区占用 89%（47 GB / 53 GB）** —— f2fs 文件系统在高占用率下垃圾回收会疯狂搬运数据，导致系统随时卡死。

### 修复
通过解锁时的强制数据擦除 + 低级格式化，**存储占用从 89% 降到 18%**，根因消除。

---

## 三、技术攻关过程

### 3.1 核心难点
华为 EMUI 9 的 USB 更新模式（DLOAD）有**版本检查**，拒绝低于设备版本的固件包。

### 3.2 关键突破

**① 逆向出完整 CRC 机制**
- 算法：**CRC-16/X-25**，按原始数据逐 **32K 块**计算（最后一块不补齐）
- `CRC.img` 结构：uint16 LE 数组，每 32K 块一项
  ```
  idx0 = CURVER
  idx1 = VERLIST
  idx2 = PACKAGE_TYPE
  idx3.. = HISIUFS_GPT 及其后所有镜像
  ```
- **`CRC.img` 自身不在表内，但有 SHA256RSA 签名保护 → 不可修改**

**② 挖出设备端版本检查逻辑**（反编译 update-binary）
```
check_emui_version
the current emui version does not exist in the list, not allow to update.
line length of list greater than emui version length, not allow to update.
This is not a downgrade package, don't need to check emui version.
version list not be checked, maybe there is no versionlist or checked fail!
```

**③ 实现真实 CRC 碰撞**
用 GF(2) 线性代数求解，构造出**内容全改但 CRC 值不变**的 VERLIST：
- 目标 CRC：`0xad14`（原值）
- 方法：在末尾留 16 字节"牺牲区"，用高斯消元求解使 CRC 命中目标
- **结果：CRC.img 无需修改，签名保护绕过**

**④ 发现版本标识真相**
对比 9.1.0.337 与 8.0.0.199 的 VERLIST：
```
9.1.0.337 包:  BKL-EMUI90          ← 设备实际比对的「EMUI 版本标识」
              BKL-EMUI9.0.0.150_Xloader
              BKLL00B000
              BKLC00B000
              BKL-AL00 8.0.0.106(C00)
              ...
8.0.0.199 包:  （无 BKL-EMUI90 这两行）→ 版本检查失败
```

### 3.3 最终执行路径

```
1. 取得 9.1.0.337 完整固件包（含 XLOADER）
      ↓
2. Kirin-Tool SWTP（软件测试点）
   ├─ 用 9.1.0.337 的 UPDATE.APP（版本完全匹配）
   └─ 手机显示 "update success" → 黑屏 → 进入 COM 1.0 模式
      ↓
3. 安装 COM 1.0 驱动（VID_12D1&PID_3609）
   ├─ 系统无匹配 INF → 手工给 hw_quser.inf 加入 PID_3609
   ├─ 自签名证书 + 目录签名 + 测试签名模式
   └─ pnputil 正式安装 → COM14 出现
      ↓
4. Kirin-Tool VCOM Operations → Unlock
   └─ 加载临时 fastboot（null → XLOADER → UCE → FASTBOOT）
      ↓
5. 解锁 Bootloader
   ├─ fblock:   locked → unlocked
   └─ userlock: locked → unlocked
      ↓
6. 刷入 Magisk（recovery_ramdisk）
      ↓
7. 擦除 userdata（清 crypt info）
      ↓
8. 恢复引导器（SWTP 会把 XLOADER 打坏）
   ├─ fastboot flash xloader  ← 原厂 9.1.0.337 XLOADER
   └─ fastboot flash fastboot ← 原厂 FASTBOOT
      ↓
9. 低级格式化数据分区（修复损坏的 /data）
      ↓
10. 手工重建 Magisk 环境（/data/adb/magisk/）
      ↓
✅ 完成
```

---

## 四、关键文件位置

### 固件与镜像
```
tools/firmware/BASE337/UPDATE.APP          9.1.0.337 完整固件 (3.72 GB)
tools/firmware/REC_337/9.1.0.337/
    RECOVERY_RAMDIS.img                     原厂 recovery (MD5 f9f94fa3...)
    magisk_patched.img                      Magisk 版 (MD5 49a2e1ae...)
tools/unlock_ws/dload337/dload/             48 个分区镜像（含 XLOADER）
tools/firmware/BD/.../                       BD 工程固件（救砖用）
```

### 备份
```
phone_backup/apk/                           34 个 APK (2.34 GB)
phone_backup/app_list.md                    带中文名的清单
phone_backup/partitions_after_root/         解锁后关键分区备份
    recovery_ramdisk.img  (32 MB)           已验证可用的 Magisk 版
    kernel.img / vbmeta.img / fastboot.img ...
phone_backup/baseline_before_unlock.txt     解锁前 rootinfo 基线
```

### 工具
```
tools/kirintool/.../Kirin-Tool.exe          Kirin-Tool v2.4.2
tools/magisk/MagiskManager-v7.5.1.apk       配套 Manager
tools/magisk/Magisk-v20.1.zip               官方包（含 busybox 等）
tools/drivers/hw_quser_3609/                改版驱动（含 PID_3609）
tools/drivers/install_driver_admin.ps1      驱动安装脚本
```

### 关键脚本
```
tools/unlock_ws/run_swtp2.py                SWTP 漏洞发送器
tools/unlock_ws/collide2.py                 CRC 碰撞生成器
tools/unlock_ws/restore_stock.ps1           恢复原厂脚本
fix_magisk_env.ps1                          重建 Magisk 环境
```

---

## 五、解锁码

```
485737783237ffff
```
（从 update.APP 的镜像头 offset 12 提取，8 字节，所有版本一致）

---

## 六、使用须知

### Root 使用
**正常开机（电源键）即带 Root** —— 无需按音量+进 recovery。

### 每次开机的解锁警告
```
⚠️ Your device has been unlocked and can't be trusted.
(1) Press Power key to continue.
(3) Your device will continue to boot 5 seconds later if there is no operation.
```
**这是正常的，等 5 秒自动继续。**

### 必须避免
- ❌ **不要点系统 OTA 更新**（会覆盖 Magisk）
- ❌ 不要刷非本机型固件
- ⚠️ 部分银行/支付 App 会检测解锁 → 用 MagiskHide 隐藏

### 救砖资源（全部就位）
1. **原厂镜像** —— 48 个分区镜像
2. **Kirin-Tool** —— 重新进 COM 1.0
3. **BD 工程固件** —— 终极救砖
4. **完整备份** —— 解锁后可用的 recovery_ramdisk

---

## 七、Magisk 环境修复详解（本次独有）

### 问题
格式化数据分区后 `/data/adb/magisk/` 被清空，导致：
```
E Magisk : * Magisk environment setup incomplete, abort
```
Magisk Manager 反复提示"需要修复运行环境"，但它的修复流程（下载+打补丁+刷机）在这台华为上无效，形成死循环。

### 根因
Magisk Manager 7.5.1 的 APK **不打包 Magisk 二进制**（只有 2 MB 界面资源），需要联网下载 `Magisk-vXX.zip`。而修复流程走的是"打补丁刷 boot 分区"，这台设备**没有 boot 分区**，所以永远失败。

### 解决
从官方 `Magisk-v20.1.zip` 手工组装 `/data/adb/magisk/`：

| 文件 | 来源 | 大小 |
|---|---|---|
| `magisk` | `magiskinit64 -x magisk magisk` 提取 | 149848 |
| `magiskboot` | `arm/magiskboot` | 303088 |
| `magiskinit` | `arm/magiskinit` | 365892 |
| `magiskinit64` | `arm/magiskinit64` | 345412 |
| `busybox` | 从 `update-binary` 偏移 1604608 处 dd 出（ARM 版） | 1070668 |
| `util_functions.sh` / `boot_patch.sh` / `addon.d.sh` / `magisk.apk` | `common/` | — |
| `chromeos/` | `chromeos/` | — |

**关键发现**：`update-binary` 是自解压脚本，脚本占前 1024 字节，后面追加多个 busybox：
- 偏移 1024，长度 1603584 → **x86 版**
- 偏移 1604608，长度 1070668 → **ARM 版** ← 我们要的

### 修复后日志
```
* Initializing Magisk environment
* Mounting mirrors
* Setting up internal busybox          ← 之前在这里 abort
* Running post-fs-data.d scripts
* Running module post-fs-data scripts
* Loading modules
* Starting MagiskHide
  hide_policy: Hiding sensitive props
  hide_list init: [com.google.android.gms/com.google.android.gms.unstable]
```

---

## 八、遗留小问题

```
I Magisk : apk_install: /data/magisk.apk
I Magisk : apk_install: Failure [INSTALL_FAILED_ABORTED: User rejected permissions]
```
Magisk 尝试安装自己的 stub APK（用于隐藏）时被拒绝。**不影响 Root 功能**。如需修复：给 Magisk Manager 开「安装未知应用」权限。

---

## 九、验证命令速查

```bash
# 解锁状态
adb shell getprop ro.boot.flash.locked          # 0
adb shell getprop ro.boot.verifiedbootstate     # orange

# Root
adb shell su -c id                              # uid=0(root)

# Magisk 状态
adb shell su -c 'magisk -v'                     # 20.1:MAGISK
adb shell su -c 'magisk --list'                 # su resetprop magiskhide

# 存储
adb shell df -h /data

# Magisk 日志
adb shell su -c 'cat /cache/magisk.log'
```

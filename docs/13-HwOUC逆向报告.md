# HwOUC OTA 接口逆向报告

> 2026-10-23 ｜ 目标：拿到 BKL-AL20 9.1.0.337 官方下载地址

## 一、成果：接口已完全逆向，实测被服务器接受

### 端点
```
POST https://query.hicloud.com/sp_ard_common/v2/onestopCheck.action?verType=true&autoInstall=y&latest=true
Content-Type: application/json
```
（另有 `?logOnly=true` 变体；`v1` 端点返回 -1 不可用；`CheckEx.action` 返回 `{"status":"1"}`；`GetCondition.action` 返回 `{"code":"-1"}`）

### 完整请求体（已实测跑通）
```json
{
  "commonRules": {
    "FingerPrint": "HONOR/BKL-AL20/HWBKL:9/HUAWEIBKL-AL20/9.1.0.337C00:user/release-keys",
    "DeviceName": "BKL-AL20",
    "VendorCountry": "hw-cn",
    "BoardID": "",
    "Reserved1": "", "Reserved2": "",
    "vendor": "BKL-AL20-hw-cn:",
    "deviceId": "P7CDU18425013192",
    "udid": "",
    "Language": "zh-CN",
    "OS": "Android 9",
    "HotaVersion": "9.1.30.391",
    "saleinfo": "black|cn|hw|N|EmotionUI 9.1.0|6.4 GB|64 GB|8 2.2GHz|Y|blue|9.1.30.391|Y",
    "C version": "C00",
    "D version": "C00",
    "Subgroup": "", "Vergroup": "", "devicetoken": "",
    "PackageType": "psi",
    "ControlFlag": "0",
    "extra info": "",
    "DeviceDisplayVersion": "BKL-AL20 8.0.0.199(C00)",
    "ProductBaseVersion": "BKL-LGRP1-CHN 8.0.0.199",
    "Emui": "EmotionUI 9.1.0"
  },
  "versionPackageRules": [
    {"versionPackageType": 2, "rules": {"FirmWare": "BKL-LGRP1-CHN 8.0.0.199"}},
    {"versionPackageType": 3, "rules": {"FirmWare": "BKL-AL20-CUST 8.0.0.199(C00)"}},
    {"versionPackageType": 4, "rules": {"FirmWare": "BKL-AL20-PRELOAD 8.0.0.1(C00R1)"}}
  ],
  "keyAttestation": ""
}
```

### 服务器响应（与手机自己查询的响应**一字不差**）
```json
{"status":"1","versionPackageCheckResults":[{"status":"1","versionPackageType":2},{"status":"1","versionPackageType":3},{"status":"1","versionPackageType":4}]}
```

### 已验证的字段约束
| 试验 | 结果 |
|---|---|
| 空 body `{}` | `{"status":"-1"}` |
| 有 commonRules，无 versionPackageRules | `{"status":"-1"}` → **versionPackageRules 是必需字段** |
| 完整 body | `{"status":"1",...}` ✅ |
| PackageType 改成 full/ota/normal/空 | 响应不变 |
| ControlFlag=1 | 响应不变 |
| 加 udid / 随机序列号 / 空序列号 | 响应不变 |
| 去掉 keyAttestation 字段 | 响应不变 |
| 版本号改成 8.0.0.199 / 9.0.0.187 / 9.1.0.300 / 9.1.0.325 | **响应仍不变，永远是「无新版本」** |

## 二、卡点：为什么拿不到下载地址

服务器**不采信**我发送的版本号，恒定返回「无新版本」。推测原因：

1. **`authorize.action` 鉴权缺失** —— 手机端 HwOUC 会先调 `https://query.hicloud.com/sp_ard_common/v1/authorize.action` 拿签名令牌，再用 `cert=` / `sign=` 证明身份。实测空请求返回 `data=&sign=&cert=`（空模板）。
2. 私钥在 `.bks` 密钥库里（APK 内含 `cer.pem` + 2 个 `.bks`），**无法提取**，这条鉴权路基本堵死。
3. 或者服务器直接用 deviceId 在库里查真实版本。

## 三、附带挖到的关键数据（很有用）

从手机 props 里拿到完整的**四元组版本信息**：
```
ro.build.display.id                  = BKL-AL20 9.1.0.337(C00E333R1P1)
ro.build.fingerprint                 = HONOR/BKL-AL20/HWBKL:9/HUAWEIBKL-AL20/9.1.0.337C00:user/release-keys
ro.build.description                 = BKL-AL20-user 9.1.0 HUAWEIBKL-AL20 337-CHN-LGRP1 release-keys
ro.comp.hl.product_base_version      = BKL-LGRP1-CHN 9.1.0.337
ro.comp.hl.product_cust_version      = BKL-AL20-CUST 9.1.0.333(C00)
ro.comp.hl.product_preload_version   = BKL-AL20-PRELOAD 9.1.0.1(C00R1)
ro.comp.cust_version                 = Cust-CHN 9.0.0.1(0001)
ro.comp.product_version              = Product-BKL-LGRP1-CHN 9.1.0(0000)
```

**`BKL-LGRP1-CHN` 这个 LGRP 名很关键** —— 找固件时可以直接搜这个串。

## 四、结论与建议

### HwOUC 逆向：**技术上成功**（格式完全对，服务器接受），但**拿不到下载地址**（鉴权层挡住）。

### 新思路（推荐）

**eRecovery 路线** —— 手机自己就能下载 9.1.0.337 完整包：
1. 关机 → **电源键 + 音量加**（按住约 3 秒）→ 进入 eRecovery
2. 选「下载最新版本并恢复」（需连 WiFi）
3. eRecovery 下载的就是**当前版本 9.1.0.337 的完整固件包**

**关键**：eRecovery 是系统级恢复流程，可能不走设备证书鉴权。只要在下载时把 URL 抓出来（PC 开热点让手机连、或用代理），就能自己下整包。

**风险提示**：eRecovery 恢复会**清空手机数据**（你已备份）。而且它会直接刷机。

### 其他可行路线
- **HiSuite PC 端「系统修复」**：同样会下载当前版本完整包
- 继续等另一个对话找到的 9.1.0.337 完整固件

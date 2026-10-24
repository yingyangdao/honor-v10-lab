# 荣耀V10 · Frida / objection / 电脑抓包 完全教程

设备：HONOR BKL-AL20（荣耀V10）· Android 9 / EMUI 9.1.0.337 · Magisk 20.1 · 已 Root
编写时间：2026-10-25

---

## 0. 结论先行：这台机器能用什么、不能用什么

| 方案 | 状态 | 说明 |
|---|---|---|
| **frida-server** | ❌ **用不了** | 华为锁死了 SELinux 策略写接口 |
| **Frida Gadget**（objection patchapk） | ✅ **强烈推荐** | 绕过 frida-server 限制，实测可用 |
| **EdXposed 模块** | ✅ 可用 | 框架已激活（Riru v23.9 + EdXposed 0.5.2.2） |
| **系统 CA 证书 + 代理** | ✅ 已配好 | 能解密遵循系统信任链的 App |
| **tcpdump 被动抓包** | ✅ 已装好 | 抓不走代理的流量 |
| **PCAPdroid** | ✅ 备选 | 免 root，VPN 方式 |

### 为什么 frida-server 在这台机器上用不了（有实测证据）

```
# 1) frida-server 自己报的错
/data/adb/frida/frida-server -v
→ Unable to save SELinux policy to the kernel: Out of memory

# 2) 换 Magisk 自带的工具，一样失败（说明不是 frida 的问题）
magiskpolicy --live "allow magisk magisk_file file read"
→ write failed with 12: Out of memory

# 3) 想关 SELinux 也不行
setenforce 0
→ setenforce: Couldn't set enforcing status to '0': Invalid argument
```

**根因**：华为内核把 `/sys/fs/selinux/load` 这个策略写接口锁死了，任何写入都返回 `ENOMEM(12)`。
所以凡是**需要在运行时修改 SELinux 策略**的工具（frida-server、setenforce、magiskpolicy --live）全部失效。

这是 frida 官方的老问题，不是你这台机器独有：
- [frida#1039 — huawei p20 Unable to save SELinux policy](https://github.com/frida/frida/issues/1039)
- [frida#1023 — PTRACE_POKEDATA head failed: 5 | HUAWEI](https://github.com/frida/frida/issues/1023)

> 注意：**Magisk 模块的 `sepolicy.rule` 在开机阶段是能生效的**（Riru/EdXposed 就靠它），
> 但那是开机早期由 magiskd 写入，运行期再写就一律失败。

**所以本教程走 "Frida Gadget" 路线。**

---

## 1. 环境清单（都已装好）

### 手机端

| 东西 | 位置 / 说明 |
|---|---|
| Root | Magisk 20.1，`su -c id` → uid=0 |
| frida-server | `/data/adb/frida/frida-server`（**装了，但用不了，留着做纪念**） |
| tcpdump 4.99.7 | `/data/data/com.termux/files/usr/bin/tcpdump` |
| 系统 CA 证书 | `/system/etc/security/cacerts/037aaf60.0`（mitmproxy CA） |
| EdXposed Manager | 桌面「EdXposed Ma..」，框架已激活 |
| MT管理器 | 桌面「MT管理器」 |
| Termux | SSH 端口 8022，用户名 `u0_a123`，密码 `termux2026` |

### 电脑端

| 工具 | 路径 / 版本 |
|---|---|
| Python | `C:\Windows\py.exe`（3.11.9） |
| frida | 17.24.3 |
| frida-tools | 14.11.0 |
| objection | 1.12.5 |
| adb | `C:\Users\wangyang\AppData\Local\Android\Sdk\platform-tools\adb.exe` |
| zipalign / apksigner / aapt | `...\Android\Sdk\build-tools\36.0.0\` |
| Java | JDK 17（`C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot`） |
| apktool | 3.0.3（`G:\DeepSeek Harness\Root\tools\apktool\apktool.bat`） |
| plink | `G:\DeepSeek Harness\Root\tools\plink.exe`（备用 SSH 客户端） |

**新开 PowerShell 时先把工具加进 PATH：**
```powershell
$env:PATH += ";C:\Users\wangyang\AppData\Local\Android\Sdk\platform-tools"
$env:PATH += ";C:\Users\wangyang\AppData\Local\Android\Sdk\build-tools\36.0.0"
$env:PATH += ";C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot\bin"
$env:PATH += ";G:\DeepSeek Harness\Root\tools\apktool"
$env:PATH += ";C:\Users\wangyang\AppData\Local\Programs\Python\Python311\Scripts"
```
加完之后 `adb` / `frida-ps` / `objection` / `apktool` / `java` 都能直接敲。

---

## 2. 拼图一：让 App 信任你的抓包证书（系统级 CA）

Android 7 以后，App 默认**不信任用户手动装的证书**，只信 `/system/etc/security/cacerts` 里的。
本机已经用 Magisk 模块 `cacerts` 把 mitmproxy 的 CA 挂进去了：

```bash
ls -l /system/etc/security/cacerts/037aaf60.0     # 应该能看到
```

### 换成 Charles / Fiddler / Burp 的证书

```bash
# ① 电脑上把证书导出成 PEM（比如 ca.pem），算哈希
#    Git Bash / WSL 里执行：
openssl x509 -inform PEM -subject_hash_old -in ca.pem | head -1
#    假设输出 9a5ba575

# ② 改名成 <hash>.0，推到手机
#    mv ca.pem 9a5ba575.0
adb push 9a5ba575.0 /data/local/tmp/

# ③ 放进 cacerts 模块（不是直接写 /system！）
adb shell su -c 'cp /data/local/tmp/9a5ba575.0 /data/adb/modules/cacerts/system/etc/security/cacerts/'
adb shell su -c 'chmod 644 /data/adb/modules/cacerts/system/etc/security/cacerts/9a5ba575.0'
adb shell su -c 'chcon u:object_r:magisk_file:s0 /data/adb/modules/cacerts/system/etc/security/cacerts/9a5ba575.0'

# ④ 重启
adb reboot
```

> ⚠️ 文件名**必须**是 `<subject_hash_old>.0`（8 位小写十六进制 + `.0`），否则系统不认。
> ⚠️ **不要**去 `mount -o rw,remount /system` —— 本机 /system 是只读 erofs，改不动，而且 Magisk 模块挂载是更好的做法。
> ⚠️ **不用**再装 MoveCertificate / Conscrypt Trust User Certs，原理和 `cacerts` 模块一样，重复。

**删除某张证书**：把对应文件从模块目录删掉，重启即可。

---

## 3. 拼图二：代理抓包（跨网段也能用）

### 3.1 关键技巧：`adb reverse`

你这台电脑在 `192.168.9.x`，手机在 `192.168.5.x`，**不在同一个局域网**，手机直连不到电脑的代理端口。

**解决办法：用 `adb reverse` 把电脑的端口"反向"映射到手机的 127.0.0.1。**

```powershell
# 电脑上执行：把电脑的 8080 映射成手机上的 127.0.0.1:8080
adb reverse tcp:8080 tcp:8080
adb reverse --list        # 确认：(reverse) tcp:8080 tcp:8080

# 让手机全局走这个代理
adb shell settings put global http_proxy 127.0.0.1:8080
```

取消代理：
```powershell
adb shell settings put global http_proxy :0
adb reverse --remove-all
```

### 3.2 用 mitmproxy（命令行，最方便）

```powershell
# 电脑上
pip install mitmproxy          # 或者用 py -m pip install mitmproxy
mitmweb --listen-port 8080     # 会打开浏览器界面 http://127.0.0.1:8081
```

### 3.3 用 Charles / Fiddler

1. 电脑上设置监听端口 **8080**，勾选 "Allow remote clients"
2. 按 3.1 建立 `adb reverse` 并设置手机代理
3. 证书用第 2 节的方法装进系统区
4. 手机上打开目标 App，电脑上就能看到明文 HTTPS

### 3.4 只给单个 App 设代理（不动全局）

部分 App 不认全局代理，可以改用 **PCAPdroid**（见第 7 节），或者在目标 App 里用 Frida 改它的代理设置。

---

## 4. 拼图三：Frida Gadget（本机唯一可用的 Frida 路线）⭐

### 4.1 原理对比

| | frida-server | Frida Gadget |
|---|---|---|
| 工作方式 | 外部进程注入目标 App | 把 `libfrida-gadget.so` 打进 APK，App 自己加载 |
| 需要改 SELinux | ✅ 需要 → **本机不行** | ❌ 不需要 → **本机可行** |
| 需要重装 App | ❌ | ✅（签名变了要重装） |
| 适用 | 通用 | 需要 patch 的目标 App |

### 4.2 完整流程

```powershell
# ① 找到目标 App 的 APK 路径并拉下来
adb shell pm path com.example.app
#    → package:/data/app/~~xxxx/com.example.app-yyyy/base.apk
adb pull /data/app/~~xxxx/com.example.app-yyyy/base.apk target.apk

# ② 打补丁
#    -a arm64-v8a  指定架构（本机是 arm64-v8a）
#    -N            注入 network_security_config.xml，让 App 信任用户 CA（抓包必加！）
#    -d            顺便把 android:debuggable 设成 true（可选）
objection patchapk -s target.apk -a arm64-v8a -N

#    产物：target.objection.apk

# ③ 卸载原版，装补丁版（签名变了，必须先卸）
adb uninstall com.example.app
adb install target.objection.apk

# ④ 启动 App（gadget 会自动加载并挂起/监听）
adb shell am start -n com.example.app/.MainActivity

# ⑤ 连接
frida-ps -U                     # 列表里应该出现 Gadget
objection -g com.example.app explore
# 或
frida -U -n Gadget
```

**实测记录**（拿 Termux:Boot 做的小样）：
```
Unpacking tb.apk
App does not have android.permission.INTERNET, attempting to patch...
Injecting permission: android.permission.INTERNET
Creating XML res path: ...\res\xml
Copying network_security_config.xml...
Reading smali from: .../BootActivity.smali
Injecting loadLibrary call at line: 6
Creating library path: ...\lib\arm64-v8a
Copying Frida gadget to libs path...
Rebuilding the APK with the frida-gadget loaded...
Zipalign completed / Signed the APK
→ tb.objection.apk
```

### 4.3 让 Gadget 监听网络端口（可选，方便远程调试）

默认 Gadget 走 USB。如果想让电脑通过网络连（例如手机不在同一网段但能互通），
写一个配置文件 `gadget.json`：

```json
{
  "interaction": {
    "type": "listen",
    "address": "0.0.0.0",
    "port": 27042,
    "on_load": "resume"
  }
}
```

打补丁时指定：
```powershell
objection patchapk -s target.apk -a arm64-v8a -N -c gadget.json
```

连接：
```powershell
frida -H 192.168.5.16:27042 -n Gadget
```

---

## 5. 拼图四：objection 实战

### 5.1 常用命令速查（在 `objection -g <包名> explore` 的交互里敲）

| 命令 | 作用 |
|---|---|
| `android sslpinning disable` | **解除 SSL Pinning**（最常用） |
| `android root disable` | 隐藏 root 检测 |
| `android root simulate` | 假装有 root |
| `android hooking list classes` | 列出所有类 |
| `android hooking search classes <关键字>` | 搜索类 |
| `android hooking list class_methods <类名>` | 列出某类的方法 |
| `android hooking watch class_method <类>.<方法> --dump-args --dump-return --dump-backtrace` | **实时监控方法调用和参数** |
| `android hooking set return_value <类>.<方法> false` | 强制某方法返回指定值 |
| `memory list modules` | 列出加载的 so |
| `memory list exports <so名>` | 列出 so 的导出符号 |
| `android intent launch_activity <Activity>` | 启动指定 Activity |
| `env` | 查看 App 运行环境 |
| `jobs list` / `jobs kill <id>` | 管理 hook 任务 |
| `exit` | 退出 |

### 5.2 典型用法：一条命令解除 SSL Pinning

```powershell
objection -g com.example.app explore
# 进去后敲：
android sslpinning disable
```

它会自动 hook 掉 OkHttp / TrustManager / Conscrypt / Appmattus 等常见 pinning 实现。

### 5.3 直接跑 Frida 脚本（不用交互）

```javascript
// unpin.js —— 通用 SSL Pinning 绕过
Java.perform(function () {
    // 1. 干掉 OkHttp 的 CertificatePinner
    try {
        var CertificatePinner = Java.use('okhttp3.CertificatePinner');
        CertificatePinner.check.overload('java.lang.String', 'java.util.List').implementation = function (a, b) {
            console.log('[+] OkHttp pinning bypassed: ' + a);
            return;
        };
    } catch (e) { console.log('[-] no OkHttp'); }

    // 2. 干掉 X509TrustManager 的所有校验
    try {
        var X509TrustManager = Java.use('javax.net.ssl.X509TrustManager');
        var SSLContext = Java.use('javax.net.ssl.SSLContext');
        var TrustManager = Java.registerClass({
            name: 'com.dsh.TrustAll',
            implements: [X509TrustManager],
            methods: {
                checkClientTrusted: function (chain, authType) {},
                checkServerTrusted: function (chain, authType) {},
                getAcceptedIssuers: function () { return []; }
            }
        });
        var TrustManagers = [TrustManager.$new()];
        var SSLContext_init = SSLContext.init.overload(
            '[Ljavax.net.ssl.KeyManager;', '[Ljavax.net.ssl.TrustManager;', 'java.security.SecureRandom');
        SSLContext_init.implementation = function (km, tm, sr) {
            console.log('[+] SSLContext.init hooked');
            SSLContext_init.call(this, km, TrustManagers, sr);
        };
    } catch (e) { console.log('[-] TrustManager hook failed: ' + e); }

    // 3. 打印所有网络请求（可选）
    try {
        var URL = Java.use('java.net.URL');
        URL.openConnection.overload().implementation = function () {
            console.log('[URL] ' + this.toString());
            return this.openConnection();
        };
    } catch (e) {}
});
```

运行：
```powershell
frida -U -n Gadget -l unpin.js
# 或者 gadget 已经在跑：
frida -U -f com.example.app -l unpin.js
```

---

## 6. 拼图五：EdXposed（不重打包就能 Hook）

**优点**：不用改 APK、不用重装，装上模块勾选目标 App 重启即可。
**缺点**：只能用在已 Root 且有 Xposed 框架的机器上（本机已就绪）。

### 6.1 装模块

1. 下载 Xposed 模块 APK（例如 **TrustMeAlready**）
2. 安装到手机
3. 打开 **EdXposed Manager** → 左侧「模块」→ 勾选该模块
4. **重启手机**
5. 打开模块 App 配置要作用的范围

### 6.2 抓包相关的推荐模块

| 模块 | 作用 |
|---|---|
| **TrustMeAlready** | SSL Pinning 绕过（JustTrustMe 的维护版，Android 8~11 通用） |
| **SSLUnpinning** | 同类，备选 |
| **JustTrustMe** | ⚠️ 2016 年老版本，Android 9 上大面积失效，**不推荐** |
| **XPrivacyLua** | 隐私沙盒（喂假数据） |

### 6.3 与 Frida 的分工

- **EdXposed**：一次配置，长期生效，适合"装一次一直用"
- **Frida Gadget**：按需注入，脚本可随时改，适合"临时深挖某个 App"

---

## 7. 拼图六：tcpdump 被动抓包（抓不走代理的流量）

代理抓包有个盲区：**不遵守系统代理的 App**（很多 App 会绕过）。这时候用 tcpdump 在网卡层抓。

### 7.1 抓包

```powershell
# 电脑上执行，抓包存到手机 /sdcard
adb shell su -c 'LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib /data/data/com.termux/files/usr/bin/tcpdump -i any -s 0 -w /sdcard/cap.pcap'

# 抓到够了按 Ctrl+C，然后拉回电脑
adb pull /sdcard/cap.pcap
# 用 Wireshark 打开
```

### 7.2 常用参数

| 参数 | 含义 |
|---|---|
| `-i any` | 所有网卡（WiFi + 移动网络 + 回环） |
| `-s 0` | 抓完整包（不截断） |
| `-c 100` | 抓 100 个包就停 |
| `-w file.pcap` | 写入文件 |
| `-r file.pcap` | 读取文件 |
| `-nn` | 不解析主机名和端口名（更快） |
| `port 443` | 只抓 HTTPS |
| `host 1.2.3.4` | 只抓某个 IP |

### 7.3 在手机 Termux 里直接抓

```bash
# Termux 里（需要 su，Magisk 会弹窗，点允许）
su -c 'LD_LIBRARY_PATH=$PREFIX/lib $PREFIX/bin/tcpdump -i any -w /sdcard/cap.pcap'
```

### 7.4 更省事的替代：PCAPdroid

**PCAPdroid** 是一个 App，用 VPN 方式接管流量，**免 root**：
- 能抓到所有 App 的流量（包括不走代理的）
- 可以直接导出 pcap 给 Wireshark
- 也内置了 mitm 解密功能
- 缺点：VPN 模式和某些 App 的 VPN 检测冲突

---

## 8. 组合拳：三个典型场景

### 场景 A：普通 App 抓 HTTPS（最简单）

```powershell
adb reverse tcp:8080 tcp:8080
adb shell settings put global http_proxy 127.0.0.1:8080
mitmweb --listen-port 8080        # 电脑上另开一个窗口
# 手机上打开目标 App 操作
# 电脑 mitmweb 界面里就能看到明文
```

### 场景 B：有 SSL Pinning 的 App

```powershell
# 路线 1（推荐，快）：Frida Gadget
adb shell pm path com.target.app
adb pull <上面输出的路径> target.apk
objection patchapk -s target.apk -a arm64-v8a -N
adb uninstall com.target.app
adb install target.objection.apk
adb shell am start -n com.target.app/.MainActivity
objection -g com.target.app explore
#   进去后敲：android sslpinning disable

# 路线 2（不重装）：EdXposed
#   装 TrustMeAlready → EdXposed Manager 勾选 → 重启 → 模块里勾目标 App
```
然后再按场景 A 设置代理。

### 场景 C：抓不走代理的流量 / 非 HTTP 协议

```powershell
adb shell su -c 'LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib /data/data/com.termux/files/usr/bin/tcpdump -i any -s 0 -w /sdcard/cap.pcap'
# 操作 App
# Ctrl+C 后：
adb pull /sdcard/cap.pcap
# Wireshark 打开；如果是 TLS，再配合场景 A/B 的证书+Frida 才有明文
```

---

## 9. 常见问题

| 问题 | 解决 |
|---|---|
| `frida-ps -U` 没反应/卡住 | 本机没有可用的 frida-server。用 Gadget 路线，或先确认 Gadget 已随 App 启动 |
| `objection patchapk` 报找不到 adb / apktool | 按第 1 节把路径加进 PATH |
| 补丁版 App 装不上（签名冲突） | 先 `adb uninstall <包名>`；数据会丢，先备份 |
| 装了证书 App 还是报证书错误 | 该 App 有 SSL Pinning → 走场景 B |
| App 完全不发请求 | 它可能绕过了系统代理 → 走场景 C |
| 手机和电脑不同网段 | 用 `adb reverse`（第 3.1 节） |
| `setenforce 0` 报 Invalid argument | 华为锁死，正常现象，别折腾 |
| `pm` 命令报 `Failed transaction` | 华为限制：**不要用 `su -c` 跑 `pm`**，直接用 `adb shell pm ...` |
| Termux 里 `su` 弹窗 | 在 Magisk Manager → 超级用户里给 Termux 授权 |

---

## 10. 一句话总结

**这台机器的抓包链路是：**
```
系统 CA 证书（cacerts 模块）
        +
代理（adb reverse + mitmproxy/Charles）
        +
绕过 SSL Pinning（Frida Gadget + objection，或 EdXposed + TrustMeAlready）
        +
兜底抓包（tcpdump / PCAPdroid）
```
**Frida-server 走不通（华为锁 SELinux），但 Frida Gadget 完全可用，功能一点不少。**

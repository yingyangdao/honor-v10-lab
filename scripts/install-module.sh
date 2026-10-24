#!/system/bin/sh
# Magisk 模块安装器（兼容 Magisk 20.1 —— 20.1 没有 magisk --install-module）
# 用法: su -c 'sh install-module.sh /data/local/tmp/xxx.zip'
ZIP="$1"
[ -f "$ZIP" ] || { echo "用法: sh $0 <module.zip>"; exit 1; }

BB=/system/bin/busybox
[ -x "$BB" ] || BB=/data/adb/magisk/busybox
[ -x "$BB" ] || { echo '找不到 busybox'; exit 1; }

BBDIR=/dev/.bb
mkdir -p $BBDIR
cp -f $BB $BBDIR/busybox
chmod 755 $BBDIR/busybox
$BBDIR/busybox --install -s $BBDIR 2>/dev/null
export PATH="$BBDIR:$PATH"

export BOOTMODE=true
export MAGISK_VER=20.1
export MAGISK_VER_CODE=20100
export ARCH=arm64
export IS64BIT=true
export API=28
export TMPDIR=/dev/tmp
export MAGISKTMP=/sbin/.magisk
export NVBASE=/data/adb

T=/dev/.mi
rm -rf $T; mkdir -p $T
unzip -o "$ZIP" 'META-INF/com/google/android/update-binary' -d $T >/dev/null 2>&1
[ -f "$T/META-INF/com/google/android/update-binary" ] || { echo '不是有效的 Magisk 模块 zip'; exit 1; }

sh $T/META-INF/com/google/android/update-binary 3 1 "$ZIP"
rc=$?
echo "=== exit=$rc ==="
ls /data/adb/modules
exit $rc
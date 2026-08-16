#!/usr/bin/env bash
#===============================================================================
# check-artifacts.sh — CI 产物目录校验（D4 · 镜像三件套 + GPL 归档完整性）
#
# 用法： bash build/check-artifacts.sh <artifact-dir> <device>
#   <artifact-dir>  artifacts/<runid>/<device>/ 下解包后的目录（含 .itb / buildinfo）
#   <device>        gemtek_xr1710g-ubi | gemtek_w1700k-ubi
#
# 校验项（镜像 CI 的「校验固件产物」步骤 + D4 归档口径）：
#   1. 三件套 .itb 按类别通配（sysupgrade / initramfs-recovery / chainload-uboot）——
#      chainload-uboot.itb 为社区未发布、我们独有交付，必须在场
#   2. sha256sums / config.buildinfo / feeds.buildinfo / version.buildinfo（GPL+可复现归档）
#   3. 现场导出 config（openwrt-...-<device>.config）
#   4. 输出每件 .itb 的 sha256（供 D6 闪光卡与真机刷写前自检）
#
# 退出码：0 = 全部 PASS；1 = 有缺失（列出明细）
#===============================================================================
set -u
DIR="${1:?用法: check-artifacts.sh <artifact-dir> <device>}"
DEV="${2:?用法: check-artifacts.sh <artifact-dir> <device>}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FAIL=0

echo "== $TS | device=$DEV | dir=$DIR =="
for cat in sysupgrade initramfs-recovery chainload-uboot; do
  hit="$(ls "$DIR"/openwrt-airoha-an7581-"$DEV"-*"$cat"*.itb 2>/dev/null | head -1)"
  if [ -n "$hit" ]; then
    sha="$(sha256sum "$hit" | cut -c1-16)"
    echo "PASS | $cat | $(basename "$hit") | sha256=$sha…"
  else
    echo "FAIL | $cat | 缺失（openwrt-airoha-an7581-$DEV-*${cat}*.itb 未找到）"
    FAIL=1
  fi
done
for f in sha256sums config.buildinfo feeds.buildinfo version.buildinfo "openwrt-airoha-an7581-$DEV.config"; do
  if [ -s "$DIR/$f" ]; then echo "PASS | $f"; else echo "FAIL | $f 缺失/为空"; FAIL=1; fi
done

echo "== sha256 全表（闪烁/刷机核对） =="
( cd "$DIR" && sha256sum openwrt-airoha-an7581-"$DEV"-*.itb 2>/dev/null ) | sed 's/^/  /'

echo "== check-artifacts summary: $([ "$FAIL" -eq 0 ] && echo ALL-PASS || echo FAIL=$FAIL) =="
[ "$FAIL" -eq 0 ]
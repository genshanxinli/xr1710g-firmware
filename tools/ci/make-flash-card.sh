#!/usr/bin/env bash
#===============================================================================
# make-flash-card.sh — 从已校验产物目录生成 D6 首刷闪光卡（sha256 核对版）
#
# 用法： bash tools/ci/make-flash-card.sh <run-id> [<device=gemtek_xr1710g-ubi>]
# 前置： tools/ci/fetch-artifacts.sh <run-id> 已跑（build/artifacts/<runid>/<device>/）
# 产物： docs/sop/flash-card-<runid>.md（人工执行版，含 sha256 表 + YYH 兜底）
#===============================================================================
set -u
RUNID="${1:?用法: make-flash-card.sh <run-id> [device]}"
DEV="${2:-gemtek_xr1710g-ubi}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT/build/artifacts/$RUNID/$DEV"
OUT="$ROOT/docs/sop/flash-card-$RUNID.md"
[ -d "$DIR" ] || { echo "产物目录不存在：$DIR（先跑 fetch-artifacts.sh）" >&2; exit 2; }

{
cat <<EOF
# 闪光卡 · XR1710G 首刷（D6 人工放行）· run $RUNID

> 由 tools/ci/make-flash-card.sh 生成（$(date -u +%Y-%m-%dT%H:%M:%SZ)）。
> 红线：永不碰 bootloader 槽（一机一路线）；刷前核对 sha256；失败走 YYH 恢复页
> （docs/sop/brick-recovery.md）。刷写 = 人工动作（人类最小集）。

## 1. 镜像三件套与 sha256（<device=$DEV>）

| 件 | 文件名 | sha256 |
|---|---|---|
EOF
for cat in sysupgrade initramfs-recovery chainload-uboot; do
  f="$(ls "$DIR"/openwrt-airoha-an7581-"$DEV"-*"$cat"*.itb 2>/dev/null | head -1)"
  [ -n "$f" ] || continue
  echo "| $cat | $(basename "$f") | $(sha256sum "$f" | cut -d' ' -f1) |"
done
cat <<EOF

> 刷前核对：\`sha256sum <文件>\` 必须等于上表值（与 sha256sums 文件交叉核对）。

## 2. 人工步骤（SSH 192.168.123.1）

1. 确认社区线可用镜像已备份到安全位置（回退素材）。
2. \`scp <sysupgrade.itb> root@192.168.123.1:/tmp/\`
3. 设备上核对：\`sha256sum /tmp/<sysupgrade.itb>\`
4. \`sysupgrade -v /tmp/<sysupgrade.itb>\`（保持供电稳定；完成自动重启）
5. 重启后验证：\`cat /etc/openwrt_release\` / \`ip -br addr\`（br-lan 192.168.123.1/24）
   / \`uname -r\`（应 6.18.44 系，异于旧线 6.18.41）
6. 失联兜底：**按 reset 3s+ → YYH http-uboot 恢复页（192.168.255.1）→ HTTP 恢复**。

## 3. 回报给 AI

- 刷写命令输出尾部 / 重启是否成功
- §2.5 三条验证输出
- 异常描述（若有）；sysupgrade 拒绝时**不要强刷**（-F 禁用），贴错误回报
EOF
} > "$OUT"
echo "闪光卡已生成：$OUT"
head -12 "$OUT"
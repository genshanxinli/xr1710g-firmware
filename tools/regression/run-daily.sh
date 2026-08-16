#!/usr/bin/env bash
#===============================================================================
# run-daily.sh — 真机每日回归驱动（D7–D13 循环骨架）
#
# 流程：
#   1. 冒烟：tools/regression/smoke.sh（只读，Q12-a 全项）
#   2. 条件全量：路由器装了 bash 时跑 tools/metrics/collect.sh --host 全模块
#      （NPU 指标 v0 回填；iperf3 只出模板不自动测速）
#   3. 报告落盘 docs/tracking/regression-<date>.md（含时间戳与汇总）
#   4. 汇总行（stdout），FAIL 计数决定退出码
#
# 用法：
#   bash tools/regression/run-daily.sh              # 默认日期报告
#   bash tools/regression/run-daily.sh --no-metrics # 跳过 collect.sh
#   bash tools/regression/run-daily.sh --out <file> # 自定义报告文件
#
# 红线：全部只读采集；不刷机、不写设备配置（刷写走 D6 闪光卡人工流程）。
#===============================================================================
set -u
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DATE="$(date -u +%Y-%m-%d)"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/tracking/regression-$DATE.md"
DO_METRICS=1

while [ $# -gt 0 ]; do
  case "$1" in
    --no-metrics) DO_METRICS=0; shift ;;
    --out) OUT="${2:-}"; shift 2 ;;
    *) echo "未知参数 $1" >&2; exit 2 ;;
  esac
done

# 接入助手
SSH_CMD=("$HOME/.local/bin/xr1710g-ssh")
[ -x "${SSH_CMD[0]}" ] || { echo "无 xr1710g-ssh 助手" >&2; exit 2; }

echo "# XR1710G 真机回归 · $TS" > "$OUT"
echo > "$OUT"

echo "== [1/3] 冒烟 =="
SMOKE_LOG="$(mktemp)"
if bash "$ROOT/tools/regression/smoke.sh" 2>"$SMOKE_LOG"; then SMOKE_RC=0; else SMOKE_RC=$?; fi
SUMMARY="$(grep 'smoke summary' "$SMOKE_LOG")"
echo "$SUMMARY"
echo "## 冒烟（rc=$SMOKE_RC）" >> "$OUT"
echo '```' >> "$OUT"
bash "$ROOT/tools/regression/smoke.sh" >> "$OUT" 2>/dev/null || true
echo '```' >> "$OUT"; echo >> "$OUT"

echo "== [2/3] NPU 指标回填（collect.sh 全量） =="
HAS_BASH="$("${SSH_CMD[@]}" 'command -v bash 2>/dev/null || echo no-bash' 2>/dev/null | tail -1)"
if [ "$DO_METRICS" = 1 ] && [ -n "$HAS_BASH" ] && [ "$HAS_BASH" != "no-bash" ]; then
  bash "$ROOT/tools/metrics/collect.sh" --host root@192.168.123.1 -o "$OUT.metrics.tsv" 2>"$OUT.metrics.summary"
  echo "collect.sh 完成：$(tail -1 "$OUT.metrics.summary")"
  echo "## 指标回填（collect.sh v0）" >> "$OUT"
  echo "TSV: $OUT.metrics.tsv（runs/ 归档约定见 docs/metrics/runs/README.md）" >> "$OUT"
else
  echo "跳过指标：bash=${HAS_BASH:-未知}（D0-5 未装/未传 --no-metrics）"
  echo "## 指标回填：跳过（路由器无 bash，D0-5 待装）" >> "$OUT"
fi
echo >> "$OUT"

echo "== [3/3] 报告落盘 =="
echo "report: $OUT"
echo "$TS | smoke_rc=$SMOKE_RC | $SUMMARY" >> "$ROOT/docs/tracking/regression-runs.log"

echo "== run-daily done =="
[ "$SMOKE_RC" -eq 0 ]
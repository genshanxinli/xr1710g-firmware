#!/usr/bin/env bash
#===============================================================================
# run-logs.sh — 下载 Actions job 日志（D2 失败分析用）
#
# 用法： bash tools/ci/run-logs.sh <run-id> [job-id]
#   job-id 省略时列全部 job（含 id）；日志 zip 落 build/artifacts/<runid>/logs/
# 依赖：git 凭据 PAT（GET 只读）。
#===============================================================================
set -u
RUNID="${1:?用法: run-logs.sh <run-id> [job-id]}"
REPO="genshanxinli/xr1710g-firmware"
TOKEN="$(printf 'protocol=https\nhost=github.com\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$TOKEN" ] || { echo "无凭据" >&2; exit 2; }
AUTH="Authorization: Bearer $TOKEN"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LDIR="$ROOT/build/artifacts/$RUNID/logs"
mkdir -p "$LDIR"

JOBS="$(curl -s -H "$AUTH" "https://api.github.com/repos/$REPO/actions/runs/$RUNID/jobs" \
  | python3 -c "
import json,sys
for j in json.load(sys.stdin).get('jobs',[]):
    print(j['id'], j['name'])
")"
[ -n "$JOBS" ] || { echo "无 job 信息" >&2; exit 2; }
echo "$JOBS"
JOBID="${2:-}"
if [ -n "$JOBID" ]; then
  curl -sL -H "$AUTH" -o "$LDIR/$JOBID-logs.zip" \
    "https://api.github.com/repos/$REPO/actions/jobs/$JOBID/logs"
  echo "日志：$LDIR/$JOBID-logs.zip（unzip 后看 build.log 尾 / conflict-archive/）"
fi
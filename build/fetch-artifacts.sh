#!/usr/bin/env bash
#===============================================================================
# fetch-artifacts.sh — 从 GitHub Actions run 拉取固件产物并校验（D3/D4 管线）
#
# 用法：
#   bash build/fetch-artifacts.sh <run-id>          # 指定 run（API 全查下载）
#   bash build/fetch-artifacts.sh                   # 最新 push 触发的 build run
#
# 依赖：git 凭据（credential fill 取 PAT）+ curl + unzip；产物按
#   artifacts/<runid>/<device>/ 落盘；随即跑 build/check-artifacts.sh 校验。
# 红线：仅下载名为 firmware-* 的产物（不碰 build-log-*）；全部只读。
#===============================================================================
set -u
REPO="genshanxinli/xr1710g-firmware"
TOKEN="$(printf 'protocol=https\nhost=github.com\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$TOKEN" ] || { echo "无法取得 GitHub 凭据（git credential fill）" >&2; exit 2; }
AUTH="Authorization: Bearer $TOKEN"
WORK="$(cd "$(dirname "$0")/.." && pwd)/build/artifacts"
mkdir -p "$WORK"

RUNID="${1:-}"
if [ -z "$RUNID" ]; then
  RUNID="$(curl -s -H "$AUTH" "https://api.github.com/repos/$REPO/actions/runs?per_page=10" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('workflow_runs',[]):
    if r['name']=='build' and r['event']=='push' and r['status']=='completed':
        print(r['id']); break
")"
  [ -n "$RUNID" ] || { echo "未找到已完成的 push 触发 build run" >&2; exit 2; }
fi
echo "run=$RUNID"

curl -s -H "$AUTH" "https://api.github.com/repos/$REPO/actions/runs/$RUNID/artifacts" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('artifacts',[]):
    n=a['name']
    if n.startswith('firmware-'): print(a['id'], n)
" > "$WORK/.list.tmp"
[ -s "$WORK/.list.tmp" ] || { echo "该 run 无 firmware-* 产物（可能未完成或失败）" >&2; exit 2; }

while read -r AID NAME; do
  DEV="${NAME#firmware-}"
  TARGET_DIR="$WORK/$RUNID/$DEV"
  mkdir -p "$TARGET_DIR"
  zip="$WORK/$NAME.zip"
  curl -sL -H "$AUTH" -o "$zip" "https://api.github.com/repos/$REPO/actions/artifacts/$AID/zip"
  ( cd "$TARGET_DIR" && unzip -oq "$zip" && rm -f "$zip" )
  echo "-- check: $DEV --"
  bash "$WORK/../check-artifacts.sh" "$TARGET_DIR" "$DEV" || exit 1
done < "$WORK/.list.tmp"
rm -f "$WORK/.list.tmp"
echo "== fetch-artifacts done: artifacts/$RUNID/ =="
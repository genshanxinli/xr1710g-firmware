#!/usr/bin/env bash
#===============================================================================
# ci-status.sh — GitHub Actions 构建状态一键速查（跨会话工具）
#
# 用法：
#   bash tools/ci/ci-status.sh                    # 最新 push 触发的 build run
#   bash tools/ci/ci-status.sh <run-id>           # 指定 run
#
# 输出：run 状态/结论 + 每个 job 的当前步骤。只读（凭据仅用于 GET）。
#===============================================================================
set -u
REPO="genshanxinli/xr1710g-firmware"
TOKEN="$(printf 'protocol=https\nhost=github.com\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$TOKEN" ] || { echo "无法取得 GitHub 凭据" >&2; exit 2; }
AUTH="Authorization: Bearer $TOKEN"

RUNID="${1:-}"
if [ -z "$RUNID" ]; then
  RUNID="$(curl -s -H "$AUTH" "https://api.github.com/repos/$REPO/actions/runs?per_page=5" \
    | python3 -c "
import json,sys
for r in json.load(sys.stdin).get('workflow_runs',[]):
    if r['name']=='build' and r['event']=='push':
        print(r['id']); break
")"
fi
[ -n "$RUNID" ] || { echo "未找到 build run" >&2; exit 2; }

curl -s -H "$AUTH" "https://api.github.com/repos/$REPO/actions/runs/$RUNID" \
  | python3 -c "
import json,sys
r=json.load(sys.stdin)
print('run', r.get('id'), '|', r.get('status'), '|', r.get('conclusion'), '| created', r.get('created_at','')[:19])
"
curl -s -H "$AUTH" "https://api.github.com/repos/$REPO/actions/runs/$RUNID/jobs" \
  | python3 -c "
import json,sys
for j in json.load(sys.stdin).get('jobs',[]):
    cur=''
    for s in j.get('steps',[]):
        if s.get('status')=='in_progress': cur=s['name'][:46]
    print('  ', j['name'], '|', j['status'], '|', j['conclusion'] or '', '| now:', cur or '(complete)')
"
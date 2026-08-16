#!/usr/bin/env bash
# ============================================================================
# fetch.sh — XR1710G 自动跟进循环（M4）· 抓取阶段
#
# 覆盖盯梢源（见 docs/research/05-watchlist.md 与 03-frontier-dynamics.md 第 6 节）：
#   #1/#3  git.openwrt.org     main HEAD（git ls-remote）+ 定向日志
#           （git log --since=14d -- target/linux/airoha package/network/services/hostapd
#            package/kernel/mt76；浅克隆 --filter=blob:none 只取日志）
#   #4     GitHub 镜像        openwrt/openwrt  commits?path=target/linux/airoha&since=...
#   #5     GitHub 镜像        openwrt/mt76       commits?path=mt7996
#   #6     w1.fi              releases/ 目录抓取，grep hostapd 版本号
#   #14    downloads.openwrt.org  snapshots/targets/airoha/an7581/profiles.json
#   #14b   同上 an7583（盲区预判 2：AN7583 设备放量的镜像侧证据）
#   #15    downloads.openwrt.org  releases/ 目录 + 最新版 targets（预判 1：稳定版 airoha）
#   附加   GitHub API pulls/22397（构建触发信号）+ torvalds/linux dts/airoha（预判 3）
#
# 输出：docs/tracking/<YYYY-MM-DD>.raw/ 下每源一个原始文件 + 99_STATUS.tsv。
#      单源失败只记 SKIP（原因写入 STATUS/日志），绝不中断整批；全部失败 exit 1。
#
# 限流约定（写进 README 与 workflow）：
#   - GitHub API 未认证 60 次/时（按出口 IP）：本脚本每次运行恰 4 次（#4/#5/PR/linux-dts）。
#     失败就跳过、不重试轰炸（curl 无 --retry）；撞 403 时响应体落盘供 gh_msg 提取原因。
#   - 论坛 search.json ⩽1 次/分（否则 429）：本脚本不碰论坛，留人工/通知驱动。
#   - 恩山需登录：人工每周回填。
#
# 用法：bash scripts/tracking/fetch.sh [YYYY-MM-DD]   # 缺省 = 今天 UTC
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_ROOT="${ROOT}/docs/tracking"
UA='XR1710G-tracking/1.0 (M4 auto-follow-loop)'
GH_BASE='https://api.github.com/repos'
OPENWRT_GIT='https://git.openwrt.org/openwrt/openwrt.git'
W1FI_URL='https://w1.fi/releases/'
SNAP_BASE='https://downloads.openwrt.org/snapshots/targets/airoha'
REL_URL='https://downloads.openwrt.org/releases/'

DATE="${1:-$(date -u +%F)}"
if [[ ! "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "用法: $0 [YYYY-MM-DD]（缺省 = 今天 UTC）" >&2
    exit 2
fi

RAWDIR="${OUT_ROOT}/${DATE}.raw"
mkdir -p "$RAWDIR"
STATUS="$RAWDIR/99_STATUS.tsv"
LOG="$RAWDIR/00_fetch.log"
: > "$STATUS"
: > "$LOG"

# 日期工具走 python3，避免 GNU date -d 的跨平台差异
SINCE="$(python3 - "$DATE" <<'PY'
import datetime, sys
d = datetime.date.fromisoformat(sys.argv[1])
print((d - datetime.timedelta(days=14)).isoformat())
PY
)" || { echo "日期解析失败: $DATE" >&2; exit 2; }
SINCE30="$(python3 - "$DATE" <<'PY'
import datetime, sys
d = datetime.date.fromisoformat(sys.argv[1])
print((d - datetime.timedelta(days=30)).isoformat())
PY
)"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

note()   { echo "$(date -u +%H:%M:%SZ)  $*" >> "$LOG"; }
record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$STATUS"; }
OKN=0
fok()   { OKN=$((OKN+1)); record "$1" "OK" "-"; note "OK   $1"; }
fskip() { record "$1" "SKIP" "$2"; note "SKIP $1   $2"; }

# http_get <url> <outfile>：非 -f 抓取（错误体也落盘，供限流/404 排查），无自动重试
http_get() {
    local code
    code="$(curl -sSL --max-time 40 -A "$UA" -o "$2" -w '%{http_code}' "$1" 2>/dev/null)"
    [ "$code" = "200" ]
}

gh_msg() { # 从（可能失败的）响应体里捞 GitHub 错误信息（限流/404 原因）
    python3 - "$1" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    if isinstance(d, dict) and d.get('message'):
        print(str(d['message'])[:140])
except Exception:
    pass
PY
}

echo "== 抓取开始 $(date -u +%Y-%m-%dT%H:%M:%SZ)  窗口 ${SINCE}..${DATE}（14 天） =="
note "banner date=${DATE} window=${SINCE}..${DATE} clone_until=$(date -u -d "${SINCE} -16 days" +%F 2>/dev/null || echo n/a)"

# ---------------- 源 #1/#3：git.openwrt.org ----------------
if git ls-remote "$OPENWRT_GIT" refs/heads/main > "$RAWDIR/01_git_lsremote.txt" 2>>"$LOG"; then
    fok 01
else
    fskip 01 "git ls-remote 失败（网络/超时）"
fi

# 定向日志：浅克隆只取日志可用 --filter（blob:none + 单分支 + 不 checkout + 无 tag）
CLONE="$TMPD/owrt"
CLONE_RC=1
if command -v timeout >/dev/null 2>&1; then
    timeout 300 git clone --filter=blob:none --no-checkout --single-branch --branch main \
        --no-tags --shallow-since="30 days ago" "$OPENWRT_GIT" "$CLONE" >>"$LOG" 2>&1
    CLONE_RC=$?
else
    git clone --filter=blob:none --no-checkout --single-branch --branch main \
        --no-tags --shallow-since="30 days ago" "$OPENWRT_GIT" "$CLONE" >>"$LOG" 2>&1
    CLONE_RC=$?
fi
if [ "$CLONE_RC" -eq 0 ]; then
    LOGOUT="$RAWDIR/03_git_openwrt_log.txt"
    git -C "$CLONE" log --date=short --pretty=format:'%h %ad %s' --no-merges \
        --since="$SINCE" -- \
        target/linux/airoha package/network/services/hostapd package/kernel/mt76 \
        > "$LOGOUT" 2>>"$LOG"
    if [ -s "$LOGOUT" ] || git -C "$CLONE" rev-parse --verify HEAD >/dev/null 2>&1; then
        fok 03
    else
        fskip 03 "git log 无输出（克隆成功但窗口内无提交？）"
    fi
else
    fskip 03 "浅克隆失败 exit=$CLONE_RC（网络/超时），SKIP 保留不重试"
fi

# ---------------- 源 #4：GitHub 镜像 airoha 提交 ----------------
URL="${GH_BASE}/openwrt/openwrt/commits?path=target/linux/airoha&since=${SINCE}T00:00:00Z&per_page=30"
if http_get "$URL" "$RAWDIR/04_gh_airoha_commits.json"; then
    fok 04
else
    fskip 04 "$(gh_msg "$RAWDIR/04_gh_airoha_commits.json")"
fi

# ---------------- 源 #5：openwrt/mt76 mt7996 提交 ----------------
URL="${GH_BASE}/openwrt/mt76/commits?path=mt7996&since=${SINCE}T00:00:00Z&per_page=30"
if http_get "$URL" "$RAWDIR/05_gh_mt76_commits.json"; then
    fok 05
else
    fskip 05 "$(gh_msg "$RAWDIR/05_gh_mt76_commits.json")"
fi

# ---------------- 附加：PR #22397 状态（报告 ② 构建触发信号） ----------------
URL="${GH_BASE}/openwrt/openwrt/pulls/22397"
if http_get "$URL" "$RAWDIR/07_gh_pr22397.json"; then
    fok 07
else
    fskip 07 "$(gh_msg "$RAWDIR/07_gh_pr22397.json")"
fi

# ---------------- 附加：Linux 主线 dts/airoha（盲区预判 3） ----------------
URL="${GH_BASE}/torvalds/linux/commits?path=arch/arm64/boot/dts/airoha&since=${SINCE30}T00:00:00Z&per_page=30"
if http_get "$URL" "$RAWDIR/16_gh_linux_airoha_dts.json"; then
    fok 16
else
    fskip 16 "$(gh_msg "$RAWDIR/16_gh_linux_airoha_dts.json")"
fi

# ---------------- 源 #6：w1.fi hostapd 版本 ----------------
if http_get "$W1FI_URL" "$RAWDIR/06_w1fi_releases.html"; then
    grep -oE 'hostapd-[0-9]+(\.[0-9]+)+\.tar\.gz' \
        "$RAWDIR/06_w1fi_releases.html" | sed -E 's/^hostapd-//; s/\.tar\.gz$//' | sort -Vu \
        > "$RAWDIR/06_w1fi_hostapd_versions.txt"
    if [ -s "$RAWDIR/06_w1fi_hostapd_versions.txt" ]; then
        fok 06
    else
        fskip 06 "页面可达但未 grep 到 hostapd tarball"
    fi
else
    fskip 06 "w1.fi/releases/ 不可达"
fi

# ---------------- 源 #14：snapshot an7581 profiles.json ----------------
if http_get "$SNAP_BASE/an7581/profiles.json" "$RAWDIR/14_an7581_profiles.json"; then
    fok 14
else
    fskip 14 "an7581 profiles.json 不可达/404"
fi

# ---------------- 源 #14b：snapshot an7583 profiles.json（预判 2 证据） ----------------
if http_get "$SNAP_BASE/an7583/profiles.json" "$RAWDIR/14b_an7583_profiles.json"; then
    fok 14b
else
    fskip 14b "an7583 profiles.json 不可达/404（该 sub-target 或未出镜像）"
fi

# ---------------- 源 #15：官方 releases 目录 + 最新版 targets（预判 1 证据） ----------------
if http_get "$REL_URL" "$RAWDIR/15_releases_dir.txt"; then
    LATEST="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$RAWDIR/15_releases_dir.txt" | sort -Vu | sort -V | tail -1)"
    if [ -n "$LATEST" ]; then
        {
            echo "# probed release: ${LATEST}  (source: ${REL_URL})"
            echo "# 若 targets 列表出现 airoha = 稳定版镜像信号（预判 1）"
        } > "$RAWDIR/15b_latest_release_targets.txt"
        if curl -sSL --max-time 40 -A "$UA" \
            "https://downloads.openwrt.org/releases/${LATEST}/targets/" \
            -o "$TMPD/targets.html" 2>/dev/null; then
            grep -i 'airoha' "$TMPD/targets.html" >> "$RAWDIR/15b_latest_release_targets.txt" \
                || echo "NO_AIROHA_IN_TARGETS" >> "$RAWDIR/15b_latest_release_targets.txt"
            fok 15
        else
            fskip 15 "releases/${LATEST}/targets/ 探测失败"
        fi
    else
        fskip 15 "releases 目录无法解析版本号"
    fi
else
    fskip 15 "downloads.openwrt.org/releases/ 不可达"
fi

# ---------------- 汇总 ----------------
echo "== 抓取结束 $(date -u +%Y-%m-%dT%H:%M:%SZ)  OK=${OKN}  SKIP=$(grep -c $'\tSKIP\t' "$STATUS" || true) =="
note "done ok=${OKN} skipped=$(grep -c $'\tSKIP\t' "$STATUS" || true)"
echo "== 原始数据: $RAWDIR =="
[ "$OKN" -eq 0 ] && { echo "全部源抓取失败（疑似网络整体故障），exit 1 供 CI 判定" >&2; exit 1; }
exit 0
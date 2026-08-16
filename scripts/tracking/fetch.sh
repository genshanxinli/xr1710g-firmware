#!/usr/bin/env bash
# ============================================================================
# fetch.sh — XR1710G 自动跟进循环（M4）· 抓取阶段
#
# 覆盖盯梢源（见 docs/research/05-watchlist.md 与 03-frontier-dynamics.md 第 6 节）：
#   #1/#3  main HEAD（git ls-remote）+ 定向日志；多通道：GitHub 镜像 gh-git 主通道，
#           openwrt.org git / GitHub API / cgit 逐级回退（git.openwrt.org git 端点间歇故障）
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
#   - GitHub API 未认证 60 次/时（按出口 IP）：常规恰 4 次（#4/#5/PR/linux-dts）；
#     回退通道全爆时最坏再 +4（#01 commits/main 1 次 + #03 三路径 3 次）≤ 8 次，仍远低于 60/h。
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
GH_GIT='https://github.com/openwrt/openwrt.git'                 # 源 #1/#3 主通道（GitHub 镜像）
CGIT_BASE='https://git.openwrt.org/openwrt/openwrt'            # cgit 网页（回退：atom / 路径页）
OPENWRT_GIT='https://git.openwrt.org/openwrt/openwrt.git'      # 回退通道（git 端点间歇故障）
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

# ---------------- 源 #1/#3：main HEAD + 定向日志（多通道，回退链见 README「通道与回退链」） ----------------
# 源 #1：main HEAD。成功统一落盘 `<sha>\trefs/heads/main`（report.py 契约：只取首行 sha）。
git_ls_remote() { # 带 60s 超时的 ls-remote（无 timeout 命令时直接跑）
    if command -v timeout >/dev/null 2>&1; then
        timeout 60 git ls-remote "$1" "$2"
    else
        git ls-remote "$1" "$2"
    fi
}

fetch_head01() {
    local out="$RAWDIR/01_git_lsremote.txt" sha=""
    # 主通道：GitHub 镜像（ls-remote SHA 与源站一致）→ openwrt-git → GitHub API commits/main → cgit atom
    if git_ls_remote "$GH_GIT" refs/heads/main > "$out" 2>>"$LOG"; then
        fok 01; return 0
    fi
    note "01 主通道 gh-git ls-remote 失败 → 回退 openwrt-git"
    if git_ls_remote "$OPENWRT_GIT" refs/heads/main > "$out" 2>>"$LOG"; then
        fok 01; return 0
    fi
    note "01 openwrt-git ls-remote 失败 → 回退 GitHub API commits/main"
    if http_get "$GH_BASE/openwrt/openwrt/commits/main" "$TMPD/01_head_api.json"; then
        sha="$(python3 - "$TMPD/01_head_api.json" <<'PY' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1])).get('sha', ''))
except Exception:
    pass
PY
)"
        if [ -n "$sha" ]; then
            printf '%s\trefs/heads/main\n' "$sha" > "$out"
            fok 01; return 0
        fi
    fi
    note "01 gh-api commits/main 失败 → 回退 cgit atom"
    # cgit atom（git.openwrt.org 过滤页间歇 502）：首条 urn:sha1: 取 sha，502 允许重试 1 次
    local attempt=
    for attempt in 1 2; do
        if http_get "$CGIT_BASE/atom/?h=main" "$TMPD/01_head_atom.xml"; then
            sha="$(grep -oE 'urn:sha1:[0-9a-f]{40}' "$TMPD/01_head_atom.xml" | head -1 | cut -d: -f3)"
            if [ -n "$sha" ]; then
                printf '%s\trefs/heads/main\n' "$sha" > "$out"
                fok 01; return 0
            fi
            break
        fi
        grep -q '502 Bad Gateway' "$TMPD/01_head_atom.xml" 2>/dev/null \
            && note "01 cgit atom 502（attempt $attempt）→ 重试" || break
    done
    fskip 01 "四通道均失败（gh-git/openwrt-git/gh-api/cgit atom）"
}
fetch_head01

# 源 #3：定向日志。浅克隆只取日志可用 --filter（blob:none + 单分支 + 不 checkout + 无 tag）。
#   主通道 gh-git 克隆 → 回退 openwrt-git 克隆 → GitHub API 三路径 commits 重建 → cgit 路径页。
try_clone03() { # $1=url $2=dir → 0/1
    local url="$1" dir="$2"
    rm -rf "$dir"
    if command -v timeout >/dev/null 2>&1; then
        timeout 300 git clone --filter=blob:none --no-checkout --single-branch --branch main \
            --no-tags --shallow-since="30 days ago" "$url" "$dir" >>"$LOG" 2>&1
    else
        git clone --filter=blob:none --no-checkout --single-branch --branch main \
            --no-tags --shallow-since="30 days ago" "$url" "$dir" >>"$LOG" 2>&1
    fi
}

fetch_log03() {
    local LOGOUT="$RAWDIR/03_git_openwrt_log.txt"
    local CH='' CLONE=''
    if try_clone03 "$GH_GIT" "$TMPD/owrt-gh"; then
        CH='gh-git'; CLONE="$TMPD/owrt-gh"
    else
        note "03 主通道 gh-git 浅克隆失败 → 回退 openwrt-git"
        if try_clone03 "$OPENWRT_GIT" "$TMPD/owrt-owrt"; then
            CH='openwrt-git'; CLONE="$TMPD/owrt-owrt"
        fi
    fi
    if [ -n "$CH" ]; then
        {
            echo "# source: $CH"   # 审计痕迹；report.py 解析 03 时跳过 # 开头行
            # --abbrev=8：固定 8 位短 sha，避免源站(git)8 位 / GitHub 7 位漂移
            git -C "$CLONE" log --abbrev=8 --date=short --pretty=format:'%h %ad %s' --no-merges \
                --since="$SINCE" -- \
                target/linux/airoha package/network/services/hostapd package/kernel/mt76
            echo
        } > "$LOGOUT" 2>>"$LOG"
        if [ -s "$LOGOUT" ] || git -C "$CLONE" rev-parse --verify HEAD >/dev/null 2>&1; then
            fok 03; return 0
        fi
        fskip 03 "git log 无输出（克隆成功但窗口内无提交？）"; return 0
    fi

    note "03 双克隆通道失败 → 回退 GitHub API commits 重建日志"
    local ok=1 p= attempt=
    for p in target/linux/airoha package/network/services/hostapd package/kernel/mt76; do
        if http_get "${GH_BASE}/openwrt/openwrt/commits?path=${p}&since=${SINCE}T00:00:00Z&per_page=100" \
            "$TMPD/03_$(echo "$p" | tr '/' '_').json"; then
            :
        else
            ok=0
        fi
    done
    if [ "$ok" -eq 1 ]; then
        # 三路径合并重建 %h %ad %s 行：剔 Merge、按 sha 去重、新→旧排序
        if python3 - "$TMPD/03_target_linux_airoha.json" "$TMPD/03_package_network_services_hostapd.json" \
            "$TMPD/03_package_kernel_mt76.json" "$LOGOUT" <<'PY' 2>>"$LOG"
import json, sys
files, out = sys.argv[1:-1], sys.argv[-1]
seen, rows = set(), []
for p in files:
    try:
        data = json.load(open(p))
    except Exception:
        continue
    if not isinstance(data, list):
        continue
    for c in data:
        try:
            sha = c['sha']
            cm = c['commit']
            msg = (cm.get('message') or '').splitlines()[0].strip()
            dt = (cm.get('author', {}).get('date') or '')[:10]
        except Exception:
            continue
        if not msg or msg.lower().startswith('merge '):
            continue
        if sha in seen:
            continue
        seen.add(sha)
        rows.append((dt, sha[:8], msg))
rows.sort(key=lambda r: (r[0], r[1]), reverse=True)
with open(out, 'w', encoding='utf-8') as f:
    f.write('# source: gh-api\n')
    for dt, h, msg in rows:
        f.write(f'{h} {dt} {msg}\n')
PY
        then
            fok 03; return 0
        fi
    fi

    note "03 gh-api 失败 → 回退 cgit 路径页"
    # cgit log 页：log/?h=main&path=<路径>（& 是真 query 分隔符；;path= 会被判 Invalid branch 404）；
    # 响应体含 502 Bad Gateway 即跳过，允许 1 次重试；行级解析尽力而为（HTML 结构变化时降级 SKIP）
    local pages=() pfile=''
    for p in target/linux/airoha package/network/services/hostapd package/kernel/mt76; do
        pfile="$TMPD/03_cgit_$(echo "$p" | tr '/' '_').html"
        for attempt in 1 2; do
            if http_get "$CGIT_BASE/log/?h=main&path=${p}" "$pfile"; then
                pages+=("$pfile"); break
            fi
            grep -q '502 Bad Gateway' "$pfile" 2>/dev/null \
                && note "03 cgit 路径页 502（$p, attempt $attempt）→ 重试" || break
        done
    done
    if [ "${#pages[@]}" -gt 0 ] && python3 - "${pages[@]}" "$LOGOUT" <<'PY' 2>>"$LOG"
import re, sys
files, out = sys.argv[1:-1], sys.argv[-1]
seen, rows = set(), []
for p in files:
    try:
        h = open(p, encoding='utf-8', errors='replace').read()
    except Exception:
        continue
    for blk in re.findall(r'<tr>(.*?)</tr>', h, re.S):
        if '<th' in blk:
            continue
        dm = re.search(r"title='(\d{4}-\d{2}-\d{2})", blk)
        am = re.search(r"id=([0-9a-f]{40})'>([^<]+)</a>", blk)
        if not dm or not am:
            continue
        sha, subj = am.group(1), am.group(2).strip()
        if not subj or subj.lower().startswith('merge '):
            continue
        if sha in seen:
            continue
        seen.add(sha)
        rows.append((dm.group(1), sha[:8], subj))
if not rows:
    sys.exit(1)
rows.sort(key=lambda r: (r[0], r[1]), reverse=True)
with open(out, 'w', encoding='utf-8') as f:
    f.write('# source: cgit\n')
    for dt, h, msg in rows:
        f.write(f'{h} {dt} {msg}\n')
PY
    then
        fok 03; return 0
    fi
    fskip 03 "四通道均失败（gh-git/openwrt-git 克隆、gh-api、cgit 路径页）"
}
fetch_log03

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
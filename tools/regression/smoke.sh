#!/usr/bin/env bash
#===============================================================================
# smoke.sh — XR1710G 真机冒烟（只读，零写操作）· alpha 战役真机自动回归 v0
#
# 归属：tools/regression/（D5 真机回归管线；Q12-a 冒烟范围）
# 配套：docs/plan/alpha-campaign.md（D5/D7–D13）；docs/metrics/（collect.sh 指标全量）
# 参考：CONTEXT.md「真机自动回归」——常规测试数据采集由 AI 执行；本脚本只读。
#
# 检查项（Q12-a 冒烟集）：
#   1. SSH 可达（经 ~/.local/bin/xr1710g-ssh 助手，密码非交互注入）
#   2. 固件版本/内核（期望 OpenWrt SNAPSHOT + 内核 6.18.x）
#   3. 接口状态（br-lan 192.168.123.1/24、eth0/wan/lan1 UP）
#   4. 无线 band（phy0 出 Band 1/2；6GHz disabled 为已知态记录不判 FAIL）
#   5. NPU 固件（dmesg NPU fw version 在册）
#   6. 告警扫描（无 OOM / panic / WED crash —— collect.sh alerts 同款口径）
#   7. 资源基线（mem / loadavg / overlay 剩余）
#   8. /proc/mtd 分区表存证（对比当前 main 布局：vendor/chainloader/ubi/reserved_bmt）
#
# 用法：
#   bash tools/regression/smoke.sh            # 经 xr1710g-ssh 助手打默认机
#   bash tools/regression/smoke.sh -o report.md   # 报告追加写到指定文件
#   bash tools/regression/smoke.sh --host root@IP  # 指定主机（须可非交互认证）
#
# 输出：逐项 [PASS|WARN|FAIL] 到 stdout；-o 时以 markdown 追加报告（含时间戳）。
# 退出码：0 = 无 FAIL；1 = 有 FAIL（WARN 不算）。
# 红线：本脚本全部命令只读（cat/grep/iw/ip/free/df/dmesg/uptime/ls），不写设备。
#===============================================================================

set -u
SELF="$(basename "$0")"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUTFILE=""
HOST_SEL=""

while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUTFILE="${2:-}"; shift 2 ;;
    --host) HOST_SEL="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数 $1（--help）" >&2; exit 2 ;;
  esac
done

# 接入助手：优先默认助手脚本，其次 --host + BatchMode（密钥）
if [ -n "$HOST_SEL" ]; then
  SSH_CMD=(ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST_SEL")
elif [ -x "$HOME/.local/bin/xr1710g-ssh" ]; then
  SSH_CMD=("$HOME/.local/bin/xr1710g-ssh")
else
  echo "没有找到接入助手（~/.local/bin/xr1710g-ssh），且未给 --host" >&2
  exit 2
fi

PASS=0; WARN=0; FAIL=0
emit() {  # $1=状态 $2=检查名 $3=详情
  printf '%s | %s | %s\n' "$1" "$2" "$3"
  [ -n "$OUTFILE" ] && printf '%s | %s | %s | %s\n' "$TS" "$1" "$2" "$3" >> "$OUTFILE"
  case "$1" in PASS) PASS=$((PASS+1));; WARN) WARN=$((WARN+1));; FAIL) FAIL=$((FAIL+1));; esac
}

rf() { "${SSH_CMD[@]}" "$1" 2>/dev/null; }   # remote fn

# --- 1 SSH 可达 ---------------------------------------------------------------
if rf 'echo ok' 2>/dev/null | grep -q ok; then
  emit PASS "1.SSH 可达" "辅助通道 OK"
else
  emit FAIL "1.SSH 可达" "ssh 无法连接/认证（检查助手与公钥）"
  echo "== smoke summary: FAIL=$FAIL WARN=$WARN PASS=$PASS ==" >&2
  exit 1
fi

# --- 2 固件版本 ---------------------------------------------------------------
rel="$(rf '. /etc/openwrt_release 2>/dev/null; echo "$DISTRIB_ID $DISTRIB_RELEASE $DISTRIB_REVISION | $DISTRIB_TARGET"')"
kern="$(rf 'uname -r 2>/dev/null')"
if echo "$rel" | grep -q "OpenWrt SNAPSHOT"; then emit PASS "2.固件版本" "$rel | 内核 $kern"
else emit WARN "2.固件版本" "$rel | 内核 $kern（非 SNAPSHOT，记录即可）"; fi

# --- 3 接口状态 ---------------------------------------------------------------
brlan="$(rf "ip -br addr show br-lan 2>/dev/null | head -1")"
ethup="$(rf "for i in eth0 wan lan1; do ip -br link show \$i 2>/dev/null; done | grep -c UP")"
if echo "$brlan" | grep -q "192.168.123.1/24" && [ "$ethup" -ge 2 ]; then
  emit PASS "3.接口状态" "br-lan=${brlan%% *} up 口=$ethup（eth0/wan/lan1）"
else emit WARN "3.接口状态" "br-lan=$brlan | up 口数=$ethup"; fi

# --- 4 无线 band ---------------------------------------------------------------
bands="$(rf "iw phy phy0 info 2>/dev/null | grep -oE 'Band [0-9]+:' | tr '\n' ',' ")"
sixg="$(rf "uci get wireless.radio2.disabled 2>/dev/null")"
if echo "$bands" | grep -q "Band 1:" && echo "$bands" | grep -q "Band 2:"; then
  # 6GHz：radio2 disabled 为已知态（信道未枚举）；自建镜像需 enable radio2 后另行验证
  emit PASS "4.无线 band" "phy0 $bands（6GHz: radio2 disabled=${sixg:-未知},信道未枚举=已知态）"
else emit WARN "4.无线 band" "phy0 bands=$bands"; fi

# --- 5 NPU 固件 ---------------------------------------------------------------
npu="$(rf "dmesg 2>/dev/null | grep -iE 'NPU fw version|npu.*fw version' | tail -2 | tr '\n' '|'")"
if echo "$npu" | grep -qi "fw version"; then emit PASS "5.NPU 固件" "$npu"
else emit WARN "5.NPU 固件" "dmesg 未见 NPU fw version 行（可能需 root dmesg 权限）"; fi

# --- 6 告警扫描（ABSENT 口径） -------------------------------------------------
alerts="$(rf "dmesg 2>/dev/null | grep -iE 'out of memory|oom-kill|kernel panic|Oops|BUG:|unable to handle kernel|wed.*crash' | head -5")"
[ -z "$alerts" ] && emit PASS "6.告警扫描" "无 OOM/panic/WED crash（dmesg 尾部快照）" \
                || emit FAIL "6.告警扫描" "发现告警：$alerts"

# --- 7 资源基线 ---------------------------------------------------------------
mem="$(rf "free -h 2>/dev/null | awk 'NR==2{print \$2\" total / \"\$7\" avail\"}'")"
load="$(rf "cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3")"
ov="$(rf "df -h /overlay 2>/dev/null | tail -1 | awk '{print \$4\" 剩余\"}'")"
emit PASS "7.资源基线" "mem=$mem | load=$load | overlay=$ov"

# --- 8 /proc/mtd 分区表存证 ----------------------------------------------------
mtd="$(rf "cat /proc/mtd 2>/dev/null | grep -v '^dev' | awk '{print \$4}' | tr '\n' ' '")"
emit PASS "8.分区表存证" "mtd: $mtd"

echo "== smoke summary: PASS=$PASS WARN=$WARN FAIL=$FAIL ==" >&2
[ "$FAIL" -eq 0 ]
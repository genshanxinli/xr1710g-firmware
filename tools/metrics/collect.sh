#!/usr/bin/env bash
#===============================================================================
# collect.sh — XR1710G（Airoha AN7581 + MediaTek MT7996）NPU 指标全量抓取 v0
#
# 归属：tools/metrics/（M0 指标盘点闭环的唯一采集端）
# 配套：docs/metrics/v0.md（版本化盘点清单 v0）
#       docs/metrics/backfill-template.md（真机回填流程与版本化规则）
#
# 模式（三态）：
#   dry-run         缺真机占位运行：每条指标输出占位值 + PENDING_DEVICE 标记，
#                   结尾汇总【缺真机清单】；退出码恒 0。进入条件：
#                     a) 未指定 --host 且本机设备自检未命中（如开发机）；
#                     b) --dry-run 强制；c) --host 但 ssh 不可达（回落并注明）。
#   real (local)    本机即 OpenWrt 真机（root）：设备自检命中 → 逐模块实际采集。
#   real (remote)   --host <user@ip>：命令经 base64 管道发往远端 bash 执行；
#                   依赖远端已装 bash（OpenWrt: opkg install bash）。
#
# 采集面（8 模块）：npu（NPU 固件版本/路径/luci 面板与计数）/ mt76（per-radio +
#   WED 计数，含 6GHz 判定）/ flow（FlowSense/PPE 流表：PPPoE/VLAN/AP 模式）/
#   eth（ethtool+sysfs 链路：2×10G+2×1G）/ cpu（占用采样）/ iperf3（双 10G 等
#   吞吐位点，只出【预留模板】绝不自动测速）/ alerts（dmesg OOM/CVE/崩溃扫描）/
#   thermal（温度/风扇，M3 环境口径）。
#
# 输出列（text/TSV）：时间戳(UTC) | 指标名 | 期望值/口径[来源] | 值 | 来源命令 | 标记
#   标记：OK（采集且符合口径）/ NA（采集为空或不符合）/ PENDING_DEVICE（缺真机）
#   kw 语义：真实关键词=输出须含；ABSENT=输出须为空（告警类期望"无"）；
#            TEMPLATE=不执行只出模板；-=不检查关键字（非空即 OK）。
#   期望值/口径一律引用报告原文并注明出处；任何情况下不编造实测数字。
#===============================================================================

set -u

SELF="$(basename "$0")"
TS_FMT='+%Y-%m-%dT%H:%M:%SZ'
PLACEHOLDER='(无真机 · PENDING_DEVICE)'
MODULES_ALL=(npu mt76 flow eth cpu iperf3 alerts thermal)
VAL_MAX=400   # 值列截断
EXP_MAX=180   # 期望列截断
CMD_MAX=230   # 来源命令列截断

MODE=dryrun          # dryrun | real
RUN_LOCATION=local   # local | remote
FORMAT=text          # text | tsv | json
OUTFILE=""
SEL=all
HOST=""
FORCE_DRY=0
DEVICE_TAG=absent
FLAG_OK=0
FLAG_NA=0
FLAG_PENDING=0

#--- 工具 ----------------------------------------------------------------------

ts() { date -u "$TS_FMT" 2>/dev/null || date -u; }

sanitize() { printf '%s' "$1" | tr '\n\t' '  ' | sed -r 's/[|]+/¦/g; s/[ ]{2,}/ /g' | cut -c1-"$VAL_MAX"; }
json_esc() { printf '%s' "$1" | tr '\n\t' '  ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

emit_line() {
  # $1 module  $2 metric  $3 expect  $4 value  $5 flag  $6 cmd
  local mod="$1" metric="$2" expect="$3" val="$4" flag="$5" cmd="$6"
  local t; t="$(ts)"
  [ "$flag" = OK ] && FLAG_OK=$((FLAG_OK+1))
  [ "$flag" = NA ] && FLAG_NA=$((FLAG_NA+1))
  [ "$flag" = PENDING_DEVICE ] && FLAG_PENDING=$((FLAG_PENDING+1))
  local exp_cut cmd_cut
  exp_cut="$(printf '%s' "$expect" | cut -c1-"$EXP_MAX")"
  cmd_cut="$(printf '%s' "$cmd" | cut -c1-"$CMD_MAX")"
  if [ -n "$OUTFILE" ]; then
    case "$FORMAT" in
      tsv)
        [ -s "$OUTFILE" ] || printf 'ts\tmetric\texpect\tvalue\tcommand\tflag\n' >> "$OUTFILE"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$t" "$metric" "$(sanitize "$exp_cut")" "$(sanitize "$val")" "$(sanitize "$cmd_cut")" "$flag" >> "$OUTFILE" ;;
      json)
        printf '{"ts":"%s","module":"%s","metric":"%s","expect":"%s","value":"%s","command":"%s","flag":"%s"}\n' \
          "$(json_esc "$t")" "$(json_esc "$mod")" "$(json_esc "$metric")" \
          "$(json_esc "$exp_cut")" "$(json_esc "$val")" "$(json_esc "$cmd_cut")" "$(json_esc "$flag")" >> "$OUTFILE" ;;
      text)
        printf '%s | %s | %s | %s | %s | %s\n' "$t" "$metric" "$(sanitize "$exp_cut")" "$(sanitize "$val")" "$(sanitize "$cmd_cut")" "$flag" >> "$OUTFILE" ;;
    esac
  else
    printf '%s | %s | %s | %s | %s | %s\n' "$t" "$metric" "$(sanitize "$exp_cut")" "$(sanitize "$val")" "$(sanitize "$cmd_cut")" "$flag"
  fi
}

# 真机/远端执行一条采集命令（real 模式专用；dry-run 不会走到这里）
run_cmd() {
  local cmd="$1" enc
  if [ "$RUN_LOCATION" = remote ]; then
    enc="$(printf '%s' "$cmd" | base64 2>/dev/null | tr -d '\n')"
    # -n 必须：否则 ssh 继承并吸干调用方（parse_spec 的 while read <<< spec）
    # 的 stdin，导致 spec 只剩第一组（2026-08-17 实测）。
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "echo \"$enc\" | base64 -d | bash" 2>/dev/null
  else
    eval "$cmd" 2>/dev/null
  fi
}

# spec 驱动的单指标执行：name / cmd / expect / kw
run_one() {
  local mod="$1" name="$2" cmd="$3" expect="$4" kw="$5"
  local out flag
  if [ "$MODE" = dryrun ]; then
    emit_line "$mod" "$name" "$expect" "$PLACEHOLDER" PENDING_DEVICE "$cmd"
    return
  fi
  if [ "$kw" = TEMPLATE ]; then
    if [ -n "$(run_cmd 'command -v iperf3 2>/dev/null')" ]; then flag=OK; else flag=NA; fi
    emit_line "$mod" "$name" "$expect" "[预留模板·手动执行，脚本不自动测速] $cmd" "$flag" "iperf3.template（不自动执行）"
    return
  fi
  out="$(run_cmd "$cmd")"
  if [ "$kw" = ABSENT ]; then
    [ -z "$out" ] && flag=OK || flag=NA
  elif [ -z "$out" ]; then
    flag=NA
  elif [ "$kw" != "-" ] && ! printf '%s' "$out" | grep -q -- "$kw"; then
    flag=NA
  else
    flag=OK
  fi
  emit_line "$mod" "$name" "$expect" "${out:-（空输出）}" "$flag" "$cmd"
}

# 模块名 → spec 常量名（模块小写、常量大写）
spec_var() {
  case "$1" in
    npu) echo SPEC_NPU ;; flow) echo SPEC_FLOW ;; eth) echo SPEC_ETH ;;
    cpu) echo SPEC_CPU ;; iperf3) echo SPEC_IPERF3 ;;
    alerts) echo SPEC_ALERTS ;; thermal) echo SPEC_THERMAL ;;
  esac
}

# spec 解析：严格每 4 行一组（name / cmd / expect / kw），空行跳过
parse_spec() {
  local mod="$1" spec_name spec line i=0 name cmd expect kw
  spec_name="$(spec_var "$1")"
  spec="${!spec_name}"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case $i in
      0) name="$line"; i=1 ;;
      1) cmd="$line"; i=2 ;;
      2) expect="$line"; i=3 ;;
      3) kw="$line"; i=0; run_one "$mod" "$name" "$cmd" "$expect" "$kw" ;;
    esac
  done <<< "$spec"
}

# 汇总清单用：列举某 spec 的全部指标名（含期望截断）
list_spec_metrics() {
  local spec_name spec line i=0 name expect
  spec_name="$(spec_var "$1")"
  spec="${!spec_name}"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case $i in
      0) name="$line"; i=1 ;;
      1) i=2 ;;
      2) expect="$line"; printf '  %s — %s\n' "$name" "$(printf '%s' "$expect" | cut -c1-120)"; i=3 ;;
      3) i=0 ;;
    esac
  done <<< "$spec"
}

#--- 真机自检（仅 local 模式用）--------------------------------------------------

detect_device() {
  if [ -r /proc/device-tree/model ] \
    && grep -qiE 'xr1710g|w1700k|an7581' /proc/device-tree/model; then return 0; fi
  [ -d /sys/kernel/debug/airoha ] && return 0
  [ -d /sys/kernel/debug/flow ] && return 0
  [ -f /lib/firmware/mediatek/en7581_MT7996_npu_rv32.bin ] && return 0
  { [ "$(uname -m)" = aarch64 ] && ls /lib/firmware/mediatek/en7581* >/dev/null 2>&1; } && return 0
  command -v ubus >/dev/null 2>&1 && return 0
  return 1
}

device_label() {
  if [ -r /proc/device-tree/model ]; then tr -d '\0' < /proc/device-tree/model
  else echo 'an7581-family(cpu/固件标记)'; fi
}

#--- spec：npu 模块（每组严格 4 行：name/cmd/expect/kw）--------------------------

SPEC_NPU='
npu.fw_version
dmesg 2>/dev/null | grep -iE "npu.*fw version|fw version" | tail -3
dmesg/启动日志含 NPU 固件版本号（出厂参考 0.1111，与实机对照）[来源: 01 §1.25；04 §3 指标来源]
fw version
npu.firmware_glue
ls -l /lib/firmware/mediatek/ 2>/dev/null | grep -i en7581
MT7996 前端绑定固件 en7581_MT7996_npu_rv32.bin + en7581_MT7996_npu_data.bin 在场（误配为 MT7992 前端 en7581_npu_rv32.bin 即告警）[来源: 01 §1.25；02 §2 打包 PR #22289]
en7581_MT7996
npu.reserved_mem
grep -i npu /proc/iomem 2>/dev/null
保留区 npu-binary(10MiB) 与 npu-pkt(45MiB) 均在 [来源: 01 §1.25]
npu
npu.dts_node
ls /proc/device-tree/ 2>/dev/null | grep -i npu
airoha,en7581-npu @0x1E900000 节点在场 [来源: 01 §1.25]
npu
npu.debugfs_tree
ls -R /sys/kernel/debug/airoha /sys/kernel/debug/flow /sys/kernel/debug/ppe 2>/dev/null | head -60
debugfs airoha/flow/ppe 可枚举，含统计/队列节点（可观测证据[④]）[来源: 04 §3 词条④ 可观测可开关]
-
npu.luci_panel
opkg list-installed 2>/dev/null | grep -iE "airoha-npu|flowsense"
luci-app-airoha-npu 已装（可观测/开关入口[④]）[来源: 04 §3 词条④；02 §4 社区构建内置]
airoha-npu
npu.luci_counters
{ ubus list 2>/dev/null | grep -i npu; uci show airoha-npu 2>/dev/null; grep -riE "npu|offload|hit|cnt" /sys/kernel/debug/airoha 2>/dev/null | head -20; }
luci-app-airoha-npu 面板/底层卸载计数可读（命中/开关状态；接口名以实机面板为准滚动收录）[来源: 04 §3 闭环机制；核心口径③ NPU 转发≥10Gbps 的计数侧]
-
npu.dmesg_ring
dmesg 2>/dev/null | grep -i npu | tail -20
NPU 启动/运行日志无崩溃痕迹（wed 崩溃、0x 异常）[来源: 02 §2 CVE-2025-68360；04 §3 CVE 在场]
npu
'

#--- spec：flow（FlowSense/PPE）模块 ----------------------------------------------

SPEC_FLOW='
flow.bin
command -v flowsense; command -v flowm; command -v flowmd
FlowSense 用户态命令在场（PPE 硬 NAT 前哨）[来源: 02 §4；04 §3 词条②]
flowm
flow.uci
uci show flowsense 2>/dev/null; uci show flowm 2>/dev/null
配置完整且 PPPoE/VLAN/AP 模式/XFRM 通道可见 [来源: 02 §2 社区 FlowSense；04 §3 指标来源]
-
flow.flows
flowm dump 2>/dev/null | head -40
硬加速流表非空、逐流可读；AP 模式下流表仍可见（=⑤专项）[来源: 04 §3 词条②⑤]
-
flow.flows_pattern
flowm dump 2>/dev/null | grep -iE "pppoe|vlan" | head -10
PPPoE/VLAN 特征流可辨识（PPPoE 硬卸载来源不全→仅观测，进 v1 验收需真机流表）[来源: 02 §2；04 §3 指标来源]
-
flow.log
logread 2>/dev/null | grep -iE "flowsense|flowm|ppe" | tail -30
初始化成功；无 PPE 报错；无 CVE-2025-22061 对应 kernel warning [来源: 02 §7；04 §3 CVE 在场]
-
flow.ppe_debugfs
ls -R /sys/kernel/debug/flow /sys/kernel/debug/airoha/ppe 2>/dev/null | head -40
PPE 计数节点在场（[②④] 可观测）[来源: 04 §3 词条②④]
-
'

#--- spec：eth（ethtool/链路状态）模块 --------------------------------------------

SPEC_ETH='
eth.port_list
ls /sys/class/net 2>/dev/null | grep -E "^eth|^lan|^wan"
网口集齐：2×10G（RTL8261BE）+ 2×1G（MT7530）[来源: 02 §0 网口；02 §5 PHY]
eth
eth.port_speed
for d in /sys/class/net/eth*; do [ -e "$d" ] && echo "$(basename $d): $(cat $d/speed 2>/dev/null) Mb/s"; done 2>/dev/null
双万兆口 Speed=10000（RTL8261BE）、双千兆=1000（MT7530）[来源: 02 §0；04 §3 核心口径① 的双 10G 载体]
10000
eth.port_link
for d in /sys/class/net/eth*; do [ -e "$d" ] && echo "$(basename $d): carrier=$(cat $d/carrier 2>/dev/null)"; done 2>/dev/null
验收时双 10G 链路 carrier=1（Link up）[来源: 04 §3 核心口径①]
-
eth.ethtool_dump
ethtool eth0 2>/dev/null | grep -iE "Speed|Duplex|Link detected"; ethtool eth1 2>/dev/null | grep -iE "Speed|Link detected"
ethtool 可见双 10G 口 Speed: 10000Mb/s 且 Link detected: yes [来源: 02 §0；04 §3 核心口径①]（依赖 ethtool 已装，未装则 sysfs 行兜底）
10000
eth.phy_driver
ethtool -i eth0 2>/dev/null | grep -i driver; ethtool -i eth1 2>/dev/null | grep -i driver
10G PHY 驱动 rtl8261 在册 [来源: 02 §0/§5 RTL8261BE]
rtl8261
'

#--- spec：cpu 模块 ---------------------------------------------------------------

SPEC_CPU='
cpu.loadavg
cat /proc/loadavg 2>/dev/null
空载 <1.0；吞吐测试期间另留同刻对照 [来源: 04 §3 核心口径④ CPU<5% 佐证]
-
cpu.top_snapshot
top -b -n1 2>/dev/null | head -20
10G↔Wi-Fi 并发 iperf3 时 CPU<5%（论坛实测 0–1%）；须与 wifi10g 模板同刻截取 [来源: 04 §3 核心口径④；01 §1.28 论坛实测 2026-03-22]
-
cpu.pidstat
pidstat 1 1 2>/dev/null | head -20
NPU/WED 线程占用分布可辨（procps-ng 可选，未装→NA 不阻塞）[来源: 04 §3 词条③]
-
cpu.softirqs
head -10 /proc/softirqs 2>/dev/null
offload 开时 NET_RX 软中断增长平缓（开关对照佐证[④]）[来源: 04 §3 词条④]
-
'

#--- spec：iperf3（吞吐位点，只出预留模板，绝不自动测速）----------------------------

SPEC_IPERF3='
iperf3.bin_present
command -v iperf3 2>/dev/null
iperf3 已装（路由器与对端双侧）[来源: 04 §3 核心口径① 工具链]
iperf3
iperf3.template.dual10g
iperf3 -c <PEER_10G_IP> -t 60 -P 4 --bidir -O 5 --json   # 双 10G 双向近线速位点
【核心口径①】双 10G iperf3 双向近线速（参考 ≥9.4Gbps/向；以实机为准）[来源: 04 §3 核心口径①；02 §0 网口]
TEMPLATE
iperf3.template.udp_nat
iperf3 -u -c <PEER_IP> -b 0 -t 60 --json   # UDP 硬 NAT 满载位点
【核心口径③/②】NPU 转发 ≥10Gbps；UDP 硬 NAT 满载 + PPE 流表命中 [来源: 04 §3 核心口径③、词条② PPE 硬 NAT 满载]
TEMPLATE
iperf3.template.wifi10g
路由器 10G LAN 口起 iperf3 -s；STA 经 Wi-Fi：iperf3 -c <ROUTER_LAN_IP> -t 60 -P 4 --json   # 10G↔Wi-Fi 位点
【核心口径④】10G↔Wi-Fi 1.1–1.4Gbps 且 CPU<5% [来源: 04 §3 核心口径④；01 §1.28 论坛实测]
TEMPLATE
iperf3.template.backhaul
iperf3 -c <MESH_NODE_IP> -t 60 --json; ping -c 20 -i 0.2 <MESH_NODE_IP>   # 6GHz 802.11s 回程位点
【核心口径②/M3】6GHz 802.11s 回程 offload 开启下吞吐/时延基准跑稳；配套 mt76.<phy6>.tx_failed=0 [来源: 04 §3 核心口径②；02 §7 恩山手法⑤]
TEMPLATE
'

#--- spec：alerts（dmesg OOM/CVE/崩溃告警扫描）-------------------------------------

SPEC_ALERTS='
alerts.dmesg_oom
dmesg 2>/dev/null | grep -iE "out of memory|oom-kill|killed process"
无 OOM 痕迹（真机期望=空输出）[来源: 02 §7 稳定性；04 §3 M3 稳定运行]
ABSENT
alerts.dmesg_panic
dmesg 2>/dev/null | grep -iE "kernel panic|Oops|BUG:|unable to handle kernel"
无内核崩溃/Oops（真机期望=空输出）[来源: 02 §2 CVE-2025-68360 场景]
ABSENT
alerts.dmesg_wed
dmesg 2>/dev/null | grep -iE "wed|mt7996" | grep -iE "crash|bug|fail|error" | head -10
无 WED 相关崩溃/报错（6GHz offload 开启下；真机期望=空输出）[来源: 02 §2 CVE-2025-68360；04 §3 R4/核心口径②]
ABSENT
alerts.dmesg_airtime
dmesg 2>/dev/null | grep -i airtime_link_metric
无 airtime_link_metric_get 报错（恩山稳定化验收项；真机期望=空输出）[来源: 02 §7 ⑤；04 §3 M3]
ABSENT
alerts.governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
performance（恩山 6GHz 稳定化手法④；M3 口径，非 04 §3 硬性）[来源: 02 §7 ④]
performance
alerts.max_inactivity
uci show wireless 2>/dev/null | grep -iE "max_inactivity|disassoc_low_ack"
max_inactivity=86400 / disassoc_low_ack=0 在场（恩山稳定化手法④；M3 口径）[来源: 02 §7 ④]
-
'

#--- spec：thermal（温度/风扇，M3 环境口径）-----------------------------------------

SPEC_THERMAL='
thermal.zones
for z in /sys/class/thermal/thermal_zone*; do echo "$z: $(cat $z/type 2>/dev/null) = $(cat $z/temp 2>/dev/null)"; done 2>/dev/null
温度可读；常态 52–57°C（M3 旗舰验收，非 04 §3 硬性）[来源: 02 §7 ⑤；04 §3 M3]
-
thermal.hwmon
cat /sys/class/hwmon/hwmon*/temp*_input 2>/dev/null | head -20
hwmon 温度通道可读 [来源: 02 §7 温度口径]
-
thermal.fancontrol_cfg
uci show fancontrol 2>/dev/null; cat /etc/config/fancontrol 2>/dev/null
luci-app-w1700k-fancontrol 配置在场 [来源: 02 §4 社区构建（来源 repo）]
-
'

#--- 模块 · mt76（per-radio + WED，含 6GHz；动态展开）-------------------------------

CMD_PHY_COUNT='ls -d /sys/kernel/debug/ieee80211/phy* 2>/dev/null | wc -l'

dry_mt76() {
  run_one mt76 mt76.phy_count "$CMD_PHY_COUNT" \
    "三频各一 phy = 3（2.4/5/6GHz）[来源: 02 §0 三频射频]" "-"
  local p
  for p in phy0 phy1 phy2; do
    emit_line mt76 "mt76.$p.band" \
      "iw 可见 Band 1/2/3 齐备 [来源: 02 §0 三频]" "$PLACEHOLDER" PENDING_DEVICE \
      "iw phy $p info 2>/dev/null | grep -E '^Band '"
    emit_line mt76 "mt76.$p.is_6ghz" \
      "6GHz radio 正确标记（offload 面，CVE-2025-68360 相关）[来源: 02 §2；04 §3 词条①]" "$PLACEHOLDER" PENDING_DEVICE \
      "iw phy $p info → 频率列表 max≥5955MHz 判 6GHz"
    emit_line mt76 "mt76.$p.tx_failed" \
      "【核心口径②】tx failed=0（含 6GHz 回程 radio）[来源: 04 §3 核心口径②；02 §7 恩山⑤]" "$PLACEHOLDER" PENDING_DEVICE \
      "grep -i 'tx failed' /sys/kernel/debug/ieee80211/$p/mt76/{tx_stats,stats}"
    emit_line mt76 "mt76.$p.wed_queue" \
      "WED 队列/统计节点在场（per-radio，含 6GHz，=⑤专项）[来源: 04 §3 词条⑤]" "$PLACEHOLDER" PENDING_DEVICE \
      "ls /sys/kernel/debug/ieee80211/$p/mt76/ | grep -iE 'wed'"
    emit_line mt76 "mt76.$p.mt76_debugfs" \
      "队列/统计可读（[①④] 可观测）[来源: 04 §3 词条①④]" "$PLACEHOLDER" PENDING_DEVICE \
      "cat /sys/kernel/debug/ieee80211/$p/mt76/{queues,tx_stats}"
  done
}

probe_mt76() {
  local phy pn maxmhz six
  local phys_out; phys_out="$(run_cmd "$CMD_PHY_COUNT")"
  if [ -z "$phys_out" ]; then
    emit_line mt76 mt76.phy_count "三频各一 phy = 3 [来源: 02 §0]" "（空输出）" NA "$CMD_PHY_COUNT"
  else
    emit_line mt76 mt76.phy_count "三频各一 phy = 3 [来源: 02 §0]" "$phys_out" OK "$CMD_PHY_COUNT"
  fi
  local phys; phys="$(run_cmd 'ls -d /sys/kernel/debug/ieee80211/phy* 2>/dev/null')"
  if [ -z "$phys" ]; then
    emit_line mt76 mt76.phy_absent "三频各一 phy = 3 [来源: 02 §0]" "（无 mt76 debugfs phy 目录）" NA "ls -d /sys/kernel/debug/ieee80211/phy*"
    return
  fi
  local iface MD
  for phy in $phys; do
    pn="$(basename "$phy")"
    # 远端/本地路径统一：phy 绝对路径在远端意义不同，per-phy 命令一律用 phy 名
    run_one mt76 "mt76.${pn}.band" \
      "iw phy ${pn} info 2>/dev/null | grep -E 'Band [0-9]+:'" \
      "iw 可见 Band 1/2/3 齐备 [来源: 02 §0]" "Band"
    if [ -z "$(run_cmd "command -v iw 2>/dev/null")" ]; then
      emit_line mt76 "mt76.${pn}.is_6ghz" "6GHz radio 正确标记 [来源: 02 §2]" "(iw 缺失，无法判定频段)" NA "iw phy ${pn} info"
    else
      maxmhz="$(run_cmd "iw phy ${pn} info 2>/dev/null | grep -oE '[0-9]{4} MHz' | tr -d ' MHz' | sort -n | tail -1")"
      if [ -n "$maxmhz" ] && [ "$maxmhz" -ge 5955 ] 2>/dev/null; then
        six="YES (6GHz 频段, max ${maxmhz}MHz)"
      else
        six="NO (max ${maxmhz:-NA}MHz)"
      fi
      emit_line mt76 "mt76.${pn}.is_6ghz" "6GHz radio 正确标记 [来源: 02 §2]" "$six" OK "iw phy ${pn} info → max≥5955MHz 判 6GHz"
    fi
    run_one mt76 "mt76.${pn}.tx_failed" \
      "grep -i 'tx failed' /sys/kernel/debug/ieee80211/${pn}/mt76/tx_stats /sys/kernel/debug/ieee80211/${pn}/mt76/stats 2>/dev/null | head -5" \
      "【核心口径②】tx failed=0 [来源: 04 §3 核心口径②]" "-"
    run_one mt76 "mt76.${pn}.wed_queue" \
      "ls /sys/kernel/debug/ieee80211/${pn}/mt76/ 2>/dev/null | grep -iE 'wed'" \
      "WED 队列/统计节点在场（=⑤专项）[来源: 04 §3 词条⑤]" "wed"
    run_one mt76 "mt76.${pn}.mt76_debugfs" \
      "cat /sys/kernel/debug/ieee80211/${pn}/mt76/queues /sys/kernel/debug/ieee80211/${pn}/mt76/tx_stats 2>/dev/null | head -20" \
      "队列/统计可读（[①④]）[来源: 04 §3 词条①④]" "-"
  done
}

list_mt76_metrics() {
  echo "  mt76.phy_count — 三频各一 phy = 3 [02 §0]"
  echo "  mt76.<phy>.{band,is_6ghz,tx_failed,wed_queue,mt76_debugfs}（×5，真机按实际 phy 展开）— per-radio/WED/6GHz/tx failed [04 §3 词条①⑤；核心口径②]"
}

#--- 调度 ---------------------------------------------------------------------

module_valid() {
  local m
  for m in "${MODULES_ALL[@]}"; do [ "$m" = "$1" ] && return 0; done
  return 1
}

run_module() {
  local m="$1"
  echo "# --- module: $m ---"
  [ -n "$OUTFILE" ] && echo "# --- module: $m ---" >> "$OUTFILE"
  case "$m" in
    npu|flow|eth|cpu|alerts|thermal) parse_spec "$m" ;;
    mt76) if [ "$MODE" = dryrun ]; then dry_mt76; else probe_mt76; fi ;;
    iperf3) parse_spec iperf3 ;;
  esac
}

print_summary() {
  local total=$((FLAG_OK+FLAG_NA+FLAG_PENDING))
  echo "[summary] mode=$MODE location=$RUN_LOCATION OK=$FLAG_OK NA=$FLAG_NA PENDING_DEVICE=$FLAG_PENDING total=$total" >&2
  if [ "$MODE" = dryrun ]; then
    echo "【缺真机清单】共 $FLAG_PENDING 条指标待真机回填——本机/远端均无真机，未执行任何采集命令，全部占位 PENDING_DEVICE（期望值/口径见各行 [来源] 标注）：" >&2
    local m
    for m in "${MODULES_ALL[@]}"; do
      echo "  [$m]" >&2
      case "$m" in
        npu|flow|eth|cpu|alerts|thermal|iperf3) list_spec_metrics "$m" >&2 ;;
        mt76) list_mt76_metrics >&2 ;;
      esac
    done
  else
    echo "【NA 待查】（采集到但为空/不符合口径关键词的行，逐条人工核对原因后回填）：" >&2
  fi
}

usage() {
  cat <<EOF
用法: $SELF [选项]

  采集模式（三态）：
    dry-run        本机无真机（自动）/ --dry-run 强制 → 全部 PENDING_DEVICE 占位 + 【缺真机清单】
    real (local)   本机即 OpenWrt 真机（root），设备自检命中 → 实际采集
    real (remote)  --host <user@ip> → 经 ssh 远端采集（远端需已装 bash；命令 base64 管道）

  选项：
    --host <user@ip>   远端真机（如 root@192.168.50.1）；ssh 不可达自动回落 dry-run
    --dry-run          强制占位运行（即使 --host/设备自检命中也不采集）
    --module <名>      单选模块：npu|mt76|flow|eth|cpu|iperf3|alerts|thermal|all
    -o <文件>          追加输出到文件（默认 TSV；--format json 为 JSONL）
    --format text|tsv|json   输出格式（默认 text；-o 时默认 tsv）
    --list              列出模块名
    -h, --help          帮助

  例：
    bash tools/metrics/collect.sh                        # 本机 dry-run（无真机演示）
    bash tools/metrics/collect.sh --dry-run              # 强制占位运行
    bash tools/metrics/collect.sh --host root@192.168.50.1 -o /root/m.tsv   # 远端真机全量
    bash tools/metrics/collect.sh --host root@192.168.50.1 --module npu     # 远端单选模块
    bash tools/metrics/collect.sh --module eth           # eth 链路模块

  输出列: 时间戳 | 指标名 | 期望值/口径[来源] | 值 | 来源命令 | 标记(OK|NA|PENDING_DEVICE)
EOF
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --host) HOST="${2:-}"; shift 2 ;;
      --dry-run) FORCE_DRY=1; shift ;;
      --module) SEL="${2:-}"; shift 2 ;;
      --format) FORMAT="${2:-}"; shift 2 ;;
      -o) OUTFILE="${2:-}"; shift 2 ;;
      --list) printf '%s\n' "${MODULES_ALL[@]}"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "错误：未知参数 '$1'（--help 看帮助）" >&2; exit 2 ;;
    esac
  done

  case "$FORMAT" in text|tsv|json) ;; *) echo "错误：未知格式 '$FORMAT'（text|tsv|json）" >&2; exit 2 ;; esac
  if [ "$SEL" != all ] && ! module_valid "$SEL"; then
    echo "错误：未知模块 '$SEL'（可用：${MODULES_ALL[*]}）" >&2; exit 2
  fi
  [ -n "$OUTFILE" ] && [ "$FORMAT" = text ] && FORMAT=tsv

  # 模式判定
  if [ "$FORCE_DRY" = 1 ]; then
    MODE=dryrun
  elif [ -n "$HOST" ]; then
    if ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2>/dev/null; then
      MODE=real; RUN_LOCATION=remote
      DEVICE_TAG="$(ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$HOST" \
        'cat /proc/device-tree/model 2>/dev/null | tr -d "\0"; uname -m' 2>/dev/null | tr '\n' ' ')"
    else
      echo "[warn] --host $HOST ssh 不可达（BatchMode=yes / ConnectTimeout=5），回落 dry-run。" >&2
      MODE=dryrun; RUN_LOCATION=local; HOST=""
    fi
  elif detect_device; then
    MODE=real; RUN_LOCATION=local
    DEVICE_TAG="$(device_label)"
  else
    MODE=dryrun
  fi

  local t; t="$(ts)"
  if [ -n "$OUTFILE" ] && [ ! -s "$OUTFILE" ]; then
    if [ "$FORMAT" = json ]; then
      printf '{"_meta":{"ts":"%s","mode":"%s","location":"%s","device":"%s","modules":"%s","script":"collect.sh","version":"v0"}}\n' \
        "$t" "$MODE" "$RUN_LOCATION" "$DEVICE_TAG" "$SEL" >> "$OUTFILE"
    else
      printf '# meta: %s | mode=%s | location=%s | device=%s | modules=%s | script=collect.sh v0\n' \
        "$t" "$MODE" "$RUN_LOCATION" "$DEVICE_TAG" "$SEL" >> "$OUTFILE"
    fi
  fi
  printf '# meta: %s | mode=%s | location=%s | device=%s | modules=%s | script=collect.sh v0\n' \
    "$t" "$MODE" "$RUN_LOCATION" "$DEVICE_TAG" "$SEL"

  if [ "$MODE" = dryrun ]; then
    echo "> [dry-run] 缺真机：全部指标输出占位值 + PENDING_DEVICE 标记，结尾汇总【缺真机清单】；退出码 0。" >&2
  else
    echo "> [real] 真机模式（须 root）：逐模块采集；iperf3 只出预留模板不自动测速。" >&2
  fi

  if [ "$SEL" = all ]; then
    local m
    for m in "${MODULES_ALL[@]}"; do run_module "$m"; done
  else
    run_module "$SEL"
  fi

  print_summary
  exit 0
}

main "$@"
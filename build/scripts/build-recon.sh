#!/usr/bin/env bash
# build-recon.sh — OpenWrt 分叉构建"探路"脚本（XR1710G 项目）
#
# 目的：在受限资源机器上做极限小实验，把每一步的真实结果（成功/失败/终止）
#       记进日志，产出构建可行性探路报告所需证据（docs/research/06-build-recon.md）。
#
# 用法：
#   ./build-recon.sh [--all]                      # 顺序执行全部步骤
#   ./build-recon.sh --defconfig                  # 仅 defconfig
#   ./build-recon.sh --feeds                      # 仅 feeds update -a（15min timeout）
#   ./build-recon.sh --build                      # 仅试编译（资源日志每 60s 一条）
#   （--config-target 已删除：F7 后 target 配置走种子法——预置整块 .config 再
#     defconfig，不再单独写 target 配置；06 报告 §4 F7 记录了 sed 法反杀教训）
#
# 环境：
#   SRC       源码根（默认 /home/harness/workspace/openwrt-src）
#   LOGDIR    日志目录（默认 $SRC/logs，仓库外）
#   JOBS      并行度（上限 -j2，脚本内 min(JOBS,2) 保护）
#   FORCE     非空则透传 FORCE=1 给 make（跳过宿主预检；菜单配置缺失的场景）
#   BUILD_TIMEOUT  试编译 timeout 秒数（默认 1500 = 25min，可覆盖）
#
# 约定：任何一步失败都记录并继续（除非用户只跑该步）；
#       所有日志带时间戳；资源日志由后台循环每 60s 追加 free -h 与 df -h。

set -uo pipefail

SRC="${SRC:-/home/harness/workspace/openwrt-src}"
LOGDIR="${LOGDIR:-$SRC/logs}"
JOBS="${JOBS:-2}"
[ "$JOBS" -gt 2 ] && JOBS=2          # 资源受限上限
BUILD_TIMEOUT="${BUILD_TIMEOUT:-1500}"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/recon-$TS.log"
RESLOG="$LOGDIR/resources-$TS.log"

mkdir -p "$LOGDIR"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

step_header() {
  log "=============================================="
  log "STEP: $1"
  log "=============================================="
}

step_result() { # $1=ok|fail|skip  $2=详情
  log "RESULT[$1]: $2"
}

# ---------- 资源采样（后台，每 60s 一条） ----------
res_sampler() {
  while :; do
    { echo "===== $(date '+%F %T') =====";
      free -h | head -3;
      df -h "$SRC" | tail -1; } >> "$RESLOG"
    sleep 60
  done
}

start_res_sampler() {
  res_sampler &
  RES_PID=$!
  log "resource sampler started (pid $RES_PID) -> $RESLOG"
}

stop_res_sampler() {
  [ -n "${RES_PID:-}" ] && kill "$RES_PID" 2>/dev/null && log "resource sampler stopped"
  RES_PID=
}

# ---------- 步骤 0：环境快照 ----------
step_env() {
  step_header "env snapshot"
  {
    echo "===== env $(date '+%F %T') ====="
    nproc
    free -h
    df -h "$SRC"
    git -C "$SRC" log --oneline -1 2>&1
  } | tee -a "$LOG"
}

# ---------- 步骤 1：defconfig ----------
step_defconfig() {
  step_header "make defconfig"
  cd "$SRC" || { step_result fail "cannot cd $SRC"; return 1; }
  local t0 t1 rc
  t0=$(date +%s)
  timeout 600 make ${FORCE:+FORCE=$FORCE} defconfig >> "$LOG" 2>&1
  rc=$?
  t1=$(date +%s)
  if [ "$rc" = 0 ]; then
    step_result ok "defconfig OK in $((t1-t0))s"
    grep -E '^CONFIG_TARGET_(airoha|airoha_an7581)' .config >> "$LOG" 2>&1 || true
  else
    step_result fail "defconfig failed in $((t1-t0))s (rc=$rc); 尾部日志:"
    tail -n 30 "$LOG"
  fi
}

# ---------- 步骤 2：feeds ----------
step_feeds() {
  step_header "scripts/feeds update -a (timeout 900s)"
  cd "$SRC" || { step_result fail "cannot cd $SRC"; return 1; }
  local t0 t1
  t0=$(date +%s)
  if timeout 900 ./scripts/feeds update -a >> "$LOG" 2>&1; then
    t1=$(date +%s)
    step_result ok "feeds update OK in $((t1-t0))s"
    timeout 300 ./scripts/feeds install -a >> "$LOG" 2>&1 \
      && step_result ok "feeds install -a OK" \
      || step_result fail "feeds install -a failed"
  else
    t1=$(date +%s)
    step_result fail "feeds update failed in $((t1-t0))s; 尾部日志:"
    tail -n 30 "$LOG"
  fi
}



# ---------- 步骤 4：试编译（受控） ----------
step_build() {
  step_header "make -j$JOBS V=s (timeout ${BUILD_TIMEOUT}s) — 资源日志每 60s"
  cd "$SRC" || { step_result fail "cannot cd $SRC"; return 1; }
  start_res_sampler
  local t0 t1 rc
  t0=$(date +%s)
  timeout "$BUILD_TIMEOUT" make ${FORCE:+FORCE=$FORCE} -j"$JOBS" V=s >> "$LOG" 2>&1
  rc=$?
  t1=$(date +%s)
  stop_res_sampler
  {
    echo "===== build end $(date '+%F %T') rc=$rc elapsed=$((t1-t0))s ====="
    free -h | head -3
    df -h "$SRC" | tail -1
    du -sh "$SRC"/build_dir "$SRC"/staging_dir "$SRC"/dl 2>/dev/null
  } >> "$LOG"
  case $rc in
    0)   step_result ok "编译完成（极不可能在预算内；见日志确认）" ;;
    124) step_result fail "编译超时（${BUILD_TIMEOUT}s 到点终止）；终止前最后 20 行:"; tail -n 20 "$LOG" ;;
    *)   step_result fail "编译退出 rc=$rc（OOM/磁盘满/错误）；终止前最后 20 行:"; tail -n 20 "$LOG" ;;
  esac
  log "资源曲线见 $RESLOG（末尾 5 条）:"
  tail -n 10 "$RESLOG" | tee -a "$LOG"
}

# ---------- 主流程 ----------
main() {
  log "===== build-recon start TS=$TS SRC=$SRC LOG=$LOG ====="
  step_env
  local do_all=0
  for a in "$@"; do
    case "$a" in
      --all)          do_all=1 ;;
      --defconfig)    step_defconfig ;;
      --feeds)        step_feeds ;;
      --build)        step_build ;;
      -h|--help)      sed -n '1,20p' "$0"; exit 0 ;;
      *)              echo "未知参数: $a" >&2; exit 2 ;;
    esac
  done
  if [ "$do_all" = 1 ] || [ $# -eq 0 ]; then
    step_defconfig
    step_feeds
    step_build
  fi
  log "===== build-recon done: $LOG ====="
  echo "LOG=$LOG"
  echo "RESLOG=$RESLOG"
}

main "$@"
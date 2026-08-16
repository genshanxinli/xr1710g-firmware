#!/usr/bin/env python3
# ============================================================================
# report.py — XR1710G 自动跟进循环（M4）· 报告构建器
#
# 把 docs/tracking/<date>.raw/ 的原始数据汇总为 docs/tracking/<date>.md。
# 报告模板固定四节：
#   ① 上游动态      airoha / mt76 / hostapd 新提交与版本摘要（源 #1/#3/#4/#5/#6）
#   ② 构建触发信号  PR #22397 状态、新设备 profile、新 hostapd 版本（有则显著标出）
#   ③ 风险变化      R1–R10 逐项给自动信号或"人工"标记（04-roadmap-and-risk.md §1）
#   ④ 盲区监测点    03-frontier-dynamics.md 第 5 节 6 条预判逐条检查
#   附 源状态表     99_STATUS.tsv 逐源 OK/SKIP + 原因
#
# 调试友好：raw 缺失/为空时输出"今日无数据"占位，exit 0（不炸 CI）。
#
# 用法：
#   python3 scripts/tracking/report.py                  # 今天；无今天则用最近一个 raw 目录
#   python3 scripts/tracking/report.py --date 2026-08-16
#   python3 scripts/tracking/report.py --raw docs/tracking/2026-08-16.raw -o /tmp/x.md
# ============================================================================
import argparse
import datetime
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_ROOT = os.path.join(ROOT, "docs", "tracking")

TS = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_args():
    ap = argparse.ArgumentParser(description="把 tracking raw 汇总为跟踪报告 md")
    ap.add_argument("--date", help="报告日期 YYYY-MM-DD（缺省今天 UTC）")
    ap.add_argument("--raw", help="直接指定 raw 目录（优先于 --date）")
    ap.add_argument("-o", "--out", help="输出路径（缺省 docs/tracking/<date>.md）")
    return ap.parse_args()


def find_raw(args, today):
    """定位 raw 目录：--raw > --date > 今天；仅缺省参数时才回退到最近一个存在的 raw 目录。"""
    if args.raw:
        return args.raw, (re.search(r"(\d{4}-\d{2}-\d{2})\.raw$", args.raw) or [None, today])[1]
    d = args.date or today
    p = os.path.join(OUT_ROOT, f"{d}.raw")
    if os.path.isdir(p):
        return p, d
    if args.date:
        return p, d  # 显式指定日期无 raw → 走"今日无数据"占位，不回退
    # 缺省参数：今天无 raw 时退而取最近一个 raw 目录（补跑/跨天）
    cands = sorted(
        (n for n in os.listdir(OUT_ROOT) if re.match(r"^\d{4}-\d{2}-\d{2}\.raw$", n)),
        reverse=True,
    )
    if cands:
        return os.path.join(OUT_ROOT, cands[0]), cands[0][:10]
    return p, d  # 都不存在 → 占位


# ---------------------------- 读取工具 ----------------------------

def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def read_json(path):
    t = read_text(path)
    if not t:
        return None
    try:
        return json.loads(t)
    except (ValueError, TypeError):
        return None


def parse_status(stat_path):
    """99_STATUS.tsv → {source: (status, note)}；缺文件返回 None。"""
    t = read_text(stat_path)
    if not t:
        return None
    out = {}
    for line in t.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            out[parts[0]] = (parts[1], parts[2] if len(parts) > 2 else "")
    return out


def short(sha, n=8):
    return sha[:n] if sha else "?"


def iso_day(ts):
    """2026-08-09T10:28:53Z → 2026-08-09"""
    m = re.match(r"(\d{4}-\d{2}-\d{2})", ts or "")
    return m.group(1) if m else (ts or "?")


def bucket(subject):
    """把 git 日志主题粗分桶，供 ① 分节展示。"""
    s = subject.lower()
    if any(k in s for k in ("airoha", "an7581", "an7583", "en7581", "nokia", "evb")):
        return "airoha"
    if "hostapd" in s or "wpa_supplicant" in s or "wpad" in s:
        return "hostapd"
    if "mt76" in s or "mt7996" in s or "mt7992" in s:
        return "mt76"
    return "other"


def commits_from_json(d):
    """GitHub commits JSON → [(sha, date, subject)]"""
    if not isinstance(d, list):
        return []
    out = []
    for c in d:
        try:
            sha = c.get("sha", "")
            msg = (c.get("commit", {}).get("message") or "").splitlines()[0]
            dt = c.get("commit", {}).get("author", {}).get("date", "")
            out.append((sha, dt, msg.strip()))
        except (AttributeError, KeyError):
            continue
    return out


# ---------------------------- 渲染部分 ----------------------------

def render_upstream(r):
    """① 上游动态"""
    lines = []
    glog = read_text(os.path.join(r, "03_git_openwrt_log.txt"))
    if glog:
        rows = []
        for ln in glog.splitlines():
            m = re.match(r"(\w+)\s+(\S+)\s+(.*)", ln)
            if m:
                rows.append((m.group(1), m.group(2), m.group(3)))
        by = {"airoha": [], "hostapd": [], "mt76": [], "other": []}
        for sha, dt, subj in rows:
            by[bucket(subj)].append((sha, dt, subj))
        lines.append("### airoha / hostapd / mt76 定向日志（多通道回退，源#1/#3）")
        lines.append("")
        lines.append(f"共 **{len(rows)}** 条（14 天窗口；主题按关键词粗分桶）：")
        lines.append("")
        for name, label in (("airoha", "airoha 线"), ("mt76", "mt76 线"),
                            ("hostapd", "hostapd 线"), ("other", "其他/交叉")):
            if by[name]:
                lines.append(f"- **{label}** {len(by[name])} 条")
        lines.append("")
        lines.append("| 提交 | 日期 | 主题 |")
        lines.append("|---|---|---|")
        for name in ("airoha", "mt76", "hostapd", "other"):
            for sha, dt, subj in by[name]:
                lines.append(f"| `{short(sha)}` | {dt} | {subj} |")
    else:
        lines.append("### airoha / hostapd / mt76 定向日志（源#1/#3）")
        lines.append("")
        lines.append("- （无数据：03_git_openwrt_log.txt 缺失或为空 → 该源 SKIP）")
    lines.append("")

    agh = read_json(os.path.join(r, "04_gh_airoha_commits.json"))
    lines.append("### airoha 提交（GitHub 镜像 API，源#4）")
    lines.append("")
    if isinstance(agh, list):
        cm = commits_from_json(agh)
        lines.append(f"共 **{len(cm)}** 条（since=14d，per_page=30）：")
        lines.append("")
        lines.append("| 提交 | 日期 | 主题 |")
        lines.append("|---|---|---|")
        for sha, dt, subj in cm:
            lines.append(f"| `{short(sha)}` | {iso_day(dt)} | {subj} |")
    else:
        lines.append("- （无数据/失败）")
    lines.append("")

    mt = read_json(os.path.join(r, "05_gh_mt76_commits.json"))
    lines.append("### mt76 · mt7996 提交（GitHub 镜像 API，源#5）")
    lines.append("")
    if isinstance(mt, list):
        cm = commits_from_json(mt)
        lines.append(f"共 **{len(cm)}** 条（since=14d，per_page=30）：")
        lines.append("")
        lines.append("| 提交 | 日期 | 主题 |")
        lines.append("|---|---|---|")
        for sha, dt, subj in cm:
            lines.append(f"| `{short(sha)}` | {iso_day(dt)} | {subj} |")
    else:
        lines.append("- （无数据/失败）")
    lines.append("")

    hv = read_text(os.path.join(r, "06_w1fi_hostapd_versions.txt"))
    lines.append("### hostapd / wpa_supplicant 上游（源#6）")
    lines.append("")
    if hv:
        vers = sorted({v.strip() for v in hv.splitlines() if v.strip()},
                      key=lambda v: [int(x) for x in re.findall(r"\d+", v)])
        latest = vers[-1] if vers else "?"
        recent = [v for v in vers if [int(x) for x in re.findall(r"\d+", v)][:1] >= [2]]
        list_txt = "、".join(recent) if recent else "（2.x 行无版本）"
        lines.append(f"- 最新 hostapd 版本：**{latest}**；2.x 行版本：{list_txt}")
    else:
        lines.append("- （无数据/失败）")
    return lines


def render_triggers(r, prev_path):
    """② 构建触发信号 — 有信号则显著标出（GitHub admonition + 粗体）"""
    lines = []
    # --- PR #22397 ---
    pr = read_json(os.path.join(r, "07_gh_pr22397.json"))
    if isinstance(pr, dict) and "state" in pr:
        state = pr.get("state")
        merged = pr.get("merged")
        lines.append("### PR #22397（Gemtek XR1710G 上主线通道）")
        lines.append("")
        if merged is True:
            lines.append("> [!IMPORTANT]")
            lines.append(f"> **构建触发：PR #22397 已合并**（merged_at={pr.get('merged_at')}）— 事件驱动构建 + 评估设备适配层上提")
            lines.append("")
        elif state == "open":
            lines.append(f"- state: **open**（未合并）；updated_at: {pr.get('updated_at') or '?'}")
            lines.append("- 合并即触发分叉构建（04-roadmap-and-risk.md M4 / R6 缓解）")
        else:
            lines.append(f"- state: {state}（非 open 非 merged，请人工核查：{pr.get('state_reason') or ''}）")
        lines.append(f"- title: {pr.get('title')}")
        lines.append(f"- 链接: https://github.com/openwrt/openwrt/pull/22397")
    else:
        lines.append("### PR #22397（Gemtek XR1710G 上主线通道）")
        lines.append("")
        lines.append("- （数据缺失/抓取失败）")
    lines.append("")

    # --- 新设备 profile ---
    lines.append("### 官方 snapshot profiles（源#14 / #14b）")
    lines.append("")
    p14 = read_json(os.path.join(r, "14_an7581_profiles.json"))
    p14b = read_json(os.path.join(r, "14b_an7583_profiles.json"))
    for tag, d in (("an7581", p14), ("an7583", p14b)):
        if isinstance(d, dict) and isinstance(d.get("profiles"), dict):
            keys = sorted(d["profiles"].keys())
            has_xr = any("xr1710g" in k for k in keys)
            lines.append(f"- **{tag}** profiles（{len(keys)}）：{'、'.join(keys) or '—'}")
            if has_xr:
                lines.append("> [!IMPORTANT]")
                lines.append("> **新设备信号：官方 snapshot 出现 XR1710G 专属 profile** → 评估脱离 W1700K 覆盖、直接采用官方镜像")
                lines.append("")
            if "gemtek" in tag or tag == "an7581":
                gem = [k for k in keys if "gemtek" in k]
                lines.append(f"  - 同板 Gemtek profile：{'、'.join(gem) or '无（官方仍无 XR1710G 专属 profile，= W1700K 同硬件覆盖）'}")
            if tag == "an7581":
                kver = d.get("linux_kernel", {})
                lines.append(f"  - snapshot linux_kernel: {kver.get('version', '?')}  git_commit: {str(d.get('git_commit', ''))[:12]}")
        else:
            lines.append(f"- **{tag}** profiles：无数据/失败")
        lines.append("")
    # 与上一份 raw 对比新增 profile
    if prev_path:
        pp = read_json(os.path.join(prev_path, "14_an7581_profiles.json"))
        # prev_path 是上一份 raw 目录
        if isinstance(pp, dict) and isinstance(pp.get("profiles"), dict) \
                and isinstance(p14, dict) and isinstance(p14.get("profiles"), dict):
            old = set(pp["profiles"].keys())
            new = set(p14["profiles"].keys())
            diff = new - old
            if diff:
                lines.append(f"- **对比上一期新增 profile**：{'、'.join(sorted(diff))}")
            lines.append("")
    lines.append("")

    # --- 新 hostapd 版本 ---
    cur_v = version_latest(os.path.join(r, "06_w1fi_hostapd_versions.txt"))
    lines.append("### hostapd 上游版本（源#6）")
    lines.append("")
    if cur_v:
        lines.append(f"- 最新：**{cur_v}**")
        if prev_path:
            prev_v = version_latest(os.path.join(prev_path, "06_w1fi_hostapd_versions.txt"))
            if prev_v and prev_v != cur_v:
                lines.append("> [!IMPORTANT]")
                lines.append(f"> **新 hostapd 版本发布：{prev_v} → {cur_v}** → 评估安全修复 & 同步构建")
                lines.append("")
            elif prev_v:
                lines.append(f"- 与上一期（{prev_v}）一致，无新版")
        else:
            lines.append("- 基线：2.12（调研快照 2026-08-15 时最新）；无历史对比文件")
    else:
        lines.append("- （无数据/失败）")
    return lines


def version_latest(path):
    t = read_text(path)
    if not t:
        return None
    vers = sorted({v.strip() for v in t.splitlines() if v.strip()},
                  key=lambda v: [int(x) for x in re.findall(r"\d+", v)])
    return vers[-1] if vers else None


def render_risk(r, status, commits_airoha, commits_mt76, head_txt):
    """③ 风险变化：R1–R10 逐项，自动信号能算的算，算不了标人工"""
    mt76_subj = " ".join(s for _, _, s in commits_mt76) if commits_mt76 else ""
    mlo = sum(1 for s in re.split(r"\s(?=[a-z0-9]{8,})", mt76_subj) or [mt76_subj]
              if re.search(r"MLO|eMLSR", s, re.I))
    cve = re.findall(r"CVE-\d{4}-\d+", mt76_subj + " " + (" ".join(s for _, _, s in commits_airoha) if commits_airoha else ""))
    skip_cnt = sum(1 for s, _ in (status or {}).values() if s == "SKIP")
    rl = any(n and any(k in n.lower() for k in ("rate limit", "403", "429"))
             for _, n in (status or {}).values())
    rl_hint = "（含限流/403 迹象）" if rl else ""
    rows = [
        ("R1", "刷错槽位变砖", "—（人工：SOP 明令禁止；无自动源）", "不变"),
        ("R2", "UBI 布局破坏", "—（人工：仅用 XR1710G 专属包）", "不变"),
        ("R3", "6GHz 无授权使用", "—（静态合规约束，报告明示）", "不变"),
        ("R4", "CVE-2025-68360 面", f"—（人工核对；本期上游提交含 CVE 提及：{'、'.join(sorted(set(cve))) or '无'}）", "不变"),
        ("R5", "YYH U-Boot 单点依赖", "—（人工：备份镜像+串口回刷路径入 SOP）", "不变"),
        ("R6", "自主分支 rebase 债", f"auto：本期 airoha 提交（API）{len(commits_airoha)} 条 ／ main HEAD {head_txt}", "跟踪中"),
        ("R7", "驱动快速变化期不稳定", f"auto：mt76 mt7996 提交 {len(commits_mt76)} 条（含 MLO/eMLSR 相关 {mlo} 条）", "跟踪中"),
        ("R8", "双 10G 同接 Web UI 失联", "—（人工：论坛 #247242 回填）", "不变"),
        ("R9", "MLO 不成熟", "auto：上游持续修复中（见 R7 MLO 计数），仍定位实验项", "跟踪中"),
        ("R10", "论坛/恩山反爬与登录墙", f"auto：本期源 SKIP={skip_cnt} 条 {rl_hint}", "跟踪中"),
    ]
    lines = [""]
    lines.append("| # | 风险 | 本报告自动信号 | 判定 |")
    lines.append("|---|---|---|---|")
    for rid, name, sig, verdict in rows:
        lines.append(f"| {rid} | {name} | {sig} | {verdict} |")
    lines.append("")
    lines.append("> 说明：能自动计算的信号由本期 raw 数据推导；标「人工」项沿用调研基线，由人类周期核对（SOP / 论坛 / NVD）。")
    return lines


def render_bilnd(r, status, commits_airoha, commits_mt76, p14, p14b):
    """④ 盲区监测点：03 §5 六条预判逐条检查"""
    lines = [""]
    glog = read_text(os.path.join(r, "03_git_openwrt_log.txt")) or ""
    glog_ok = bool(glog)
    glog_subj = " ".join((m.group(0) for m in re.finditer(r"[a-z0-9]+\s+\S+\s+(.+)$", glog, re.M)))
    latest_rel = read_text(os.path.join(r, "15b_latest_release_targets.txt")) or ""
    rel_dir = read_text(os.path.join(r, "15_releases_dir.txt")) or ""
    rel_vers = "、".join(sorted(set(re.findall(r"\b\d+\.\d+\.\d+\b", rel_dir)))) or "无数据"
    linux_dts = read_json(os.path.join(r, "16_gh_linux_airoha_dts.json")) or []

    # 1. AN7581/7583 稳定版镜像（中概率）
    stable_hit = False
    if "NO_AIROHA_IN_TARGETS" in latest_rel:
        verdict = "未命中"
        note = f"最新 release targets 无 airoha（{latest_rel.splitlines()[0] if latest_rel else '?'}）"
    elif "airoha" in latest_rel.lower():
        verdict = "**命中 ⚡（构建/基线信号）**"
        stable_hit = True
        note = "releases 最新版 targets 出现 airoha"
    elif not latest_rel:
        verdict = "数据缺失"
        note = "15b 文件缺失/抓取失败 → 人工核查 releases/"
    else:
        verdict = "未命中"
        note = "（探测结果为空但无 NO_AIROHA 标记，见 15b 原文）"
    lines.append(f"1. **AN7581/7583 稳定版镜像出现**〔源#15〕 → {verdict}")
    lines.append(f"   - {note}；releases 版本目录：{rel_vers[:200]}")
    lines.append("")

    # 2. AN7583 设备放量（高概率）
    a83 = 0
    if isinstance(p14b, dict) and isinstance(p14b.get("profiles"), dict):
        a83 = len(p14b["profiles"])
    glog_a83 = len(re.findall(r"an7583|XG-040G-MF", glog, re.I))
    hit2 = a83 > 0 or glog_a83 > 0
    glog_txt = (f"近 14 天日志提及 an7583/XG-040G-MF 提交 {glog_a83} 条"
                if glog_ok else "03 定向日志 SKIP（本环境 git 端点不可用），无日志侧证据")
    lines.append(f"2. **AN7583 设备放量**〔源#14b + 日志〕 → {'**有动向**' if hit2 else '未命中'}")
    lines.append(f"   - an7583 profiles 数={a83}；{glog_txt}")
    lines.append("")

    # 3. Linux 主线吸收 AN7581（中概率）
    anc = []
    if isinstance(linux_dts, list):
        for sha, dt, subj in commits_from_json(linux_dts):
            if re.search(r"an7581", subj, re.I):
                anc.append((sha, subj))
    if anc:
        lines.append(f"3. **Linux 主线吸收 AN7581 驱动**〔源#16 torvalds dts/airoha〕 → **有动向**（{len(anc)} 条）")
        for sha, subj in anc[:5]:
            lines.append(f"   - `{short(sha)}` {subj}")
    elif linux_dts == []:
        lines.append("3. **Linux 主线吸收 AN7581 驱动**〔源#16〕 → 未命中（30 天窗口 dts/airoha 无 AN7581 提交，仍仅 en7581）")
    else:
        lines.append("3. **Linux 主线吸收 AN7581 驱动**〔源#16〕 → 数据缺失/抓取失败")
    lines.append("")

    # 4. MT7992 设备出现（中概率）
    p_keys = ""
    if isinstance(p14, dict) and isinstance(p14.get("profiles"), dict):
        p_keys = " ".join(p14["profiles"].keys())
    kite = "kite" in p_keys.lower()
    m7992 = bool(re.search(r"7992", glog_subj + " " + mt_subj_text(commits_mt76), re.I))
    lines.append(f"4. **MT7992 设备出现**〔源#14 + #5〕 → {'**有动向**' if (kite or m7992) else '未命中'}")
    lines.append(f"   - an7581 profiles 含 kite(MT7992 EVB)：{'是' if kite else '否'}；mt76/日志提及 MT7992：{'是' if m7992 else '否'}")
    lines.append("")

    # 5. 社区固件主线化（高概率）
    lines.append("5. **社区固件持续主线化**〔源#11 通知驱动〕 → **人工回填**（本循环不抓社区 Releases：naoki66 / orangeyoo / hx801217，API 开销换低信息量，见 README）")
    lines.append("")

    # 6. hostapd 2.12.x 点版本与安全公告
    hv = version_latest(os.path.join(r, "06_w1fi_hostapd_versions.txt"))
    sec_txt = "日志 SKIP，无提交侧证据"
    if glog_ok:
        glog_sec = re.findall(r"[a-z0-9]+\s+\S+\s+(.+)?", glog, re.M)
        sec = [m for m in glog_sec if re.search(r"security|advisory|hostapd", str(m), re.I)]
        sec_txt = f"日志中 hostapd/安全相关提交 {len(sec)} 条"
    lines.append(f"6. **hostapd 2.12.x 点版本与安全公告**〔源#6 + 日志〕 → {'**有新版/安全提交**' if (hv and hv != '2.12') else '未命中（上游仍 2.12 系）'}")
    lines.append(f"   - 当前目录页最新：{hv or '无数据'}；{sec_txt}")
    lines.append("")
    return lines, stable_hit


def mt_subj_text(cm):
    return " ".join(s for _, _, s in cm)


def render_appendix(r, status):
    lines = ["## 附录 · 源状态与原始数据", ""]
    lines.append(f"- 原始数据目录：`{os.path.relpath(r, ROOT)}`")
    lines.append(f"- 报告生成：{TS}（UTC）· 脚本 scripts/tracking/report.py · 消费方 M4 自动跟进循环")
    lines.append("")
    if status:
        lines.append("| 源 | 状态 | 原因/备注 |")
        lines.append("|---|---|---|")
        for src in sorted(status):
            st, note = status[src]
            lines.append(f"| {src} | **{st}** | {note or '—'} |")
    else:
        lines.append("（99_STATUS.tsv 缺失：fetch.sh 未运行或未写状态）")
    lines.append("")
    lines.append("> 限流约定：GitHub API 未认证 60 次/时（本循环常规 4 次/run、回退最坏 ≤8 次）；论坛 search.json ⩽1 次/分（不自动抓）；恩山人工。")
    return lines


def main():
    args = parse_args()
    today = datetime.date.today().isoformat()
    raws, date = find_raw(args, today)
    files = [f for f in os.listdir(raws) if os.path.isfile(os.path.join(raws, f))] if os.path.isdir(raws) else []
    out = args.out or os.path.join(OUT_ROOT, f"{date}.md")

    # ---- 占位：无 raw / 空 raw / 无 STATUS ----
    no_data = (not os.path.isdir(raws)) or not files or read_text(os.path.join(raws, "99_STATUS.tsv")) is None
    if no_data:
        txt = [
            f"# XR1710G 上游跟踪报告 · {date}",
            "",
            "**今日无数据**（`{}` 不存在或为空）。".format(os.path.relpath(raws, ROOT)),
            "",
            "请先运行：`bash scripts/tracking/fetch.sh {}`，再运行 `python3 scripts/tracking/report.py --date {}`。".format(date, date),
            "",
            f"- 生成时间：{TS}（UTC）",
            "",
        ]
        write_out(out, txt)
        print(f"== 占位报告已写出: {out}（无 raw 数据） ==")
        return 0

    status = parse_status(os.path.join(raws, "99_STATUS.tsv")) or {}

    # 上一期 raw 目录（同日补跑取更早一期；用于 diff）
    cands = [n for n in sorted(os.listdir(OUT_ROOT), reverse=True)
             if re.match(r"^\d{4}-\d{2}-\d{2}\.raw$", n) and n < os.path.basename(raws)] if os.path.isdir(OUT_ROOT) else []
    prev = os.path.join(OUT_ROOT, cands[0]) if cands else None

    commits_airoha = commits_from_json(read_json(os.path.join(raws, "04_gh_airoha_commits.json")))
    commits_mt76 = commits_from_json(read_json(os.path.join(raws, "05_gh_mt76_commits.json")))
    p14 = read_json(os.path.join(raws, "14_an7581_profiles.json"))
    p14b = read_json(os.path.join(raws, "14b_an7583_profiles.json"))

    head_now = (read_text(os.path.join(raws, "01_git_lsremote.txt")) or "").splitlines()
    head_now = head_now[0].split("\t")[0] if head_now else None
    head_prev = None
    if prev:
        p = (read_text(os.path.join(prev, "01_git_lsremote.txt")) or "").splitlines()
        head_prev = p[0].split("\t")[0] if p else None
    head_changed = bool(head_now and head_prev and head_now != head_prev)
    if head_now is None:
        head_txt = "未知（源#1 SKIP）"
    elif head_prev is None:
        head_txt = "首次运行（无基线）"
    else:
        head_txt = "有更新" if head_changed else "无变化"

    bilnd, stable_hit = render_bilnd(raws, status, commits_airoha, commits_mt76, p14, p14b)

    lines = [
        f"# XR1710G 上游跟踪报告 · {date}",
        "",
        f"- 生成时间：{TS}（UTC）· fetch.sh + report.py（M4 自动跟进循环）",
        f"- 抓取窗口：近 14 天 UTC（源级 since 参数）",
        f"- 原始数据：`docs/tracking/{date}.raw/`（每源一文件 + 99_STATUS.tsv）",
        f"- 源状态摘要：OK={sum(1 for s, _ in status.values() if s == 'OK')} / SKIP={sum(1 for s, _ in status.values() if s == 'SKIP')}（明细见附录）",
        "",
        "## ① 上游动态",
        "",
    ]
    lines += render_upstream(raws)
    lines += ["## ② 构建触发信号", ""]
    lines += render_triggers(raws, prev)
    lines += ["## ③ 风险变化", ""]
    lines += render_risk(raws, status, commits_airoha, commits_mt76, head_txt)
    lines += ["## ④ 盲区监测点（03 §5 · 6 条预判）", ""]
    lines += bilnd
    lines += render_appendix(raws, status)

    write_out(out, lines)
    print(f"== 报告已生成: {out} ==")
    print(f"== 源状态: OK={sum(1 for s, _ in status.values() if s == 'OK')} "
          f"SKIP={sum(1 for s, _ in status.values() if s == 'SKIP')} "
          f"（共 {len(status)} 条，明细见 99_STATUS.tsv / 附录） ==")
    return 0


def write_out(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).rstrip() + "\n")


if __name__ == "__main__":
    sys.exit(main())
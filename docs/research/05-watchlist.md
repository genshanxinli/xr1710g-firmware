# 05 · 盯梢清单（情报源）

> 调研日期：2026-08-15。供"自动跟进循环"（M4）消费；频率建议已按情报价值标注。✓=已核实可用；✗=受限/未能确认。

## 清单

| # | 源 | URL / 命令 | 盯什么 | 频率 |
|---|---|---|---|---|
| 1 | git.openwrt.org cgit 日志（路径过滤）✓ | `https://git.openwrt.org/openwrt/openwrt/log/?h=main&path=target/linux/airoha` | airoha 提交主题/日期 | 每日 |
| 2 | git.openwrt.org Atom（全库）✓ | `https://git.openwrt.org/openwrt/openwrt/atom/?h=main` | 全库新提交（hostapd/内核 bump） | 每 2-3 日 |
| 3 | git 命令行 ✓ | `git ls-remote https://git.openwrt.org/openwrt/openwrt.git main`；`git log --oneline --since="14 days ago" -- target/linux/airoha package/network/services/hostapd package/kernel/mt76` | 定向日志（可脚本化进 CI） | 每日 CI |
| 4 | GitHub 镜像 API ✓ | `https://api.github.com/repos/openwrt/openwrt/commits?path=target/linux/airoha&since=...` | 同上（未认证 60 次/时） | 每日 |
| 5 | mt76 镜像 ✓ | `https://github.com/openwrt/mt76/commits`；API `commits?path=mt7996` | MT7996/7992 特性与修复 | 每日/隔日 |
| 6 | hostapd/wpa_supplicant 上游 ✓ | `https://w1.fi/releases/`；`https://w1.fi/cgit/hostap/` | 2.12.x 点版本、EHT/MLO/安全 | 每周 |
| 7 | 论坛 #222776 ✓ | `https://forum.openwrt.org/t/222776` | W1700K 实测/固件（3779 楼） | 每周 |
| 8 | 论坛 #247242 ✓ | `https://forum.openwrt.org/t/247242` | XR1710G 同机、双 10G 问题 | 每周 |
| 9 | 论坛 #252504 ✓ | `https://forum.openwrt.org/t/252504` | 社区 build 迭代 | 每周 |
| 10 | 论坛新帖发现 ✓ | `https://forum.openwrt.org/search?q=XR1710G`（search.json ⩽1 次/分，否则 429） | 新主题 | 按需 |
| 11 | GitHub Releases（社区固件）✓ | naoki66 / orangeyoo / hx801217（Watch→Releases only） | 新固件/变更日志 | 通知驱动 |
| 12 | 恩山论坛 ✗ | `https://www.right.com.cn/forum/` | AN7581/XR1710G/W1700K/XG-040G（需登录；本环境 TLS 不可达） | 人工每周 |
| 13 | linux-wireless ML ✓ | `https://lore.kernel.org/linux-wireless/`（q=mt7996） | mt76 补丁终审/RFC | 每周 |
| 14 | 官方 snapshot 镜像 ✓ | `https://downloads.openwrt.org/snapshots/targets/airoha/an7581/`（+profiles.json） | 新设备/新镜像 | 每周 |
| 15 | 官方 release 目录 ✓ | `https://downloads.openwrt.org/releases/` | **25.12.x 是否出现 targets/airoha**（稳定版信号） | 每发布周期 |
| 16 | 硬件资料库 ✓ | `https://techinfodepot.shoutwiki.com/wiki/Brightspeed_XR1710G`（FCC MXF-XR1710G） | 新机型资料 | 按需 |
| 17 | 中文社区 ✓/✗ | `blog.yazawaniko.com`（2026-06-21）；mobile01 f=110&t=7284929 | 中文圈动态 | 每周 |
| 18 | SDK 异动 ✓ | `github.com/lotusmomo/airoha_sdk`（★7，2026-05-13 push，来源待考证） | AN7581 SDK 动向 | 每月 |

## 自动跟进循环建议（M4 落地）

- **抓取**：GitHub Actions scheduled workflow（每周）执行 #1/#3/#4/#5/#6/#14 的 API/git 抓取
- **构建触发**：airotarget/mt76/PR #22397 有提交 → 事件触发分叉构建（事件驱动+每夜保底）
- **报告**：汇总 diff → commit 到仓库 `docs/tracking/`（公开可审计）
- **限速与反爬**：论坛 search API ⩽1 次/分钟；恩山需登录（人工每周回填）
- **稳定版信号**：#15 若出现 targets/airoha → 评估是否锁定 25.12 稳定基线（走 ADR）

## 预判监测点（2026-08 → 2027-02）

1. AN7581/7583 稳定版镜像出现（中概率）→ #15
2. AN7583 设备放量（高概率，XG-040G-MF UBI 8/9 完成）→ #1/#14
3. Linux 主线吸收 AN7581 驱动（中概率，multi-serdes/pinctrl 已回移）→ #13
4. MT7992 设备出现（中概率，"Kite" EVB 现成载体）→ #5/#14
5. 社区固件持续主线化（高概率）→ #9/#11
6. hostapd 2.12.x 点版本与安全公告 → #6
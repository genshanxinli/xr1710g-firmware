# XR1710G 固件项目 · 调研总览

> 调研基线：2026-08-15/16。本目录为全 AI 驱动的 XR1710G 固件项目研究阶段交付物。

## 一句话结论

Gemtek XR1710G（Airoha AN7581GT + MT7996 Wi-Fi 7 / BE19000 / 双万兆）正处于**社区先行、主线收尾**的窗口期：刷机与救砖体系成熟、6GHz 802.11s 回程已被多个 6.18 社区构建跑稳、进 OpenWrt 主线只差 PR #22397 合并——**现在入场建分叉，正是吃掉这波红利的时机**。

## 速查

| 维度 | 要点 |
|---|---|
| 设备 | Brightspeed 洋垃圾路由器；FCC MXF-XR1710G；SoC AN7581GT（四核 A53 1.3GHz + 8 核 NPU）；MT7996AV 三频 BE19000（6G EHT320）；2×10G + 2×1G；2GB DDR4 / 512MB NAND；无 USB/WPS/SFP+；已刷 **YYH http-uboot** |
| 生态 | OpenWrt main 内核 **6.18.44**；airoha target 每日演进；**XR1710G PR #22397 open**（已实机验证）；W1700K 已进主线；iStoreOS 官方未收录；社区三条构建线活跃（orangeyoo/naoki66/hx801217） |
| 项目形态 | **公开社区固件 + 情报体系**；完全自主分支；前沿跟踪第一；AI 全流程 + GitHub Actions 自动跟进循环；人类最小集 = 物理操作与发布按键 |
| 集成定义 | **设备能力全集**（硬件全启用可配置），运营商云端功能放弃 |
| 旗舰 | **M3 · 6GHz 无线回程优化固件** |
| 风险 | 刷槽位/UBI 破坏（高）、6GHz 无授权（法律中）、YYH 单点（中）、rebase 债（中，AI 每日循环吸收） |

## 交付物索引

- **调研报告**
  - [01 · 硬件考据](./research/01-hardware.md)
  - [02 · 固件生态与支持状态](./research/02-firmware-ecosystem.md)
  - [03 · 前沿动态与情报（AN7581/MT7996，2026-08-15）](./research/03-frontier-dynamics.md)
  - [04 · 风险清单与路线图 v0](./research/04-roadmap-and-risk.md)
  - [05 · 盯梢清单（情报源）](./research/05-watchlist.md)
- **术语表**：[CONTEXT.md](../CONTEXT.md)
- **架构决策**：[ADR-0001 完全自主分支+事件驱动发布](./adr/0001-distro-strategy.md) · [ADR-0002 设备能力全集边界](./adr/0002-device-capability-boundary.md)
- **M1 开工交付物（2026-08-16）**
  - 自动跟进循环骨架：[抓取脚本](../scripts/tracking/fetch.sh) · [CI workflow](../.github/workflows/tracking.yml) · [盯梢报告样例](./tracking/2026-08-16.md)
  - 救砖体系：[救砖 SOP](./sop/brick-recovery.md) · [互刷边界实验模板](./sop/mutual-flash-experiment-template.md)
  - NPU 指标盘点 v0：[采集脚本](../tools/metrics/collect.sh) · [清单 v0](./metrics/v0.md) · [回填模板](./metrics/backfill-template.md)

## 下一步（M0 启动清单 · 进度）

1. 购机：2 台 Gemtek XR1710G（¥350–400/台，闲鱼搜 "w1700k"）—— ✅ 真机已在手（2026-08-16）
2. 建仓：GitHub 公开仓库（GPL-2.0-or-later），本目录 docs/ 移入—— ✅ 已建 genshanxinli/xr1710g-firmware（2026-08-16）
3. AI 管线骨架：每日同步循环（git.openwrt.org + mt76 抓取）、事件触发构建—— 🚧 骨架产出中（scripts/tracking/ + .github/workflows/）
4. 原厂固件/分区备份 + 救砖 SOP + NPU 指标盘点 v0（人类：拆机/UART/刷机）—— 🚧 SOP 草稿与指标盘点 v0 产出中（docs/sop/、tools/metrics/）

## 路线图一句话

M0 硬件考据与救砖（并行调研期购机）→ M1 基线可刷 → M2 设备能力全集（v1 验收锁）→ M3 旗舰 6GHz 回程 → M4 情报体系上线。
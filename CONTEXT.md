# XR1710G 固件项目

为 Gemtek XR1710G（Airoha AN7581 平台 Wi-Fi 7 路由器）构建"前沿跟踪优先"的公开社区固件，并配套持续跟进上游动态的 AI 驱动情报体系。本术语表只定义概念，不承载实现决策。

## 定位

**设备 (Device)**:
指 Gemtek XR1710G —— Brightspeed/Quantum Fiber 运营商淘汰的 Wi-Fi 7 路由器，市场俗称"洋垃圾"。
_Avoid_: W1700K（同源但不同的产品型号）

**同平台 (Same-Platform)**:
共享 SoC（Airoha AN7581）与射频（MediaTek MT7996）的所有设备；平台级资料、补丁、驱动可在其间通用。
_Avoid_: 同源（仅指同一块板子的设备，如 W1700K）

**同源设备 (Same-Board Device)**:
与 XR1710G 使用同一块主板的设备（如 Gemtek W1700K），资料可直接互相印证。

**设备能力全集 (Device Capability Set)**:
"设备本身的功能"的规范定义——硬件能力全集：三频射频、6GHz、EHT320、双万兆口、硬件卸载、LED/按键等全部启用且可配置。
_Avoid_: 运营商功能（不属于本词条）

**运营商功能 (Carrier Cloud Features)**:
ISP 原厂固件中的云端能力（云 Mesh、家长控制、运营商管理通道）。本项目默认视为负资产，不保留、不复刻；个别值得复刻的须单独 ADR 决策。

**NPU 全功能 (Full NPU Offload)**:
设备能力全集中的硬件卸载验收档：Wi-Fi（含 6GHz 链路）与以太网/PPE 数据面均由 NPU 卸载，且与 mt76 社区特性共存无降级、可观测、可一键开关；含 AP/桥接模式专项与实机盘点闭环。详细验收矩阵见调研报告 04。
_Avoid_: 仅指 Wi-Fi offload（含以太网/PPE 面与 AP 模式）

## 固件策略

**前沿跟踪固件 (Frontier-Tracking Firmware)**:
项目旗舰定位——长期跟随 OpenWrt snapshot 与上游每日动态、保持最新的固件形态；与"稳定基线固件"相位交替：稳定基线期内自动合入挂起，解锁后恢复。
_Avoid_: 稳定基线固件（相位收敛态，见其词条）

**养老固件 (Stable-Legacy Firmware)**:
反义词——锁定版本追求稳定的固件形态。本项目明确不追，仅作对照词记录。
_Avoid_: 稳定基线固件（锁定后仍随相位滚动解锁，非一锁永逸）

**稳定基线固件 (Stable-Baseline Firmware)**:
前沿跟踪的相位收敛态——滚动锚锁定的稳定版本（P0/P1 清零点），作为对外 alpha 交付与"养老"回退对象；锁定后上游自动合入挂起，解锁才恢复前沿跟踪。

**激进改造 (Aggressive Hacking)**:
越过上游边界的自研补丁与魔改。优先级最低：前沿跟踪 > 功能集成 > 激进改造。

**完全自主分支 (Fully Owned Fork)**:
本项目固件基底——基于 OpenWrt main 的自主分支；AI 自动合入上游（含 mt76/hostapd），冲突自动处理或上报；稳定基线期内自动合入挂起，以稳定基线滚动解锁为界恢复（见 ADR-0001 修订）。
_Avoid_: 薄层跟 mainline（被否决）、iStoreOS 分叉（官方未收录）

**补丁两层 (Two-Layer Patchset)**:
分叉内自研改动分两层：设备适配层（XR1710G dts/RTL8261BE/LED/chainloader 等，能上提 PR 就上提）与激进调优层（NPU/PPE 调优、6GHz 回程参数等，本地维护）。

**主动消解 (Proactive Patch Re-Roll)**:
不等上游合入的补丁维护方式——把设备适配层持续 re-roll 对齐现网 main；上游合入只当 bonus 而非前提（见 ADR-0003 修订）。
_Avoid_: 被动等待合并（按设计标红等 PR 的旧路线）

**YYH 路线 (YYH Route)**:
引导链维护面采用社区 YYH2913 http-uboot（替换 bootloader 槽、免拆机 HTTP 恢复/刷机、长按 reset 进 192.168.255.1）。upstream chainloader 为文档备选路线。
_Avoid_: 一台机器混装两条路线（见"一机一路线"）

**一机一路线 (One Device One Route)**:
U-Boot 路线互斥规则——每台机器只走一条引导链路线（YYH 或 upstream chainloader），不叠加；互刷边界以 M0 实机实验为准。

**救砖 (Brick Recovery)**:
从变砖状态经 U-Boot 恢复页/串口/编程器等手段恢复的过程；属于"人类最小集"。

**旗舰 (Flagship)**:
路线图 M3 的"6GHz 无线回程优化固件"——本项目面向社区的招牌交付物。

## 工程方式

**全 AI 驱动管线 (AI-Driven Pipeline)**:
调研 → 决策 → 代码 → 构建 → 测试 → 发布全流程由 AI 代理执行的方式。

**人类最小集 (Minimal Human Set)**:
唯一必须人工干预的部分——物理兜底动作：拆机、UART 飞线、编程器救砖、按 reset 进 U-Boot 恢复页、断电重启、首刷人工放行、发布按键。常规 sysupgrade 刷写与测试数据采集划归 AI（见"真机自动回归"）。

**自动跟进循环 (Auto-Tracking Loop)**:
无人值守的周期任务：定期拉取上游动态 → 构建 → 对比 diff → 产出跟踪报告；是"跟踪前沿状态最全"的机制化载体。

**盯梢清单 (Watchlist)**:
需要持续监控的情报源清单（上游仓库、论坛帖、邮件列表、发布渠道），由自动跟进循环消费；详见调研报告 05。

**事件驱动发布 (Event-Driven Release)**:
发布节奏规则——上游有动静（airotarget/mt76/hostapd/PR #22397）即触发构建，另加每夜保底留档；里程碑打 tag。

**指标盘点闭环 (Metric Inventory Loop)**:
NPU 等验收指标的收集机制——AI 出全量抓取脚本，真机回填，以实机面板为准滚动收录，清单版本化；纸上列不全的由机制补全。

**真机自动回归 (Auto Regression Loop)**:
AI 对真机执行刷入-测试-数据回填的自主验证循环（常规 sysupgrade 刷写、冒烟、指标采集自动化）；失败兜底与首刷放行归人类最小集。

**社区基线参照 (Community Baseline Reference)**:
以社区声称稳定的内核版本（如 6.18.41）为 bug 归因参照系——同一缺陷在社区基线成立 = 上游问题，不成立 = 己方补丁问题；在无对照真机时替代双机对照。

**可复现构建 (Reproducible Build)**:
公开发布的固件必须可由公开的构建脚本与 configs 复现，同时满足 GPL 合规义务。
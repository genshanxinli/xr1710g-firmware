# 互刷边界实验记录模板（M0）

> 用途：M0「硬件考据与救砖」验收项——**YYH U-Boot ↔ chainloader 槽位互刷边界、恢复顺序、HTTP 恢复页全流程** [04§2]。本模板的字段必须逐项回填，产出=「互刷边界实验报告」。
> 事实预填基于：报告 `01-hardware.md`[01] / `02-firmware-ecosystem.md`[02] / YYH README[YYH]，2026-08-16。
> 想解决的问题：CONTEXT「一机一路线」= 每台机器只走一条引导链；**能否在同一台机器上 YYH ↔ upstream chainloader 互刷回退、边界在哪**，纸上无定论，交给这台模板。
> ⚠️ 实验纪律：单机单实验、每步先备份（见 SOP §2）、日志/截图留证、报错即停并回填【未确认】项。所有写入动作【人类】执行。

## 1. 实验总览（每次实验一行）

| # | 日期 | 设备序列号 | 设备型号 | 当前引导链 | 实验动作 | 预期 | 实际结果 | 日志/截图引用 | 结论 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | | | XR1710G | | | | | | |
| 2 | | | XR1710G | | | | | | |
| 3 | | | XR1710G | | | | | | |
| … | | | | | | | | | |

### 动作字典（实验动作取值，按 M0 验收范围定）

- **A1** YYH→upstream：从 YYH 状态经 ECNT 串口写 upstream chainloader（SOP §4 序列，镜像 `gemtek_xr1710g-ubi-chainload-uboot.itb`）
- **A2** upstream→YYH：从 chainloader 状态回刷 YYH（SOP §7.2，`xr1710g-chainloader-slot.bin`）
- **B1** 恢复顺序：依次验证 恢复页重装 → ECNT 串口写槽 → UBI 安装器重装 的依赖关系（哪一级失败会掉到哪一级）
- **B2** HTTP 恢复页全流程：上电 → 10G LED 起闪 → 长按 reset → 常红→流动灯效 → 192.168.255.1 → `firmware` 目标刷 sysupgrade → 布局选择器（UBI 2.0/1.5/1.0 各一次）
- **B3** 恢复页 `uboot` 目标刷 YYH 本体（验证 ⚠️ 红区：`u-boot.bin`/系统 ITB 应被拒绝或明文禁止）
- **C1** 各状态间**回退可达性**综合判定（见 §4）

## 2. 长按 reset / 恢复入口行为速查表

> 预填=报告/README 已知事实；【空】= 文献无载，**真机回填**。每行都是可观察行为断言，回填时标注：`✅符合 / ✗不符（差异描述） / 未测`。

| 引导链状态 | 上电默认行为 | 长按 reset 行为 | 恢复入口 | 备注/回填 |
|---|---|---|---|---|
| 出厂 ECNT U-Boot（原厂） | 签名 bootcmd 只跑签名镜像；串口任意键可中断 [01§4] | 【空】 | 无 HTTP 恢复页；入口=串口中断 → TFTP/flash write [01§4][01§8] | |
| YYH http-uboot | 10G 口 LED 起闪 → 状态 LED 灯效 [YYH] | **10G 口 LED 起闪后长按**，状态 LED **常红→流动恢复灯效**后松 → `http://192.168.255.1`（内置 DHCP，PC 接 10G 口）[YYH] | HTTP 恢复页（`firmware`→sysupgrade→ubi:fit；`uboot`→chainloader 槽）[YYH] | 1G 口是否可进【空】 |
| upstream chainloader（PR #22397） | U-Boot Boot Menu（1..5/0）[02§1.1][HURR] | 【空】 | 菜单 `3. Boot recovery` / `4. Boot installer via TFTP` [HURR]；无 HTTP 恢复页 [02§3] | 菜单触发按键/时序【空】 |
| 完全无响应 | 无任何输出/LED | 无 | 无 → NAND 编程器（SOP §6 档位 T4）[02§6 path6] | |

**回填专项（文献未载、必须真机回答）**：
1. 出厂 ECNT 与 upstream chainloader 上，长按 reset 究竟触发什么？
2. YYH 恢复页从 1G 口能否打开？（README 只载 10G 口）
3. upstream 菜单出现前是否有按键窗口/倒计时，具体几秒？

## 3. 单条实验记录（复制使用）

```text
实验编号：#N（对应 §1 总览行）
日期：YYYY-MM-DD
设备：序列号 ______ / 型号 XR1710G / 固件基线（如：OpenWrt r35778 / 社区构建版本号）______
当前引导链：□ YYH http-uboot（版本/commit：______，SHA256 备份：______）
            □ upstream chainloader（artifact：______）
实验动作（A1/A2/B1/B2/B3/C1 + 描述）：
前置状态检查（备份在哪 / /proc/mtd 快照 / 当前 bootcmd printenv）：
  ① 备份：路径 ______，nanddump 头 1MiB SHA256 ______
  ② 当前 bootcmd：______
  ③ 当前 UBI 布局（恢复页选择器所见 / Linux dmesg）：______
预期（写明可测断言，如"reset 后恢复页 30s 内可开"）：
步骤记录（时间线，含每个【人类】按键与【AI】给的命令）：
  1. ______
  2. ______
实际结果（✅/✗ + 现象描述）：
日志/截图引用（文件路径或帖链接）：
结论（该动作能否执行/能否回退到上一状态）：
失败后的降级去向（观测到掉到哪条路径）：______
```

## 4. 回退可达性判定（C1，实验全部完成后汇总）

对**每对**（起点链, 终点链）填：`可达（路径）/ 不可达（卡在哪）/ 未测`。

| 起点 → 终点 | 出厂 ECNT | YYH | upstream chainloader | 全砖 |
|---|---|---|---|---|
| 出厂 ECNT | — | 串口写槽（A2 同序列） | 串口写槽（A1） | — |
| YYH | 串口回写原厂备份（若有） | — | A1 | — |
| upstream chainloader | 串口回写原厂备份（若有） | A2 | — | — |
| 全砖 | 编程器（SOP 路径 E，未确认） | 编程器 | 编程器 | — |

**综合结论（M0 验收输出）**：`能否互刷回退：□ 能 □ 不能 □ 部分（描述边界）`；对 CONTEXT「一机一路线」的修订建议：______。

## 5. 引用与来源

- [01] `docs/research/01-hardware.md` §4/§8（存储引导、串口）
- [02] `docs/research/02-firmware-ecosystem.md` §3/§6（引导链、救砖路径 1–6）
- [YYH] github.com/YYH2913/http-uboot README（恢复页全流程、ECNT 环境、槽位布局）
- [HURR] github.com/hurrian/w1700k-ubi-installer README（U-Boot 菜单、串口安装序列）
- 主线依据：`docs/sop/brick-recovery.md`
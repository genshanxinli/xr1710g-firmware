# 设备适配层 · Gemtek XR1710G（OpenWrt 主线支持 · 补丁集 v2）

> 本目录是分叉固件"**设备适配层**"的补丁集仓库：**`pr22397.diff` = 当前权威补丁集
> （v2，2026-08-17 re-roll 对齐现网 main）**；`pr22397-v1-snapshot-20260815.diff` =
> 上游 PR #22397 原样快照（归档只读）；`pr22397-v2-20260817.diff` = v2 生成记录。

## 这是什么

OpenWrt PR #22397（openwrt/openwrt「airoha: add support for Gemtek XR1710G」，作者
hurrian，状态 **open + APPROVED**）的**分叉内 re-roll 补丁集**。PR 全貌见
`pr22397-v1-snapshot-20260815.diff`（12 文件：3 新 + 2 重命名 + 7 修改）。

## v2 re-roll（2026-08-17，D1 主动消解交付）

PR 基于 2026-03 的 main；现网 main（2026-08-17 HEAD 20d94d5，内核 6.18.44、hostapd
2.12）已大幅演化，原 diff **5 处冲突**（uboot-airoha Makefile / uboot-envtools
airoha_an7581 / platform.sh / an7581-w1700k-ubi.dts / an7581.mk）。v2 逐处 re-roll：

| PR 原设计 | v2 处置 | 理由 |
|---|---|---|
| `an7581-gemtek-17xx-common.dtsi` 公共 dtsi 抽取 + w1700k dts 重构 | **弃用重构**：xr1710g dts 改为**独立成文**（基于现网 w1700k dts 模板），w1700k dts 零改动 | 现网 w1700k dts 已含重大演化（BMT/BBT 新分区表 compat 2.0、pcie0 regs/resets、PHY 极性 API、uart2/hsuart）；照搬 PR 重构会回归 w1700k。公共抽取等 PR 合入后由上游自然带来，不自造轮子 |
| w1700k 的 `kmod-phy-rtl8261n` 包 | xr1710g 保留（RTL8261BE 驱动） | 现网 pkg 仍在（netdevices.mk） |
| PHY 描述 `realtek,pnswap-{tx,rx}` + interrupt-parent/interrupts | 改用现网 w1700k 同款 **`tx-polarity`/`rx-polarity = PHY_POL_INVERT`**（interrupts 注释保留） | 对齐当前 RTL826x 驱动 API |
| an7581.mk `$(Device/gemtek_17xx-common)` | 独立完整 recipe（镜像 w1700k 现网全文 + COMPAT_VERSION 2.0 + rtl8261n） | 无公共 define |

**v2 组成（10 文件）**：2 重命名（998→997 / 999→998）+ 1 新 U-Boot 补丁
（999-xr1710g chainloader）+ 1 新设备树（an7581-xr1710g-ubi.dts 独立版）+ 6 修改
（uboot Makefile / envtools / 02_network / airoha_fan / platform.sh / an7581.mk）。

**验证（D1 完成依据）**：v2 在最新 main（20d94d5）上 `git apply --check` 全绿 +
defconfig 冒烟三断言通过（`CONFIG_TARGET_airoha=y` / `gemtek_xr1710g-ubi` profile /
`u-boot-an7581_gemtek_xr1710g` 变体自动选中，无 F7 choice 冲突）。

## 目录结构（v2）

```
build/patches/device-layer/
├── pr22397.diff                          # 当前权威补丁集（= v2）
├── pr22397-v1-snapshot-20260815.diff     # 上游 PR #22397 原样归档（只读）
├── pr22397-v2-20260817.diff              # v2 生成记录（与 pr22397.diff 同内容）
├── package/boot/uboot-airoha/
│   ├── Makefile.patch                    # 注册 an7581_gemtek_xr1710g U-Boot 目标
│   └── patches/
│       ├── 997-airoha-add-snfi-label.patch        # 重命名（编号腾位）
│       ├── 998-airoha-add-gemtek-w1700k.patch     # 重命名
│       └── 999-airoha-add-gemtek-xr1710g.patch    # 新：chainloader 补丁全文
├── package/boot/uboot-tools/uboot-envtools/files/airoha_an7581.patch
└── target/linux/airoha/
    ├── an7581/base-files/...             # 02_network / airoha_fan / platform.sh 的 .patch
    ├── dts/an7581-xr1710g-ubi.dts        # 新：独立设备树全文（现网 w1700k 模板派生）
    └── image/an7581.mk.patch             # xr1710g 镜像 recipe（独立完整块）
```

归档约定：**新文件**存全文（可直接覆盖工作树）；**修改文件**存 per-file patch fragment
（`git apply` 即单独生效）；重命名保留为当前 main 已存在路径下的编号。

## 如何应用（分叉工作树 = OpenWrt main 快照）

```bash
git apply --check build/patches/device-layer/pr22397.diff && \
git apply build/patches/device-layer/pr22397.diff
```

或按需应用单个 fragment（路径见上表）。CI 双路径（`.github/workflows/build.yml`）：
整 diff 干净则一步应用；冲突则新文件覆盖 + per-file 逐个应用，箭头归档
`conflict-archive/`、job 失败不静默。

## 为何叫"设备适配层"（对照 CONTEXT.md 补丁两层）

1. **设备适配层** —— 让这台机器跑起来的最小必要改动：dts、chainloader 引导、
   RTL8261BE、LED、风扇、target recipe/Makefile 登记。归宿 = 上提 PR（本层即 PR
   #22397 的 v2 载体；PR 合入主线则本层退化为追踪占位）。
2. **激进调优层** —— 越过上游边界的自研魔改（NPU/PPE 调优、6GHz 回程参数等），
   放 `build/patches/tuning/`（未开工），撞上游先修适配层。

判别口诀：**能上提 PR 的就进适配层；只能本地维护的进调优层。**

## re-roll 流程（主动消解 · ADR-0003 修订）

- 现网 main 演化导致 v2 冲突时：先 `git apply --check` 定位冲突文件 → 对冲突文件
  以现网文件为基底重做语义变更（新文件全文 / 修改文件新 hunk）→ 重新生成
  `pr22397-v2-<date>.diff` → 冒烟三断言（apply 全绿 + defconfig profile 注册）
  → 替换 `pr22397.diff` 并归档旧版。
- **9 修 0 舍**：设备支持一项不丢；结构性重构（公共 dtsi 等）若与上游演进冲突，
  以"最小变更 + 零回归"为准则取舍（见 v2 处置表）。
# 设备适配层 · PR #22397（Gemtek XR1710G 主线支持）

> 归档日期：2026-08-15（与调研快照同日）。本目录是 OpenWrt PR #22397 的完整快照
> 与按原相对路径拆分的文件归档，是分叉固件"**设备适配层**"的第一批原料。

## 这是什么

`pr22397.diff` 是 `https://github.com/openwrt/openwrt/pull/22397.diff` 的**原样完整抓取**
（27743 字节，12 个文件）。PR 标题为 "Gemtek XR1710G support"（作者 hurrian，2026-03-11
起 4 commits），截至归档日 2026-08-15 状态 **open**（peterwillcn 已 APPROVE，IceblueSakura
2026-08-14 已在 main r35778 / Linux 6.18.44 实机验证 chainloader 引导通过）。详见
`docs/research/02-firmware-ecosystem.md §1`。

PR 变更内容（12 文件，拆分为 3 新文件 + 2 纯重命名 + 7 修改）：

| 路径（原仓库相对路径） | 类型 | 作用 |
|---|---|---|
| `package/boot/uboot-airoha/Makefile` | 修改 | 注册 `an7581_gemtek_xr1710g` U-Boot 目标 |
| `package/boot/uboot-airoha/patches/997-airoha-add-snfi-label.patch` | 重命名 | 998→997（让位新补丁序号） |
| `package/boot/uboot-airoha/patches/998-airoha-add-gemtek-w1700k.patch` | 重命名 | 999→998 |
| `package/boot/uboot-airoha/patches/999-airoha-add-gemtek-xr1710g.patch` | **新文件** | **chainloader 补丁**：`configs/an7581_xr1710g_defconfig` + `defenvs/an7581_xr1710g_env` + U-Boot 侧 `an7581-xr1710g-ubi.dts`（265 行） |
| `package/boot/uboot-tools/uboot-envtools/files/airoha_an7581` | 修改 | envtools 增加 xr1710g 板名 |
| `target/linux/airoha/an7581/base-files/etc/board.d/02_network` | 修改 | 网络端口映射（10G WAN/LAN + 1G switch） |
| `target/linux/airoha/an7581/base-files/etc/init.d/airoha_fan` | 修改 | 风扇控制板名分支 |
| `target/linux/airoha/an7581/base-files/lib/upgrade/platform.sh` | 修改 | 升级流程板名分支 |
| `target/linux/airoha/dts/an7581-gemtek-17xx-common.dtsi` | **新文件** | W1700K/XR1710G 共用的 17xx 公共 dtsi（255 行，含 PCIe x2 挂 MT7996、NPU 保留内存、RTL8261BE reset 时序 200000/200000us） |
| `target/linux/airoha/dts/an7581-w1700k-ubi.dts` | 修改 | 重构：拆出公共部分，仅留 W1700K 差异（LED/PHY RTL8261N） |
| `target/linux/airoha/dts/an7581-xr1710g-ubi.dts` | **新文件** | **XR1710G 设备树**（147 行，compatible `gemtek,xr1710g-ubi`，千兆 LED 走 switch 引脚 gpio33/43） |
| `target/linux/airoha/image/an7581.mk` | 修改 | 抽出 `Device/gemtek_17xx-common`，新增 `gemtek_xr1710g-ubi` 镜像 recipe（`kmod-phy-rtl8261n` 处理 RTL8261BE；产 sysupgrade.itb + chainload-uboot.itb） |

## 目录结构（按原相对路径镜像）

```
build/patches/device-layer/
├── pr22397.diff                          # 完整 diff（唯一权威来源）
├── package/boot/uboot-airoha/            # U-Boot 链相关
│   ├── Makefile.patch                    # 修改项 → per-file 补丁
│   └── patches/
│       ├── 997-airoha-add-snfi-label.patch        # 重命名（保留 fragment 备忘）
│       ├── 998-airoha-add-gemtek-w1700k.patch     # 重命名
│       └── 999-airoha-add-gemtek-xr1710g.patch    # 新文件：chainloader 补丁全文
├── package/boot/uboot-tools/uboot-envtools/files/airoha_an7581.patch
└── target/linux/airoha/
    ├── an7581/base-files/...             # 02_network / airoha_fan / platform.sh 的 .patch
    ├── dts/
    │   ├── an7581-gemtek-17xx-common.dtsi   # 新文件全文
    │   ├── an7581-w1700k-ubi.dts.patch      # 修改项 per-file 补丁
    │   └── an7581-xr1710g-ubi.dts           # 新文件全文
    └── image/an7581.mk.patch
```

归档约定：**新文件**存全文（可直接对照/覆盖工作树）；**修改/重命名文件**存 per-file
patch fragment（`git apply` 该 fragment 即可单独应用，提交信息保留在 fragment 头部
diff 行下方；`999-…patch` 本身是 git format-patch 格式，含原作者提交信息）。

## 如何应用到分叉

直接应用完整补丁（分叉工作树 = OpenWrt main 快照时）：

```bash
cd /path/to/fork-src        # 分叉克隆根（注意：不在 build/patches/ 所在仓库内操作 git 写）
git apply --check build/patches/device-layer/pr22397.diff && \
git apply build/patches/device-layer/pr22397.diff
```

或按需只应用某文件 fragment：

```bash
git apply build/patches/device-layer/target/linux/airoha/image/an7581.mk.patch
```

或整目录覆盖（新文件直接拷入工作树，修改文件用 patch 应用）：

```bash
# 新文件
cp -a build/patches/device-layer/target/linux/airoha/dts/an7581-xr1710g-ubi.dts \
      worktree/target/linux/airoha/dts/
# 修改文件
git -C worktree apply build/patches/device-layer/.../Makefile.patch
```

> 注意：PR #22397 基于 2026-03 的 main；分叉基线若是更新 main，公共 dtsi 拆分、
> uboot-airoha PKG_VERSION（现 2026.07）、`an7581.mk` 的 `Device/gemtek_17xx-common`
> 均可能与当下 main 冲突——**应用前先 `git apply --check`**，冲突时以新文件全文
> 手工合并（这正是"完全自主分支每日自动合入上游"流程要处理的冲突面之一）。

## 为何叫"设备适配层"（对照 CONTEXT.md 补丁两层）

CONTEXT.md「补丁两层」定义：

1. **设备适配层** —— 让这**台机器**跑起来的最小必要改动：dts、链路相关（chainloader
   引导）、硬件差异（RTL8261BE、LED、风扇）、target recipe/Makefile 登记。上提 PR
   是首选归宿：本层全部 12 个文件就是 PR #22397 本体，若 PR 合入主线则本层归零（或
   退化为"追踪该 PR 直至合并"的占位）。
2. **激进调优层** —— 越过上游边界的自研魔改：NPU/PPE 卸载调优、6GHz 802.11s 回程
   参数、运营商功能裁剪等。**不在此目录**，建议放 `build/patches/tuning/`（目录约
   定见 `docs/research/06-build-recon.md §6`），撞上游先修适配层、调优层永远本地维护。

判别口诀：**能上提 PR 的就进适配层；只能本地维护的进调优层。**

## 抓取与校验

- 抓取命令：`curl -sL https://github.com/openwrt/openwrt/pull/22397.diff`
- 完整性：diff 共 12 个 `diff --git` 头、3 个 `new file`；归档目录 13 个条目
  （12 文件 + 本 README）；`pr22397.diff` SHA256 与归档文件可交叉核对（fragment
  拼接应还原出完整 diff）。
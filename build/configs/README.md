# build/configs/ · 构建配置（.config 骨架）

> 生成环境与日期见文件头。本目录存放分叉可复现构建的配置快照；**权威源在
> `/home/harness/workspace/openwrt-src/.config`（仓库外克隆工作树）**。

## 文件清单

| 文件 | 内容 | 适用 |
|---|---|---|
| `an7581-gemtek-w1700k.config` | 完整 .config 快照（278KB，7280 行），target=`airoha/an7581`，profile=`DEVICE_gemtek_w1700k-ubi`，最简包集（640 个 `=y`） | M1 基线骨架（当前推荐） |
| `README.md` | 本说明 | — |

## 骨架设计决策（对照 PR #22397）

1. **用 `gemtek_w1700k-ubi` 而非 `gemtek_xr1710g-ubi`**：PR #22397 未合入 main，
   main 里只有 W1700K profile。XR1710G = 同板（17xx 公共 dtsi）+ 自定义 dts
   （`an7581-xr1710g-ubi.dts`，在 `build/patches/device-layer/` 归档）。
   **CI 不再手工维护 xr1710g config**：`.github/workflows/build.yml` 以本快照为
   种子，现场做器件符号切换（w1700k→xr1710g）+ `make defconfig` 种子自举，自动
   生成 xr1710g 档 config（作为构建输入与 GPL 归档产物）；
   **PR 合入前 w1700k 档即占位**（seed 前的主流程绿灯 canary）。
2. **RTL8261BE / RTL8261N（10G PHY）**：不显式出现在 .config——由 an7581.mk 的
   **每设备 recipe 的 `DEVICE_PACKAGES += kmod-phy-rtl8261n`** 带入
   （`gemtek_w1700k-ubi` 与 `gemtek_xr1710g-ubi` 各一行；注意不是
   `Device/gemtek_17xx-common` recipe 块——公共块里 PR 反而用 `-` 前缀从继承集
   移除该包，再由各设备 recipe 自行 `+=`）。切换 XR1710G profile 即自动获得
   RTL8261BE 支持（内含 reset 时序 200000/200000us）。
3. **chainloader**：`uboot-airoha` 目标（`an7581_xr1710g` defconfig）由 device-layer
   补丁提供（`999-airoha-add-gemtek-xr1710g.patch`）。骨架未显式勾选 U-Boot 包——
   也**不需要**：u-boot 变体是 `DEFAULT y if <器件选定>` 的**隐藏包**，defconfig
   即自动启用（实测当前 main 生成 `CONFIG_PACKAGE_u-boot-an7581_gemtek_w1700k=y`，
   无任何手动 `CONFIG_PACKAGE_uboot-airoha=...` 行），配合 an7581.mk 的
   `an7581-chainloader` 在 image 阶段产出 `chainload-uboot.itb`；CI 在校验步骤对这
   一变体做存在性检查（缺失仅告警）。
4. **WiFi（mt76/mt7996/NPU）**：本骨架刻意最小化（`kmod-mt76` 未开），保证 CI/前端
   构建跑得快且稳。M2+ 全量能力配置需开启 `kmod-mt7996`（及 NPU 固件
   `airoha-en7581-npu-firmware`，骨架已默认带 `CONFIG_DEFAULT_airoha-en7581-npu-firmware=y`）。

## 本机（探路机）限制下未达成的目标

- 未产出 `gemtek_xr1710g-ubi` 实体镜像（san无该 profile；需 PR 合入或分叉应用补丁）。
  **CI 已把这条路径自动化**：种子自举（本快照为种子 + 器件符号整行对变换 +
  defconfig）当场生成 xr1710g config 并构建，不依赖手工改写本文件。
- 未完成全量包集构建与 image 阶段（见 `docs/research/06-build-recon.md`：磁盘/时间墙）。
- 未验证 chainloader 镜像可刷（需真机，属人类最小集）。

## config 快照的 CI 用法（种子法，2026-08 修订）

- 本文件 = 分叉内唯一 config 权威种子（w1700k，target 块完整一致）；
- **xr1710g 档 config 不由仓库提供**，由 `.github/workflows/build.yml` 现场生成
  （`cp` 本快照 → 器件符号 w1700k→xr1710g 整行对变换 → `make defconfig` → 校验
  `DEVICE_gemtek_xr1710g-ubi=y`），生成结果随固件产物上传归档（含 config.buildinfo）；
- PR #22397 合入前，w1700k 档为占位（main 原生 profile，管线绿灯 canary）。

## 应用方式（其他机器 / CI）

```bash
cp an7581-gemtek-w1700k.config /path/to/openwrt/.config
cd /path/to/openwrt
make defconfig        # 归一化并校验
make -j$(nproc)       # 或用小核数避免内存峰值
```

> 复现前提：OpenWrt main 快照与生成日一致（`git log -1` 为
> `ee6ef8d27e realtek: pcs: discover SerDes MDIO bus via phandle`，2026-08-16）。
> 上游滚动后 config 可能因新 package 出现警告（`WARNING: ... dependency does not
> exist`），defconfig 会自行清理，不影响骨架语义。
# build/ · 分叉构建（探路实测版）

> 本目录是 XR1710G OpenWrt 分叉的构建侧。本 README 依据 2026-08-16 极限小实验
> （详见 `docs/research/06-build-recon.md`）的**实测数据**撰写。

## 1. 构建前置要求（实测结论）

探路机实测（Proxmox VM，Debian 12，无 root）：**8 核 / 8GiB RAM / swap 8GiB / 磁盘
16G→30G（构建中途扩容）**；任务简报声称的"2 核/1G/12G"与实测不符，本结论一律按实测。

| 项 | 实测数据 | 结论 |
|---|---|---|
| 内存 | 交叉编译峰值 used ≈2.5GiB（GCC 单进程常吃 1–2G）；swap 峰值 215MiB | **≥4GiB RAM** 起步；1GiB 必然 OOM/颠簸 |
| 磁盘 | 构建中途实测占用：build_dir 9.5G + staging 723M + dl 645M + 源码 .git 143M + 杂项 ≈ **15G/16G 时 100% 占满死机**；扩容 30G 后才有余量续跑 | **单 subtarget 全量 ≥20GiB（推荐 30–40G）**；16G 盘必死（已实测踩穿） |
| CPU | 8 核下 -j2 全程无压力；时间才是墙 | ≥4 核即可，核多提速 |
| 时间 | 工具链 ~1h（第一次探路 25min 到 GCC 主编译期）；world 全量按 -j2 估算 **≥4–6h** | CI/专用机才有意义 |
| 宿主依赖 | 精简 VM 缺 gawk/rsync/unzip/ncurses/distutils；无 root 用本地前缀 `/home/harness/owrt-deps`（19M）补齐 | 正常机器（或 CI runner）一条 apt 命令装齐"OpenWrt 文档标准依赖"即可 |

**一句话**：M1 基线构建需要 **≥4GiB RAM + ≥30GiB 磁盘 + ≥4 核（或 CI runner）**，
本探路机在磁盘扩容后具备续跑条件，但 35 分钟时间盒不足以跑完全量（见 06 报告续跑段）。

**CI 标准 runner 口径**（本 README 修订版）：M1 构建**主路径 = GitHub Actions CI**
（`.github/workflows/build.yml`，见 §3.4）。`ubuntu-24.04` 标准 runner = **4 vCPU /
16G RAM / 14G SSD**；全新构建约 **1.5–2.5h**，dl + 工具链缓存命中约 **1–1.5h**。
`docs/research/06-build-recon.md` 早期"16 核 / 40–70min"为**过时口径**（旧型 runner
假设、且未计入全量 world 与 image 阶段），排期勿以之为据。本机/探路机仅作**对照验证**
（无 root、缺宿主依赖的场景复现），不再承担主交付。

## 2. 补丁两层目录约定（对照 CONTEXT.md）

分叉内自研改动分两层，目录按**前缀命名**，一个补丁主题一个子目录：

```
build/patches/
├── adapt-*/            # 【设备适配层】让这台机器跑起来的最小必要改动；能上提 PR 就上提
│   ├── adapt-pr22397/  #  (现仓库内载体: build/patches/device-layer/ —— PR #22397 完整快照)
│   │   ├── pr22397.diff                    # 完整 diff（权威来源）
│   │   ├── README.md                       # 应用方式/归档约定
│   │   └── package/ target/                # 按原仓库相对路径拆分的文件/补丁
│   └── ...
└── tune-*/             # 【激进调优层】越过上游边界的自研魔改；本地维护、永不主动上提
    ├── tune-npu-ppe/   #  NPU/PPE 卸载调优（2026-08 起规划，未开工）
    ├── tune-6g-mesh/   #  6GHz 802.11s 回程参数（M3 旗舰，未开工）
    └── ...
```

**各放什么**：
- **adapt-***（设备适配层）：XR1710G dts、RTL8261BE（kmod-phy-rtl8261n + reset 时序）、
  LED、chainloader（uboot-airoha 目标 + 引导链）、target recipe/Makefile 登记、
  base-files 板名分支。归宿 = 上提 PR（本层全部内容就是 PR #22397 本体；PR 合入主
  线则本层归零，退化为追踪占位）。
- **tune-***（激进调优层）：NPU/PPE 卸载调优、6GHz 802.11s 回程参数、运营商功能裁剪、
  任何与上游相撞的自研魔改。判别口诀：**能上提 PR 的进 adapt-；只能本地维护的进 tune-**。
- **应用顺序固定**：先 adapt-*（如 `git apply --check` 通过后 `git apply`），后 tune-*；
  冲突时先修 adapt-*。分叉"每日自动合入上游"（完全自主分支）的冲突面主要落在 adapt-*。

## 3. 如何在本仓库基础上续跑（其他机器 / CI）

### 3.1 前置

```bash
# 官方依赖（Debian/Ubuntu 示例；CI runner 同款，见 .github/workflows/build.yml）
sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib \
  gettext git libncurses5-dev libssl-dev python3 python3-dev python3-setuptools \
  rsync swig unzip zlib1g-dev
# F9：Python ≥3.12 已移除 distutils；OpenWrt 预检/uboot-airoha 认 setuptools 提供的
# distutils shim → 必须装 python3-setuptools（旧文档的 python3-distutils 仅存于 ≤3.11 系发行版）
# 另含 python3-dev/swig：当前 main 的 uboot-airoha（UBOOT_USE_INTREE_DTC）有对应宿主预检。
git clone --depth=1 --filter=blob:none https://git.openwrt.org/openwrt/openwrt.git openwrt-src
cd openwrt-src
./scripts/feeds update -a && ./scripts/feeds install -a
```

### 3.2 应用适配层（当前 main 未含 XR1710G）

```bash
git apply --check build/patches/device-layer/pr22397.diff   # 来自 /home/harness/workspace/xr1710g 仓库
git apply build/patches/device-layer/pr22397.diff
# 预期与 2026-03 之后的 main 有冲突 → 以设备层内新文件全文手工合并（README 有清单）
make defconfig   # 之后 .config 出现 DEVICE_gemtek_xr1710g-ubi
```

> **CI 已内置双路径**（`.github/workflows/build.yml`，实测 2026-08 的 main 上整 diff
> 必冲突）：先 `git apply --check pr22397.diff`，失败 → 新文件整文件覆盖 + per-file
> 补丁逐个应用，冲突产物归档 `conflict-archive/`、job **失败不静默**。本机上面的
> 手工合并步骤只用于对照/调试，不作为主路径。
> **xr1710g 档 config 由 CI 现场种子自举生成**（w1700k 快照为种子 → 器件符号整行
> 对变换 → `make defconfig`，见 `configs/README.md`），仓库不提交 xr1710g config 文件。

### 3.3 配置与构建

```bash
cp build/configs/an7581-gemtek-w1700k.config openwrt-src/.config   # 或切到 xr1710g-ubi 后重新 defconfig
make defconfig
make -j$(nproc)      # 小内存机用 -j2 并配 swap
```

产物：`bin/targets/airoha/an7581/`（sysupgrade.itb / initramfs-recovery.itb /
chainload-uboot.itb）。GPL 合规：本 build/ 全部（configs、patches、scripts）随分叉公开。

### 3.4 CI（M1 主路径，已落地 `.github/workflows/build.yml`）

- runner：`ubuntu-24.04` 标准规格 **4 vCPU / 16G RAM / 14G SSD**；全新构建约
  **1.5–2.5h**、dl+工具链缓存命中约 **1–1.5h**（06 报告早期"16 核 / 40–70min"为
  过时口径）。`timeout-minutes: 240`。
- workflow 职责：装依赖（F3/F4/F9，含 python3-setuptools）→ clone main
  （blob:none，F1/F2）→ feeds → 应用 device-layer（**双路径**，冲突归档不静默）
  → 快照/种子 defconfig（F7：严禁 sed 改 choice）→ `make -j` → 上传 artifact。
  上游（PR #22397 / upstream main）有动静即触发（每 6h 轮询）+ 每夜 03:30 保底。
- 缓存：dl / 工具链按 `cache-<branch>-` 前缀分 target 分档，每夜档即 7 天生存线；
  `build_dir/target` 默认不缓存（14G 盘必爆），手动开启且大 runner 时可用。
- 探路踩过的坑（06 报告 §4 F1–F9）在 CI 上多数不存在（有 root、标准依赖），但
  **补丁冲突面（device-layer × 演进 main）仍在**——由双路径自动处理，处理不了就
  归档 + 失败，交"完全自主分支"冲突流程（ADR-0001）消解，绝不静默产出错镜像。

## 4. 探路机可续跑点（2026-08-16 状态）

- 克隆：`/home/harness/workspace/openwrt-src`（main @ ee6ef8d27e，.git 143M，blob:none）
- 工具链：**已完成**（`staging_dir/toolchain-aarch64_cortex-a53_gcc-14.4.0_musl`）
- defconfig：**已完成**（aiotoha/an7581 + w1700k profile，详见 configs/）
- world 编译：上次死于磁盘满（16G 盘），磁盘扩容 30G 后已续跑（结果见 06 报告）
- 续跑命令：`cd openwrt-src && make -j2`（含 owrt-deps 环境注入，见 06 报告 §3）
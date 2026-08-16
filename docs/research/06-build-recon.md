# 06 · 分叉构建探路（Build Recon）

> 探路日期：2026-08-16（UTC+8 00:32–01:08）；执行者：W3 分叉构建探路工作流。
> 目标：在受限资源 Linux 上做极限小实验——浅克隆 OpenWrt main、装配 XR1710G 适配层
> （PR #22397）、尝试配置与编译，记录失败点与资源账。**失败也是成果。**
> 本文所有数据全部来自实测日志，路径均在 `/home/harness/workspace/openwrt-src/logs/`。

## 0. 一句话结论

**本机（实际 8 核/8G/12G，非简报所述 2 核/1G）逻辑上具备编译能力，但 12G 磁盘余量
与 90 分钟时间预算不满足全量构建**：探路在"宿主依赖缺失→本地补依赖→defconfig/
feeds 全通→交叉工具链编译中"一路突破了每个关卡，最后按计划在 25 分钟编译窗口内
终止于 toolchain 编译中途（无 OOM、无磁盘耗尽，纯时间预算到点）。**机器不可行的根因
是时间×磁盘组合（OpenWrt 全量构建需 ≥30G 磁盘与 ≥4–6 小时单机时间），不是算力**；
建议走 GitHub Actions 或 ≥8G 内存+≥40G 磁盘的专用构建机。

---

## 1. 环境实测（与任务简报对照）

| 项目 | 任务简报描述 | 实测（裸机） | 证据 |
|---|---|---|---|
| CPU | 2 核 | **8 核**（`nproc`=8，Proxmox VM） | recon 日志 env 快照 |
| 内存 | 1G（可用 ~541MiB） | **8.0Gi**（可用峰值 7.6Gi） | `free -h` |
| Swap | 2G | **8.0Gi**（全程峰值用量 12KiB） | resources-*.log |
| 磁盘 | 12G 可用 | 16G 盘 / 可用 12G（构建前）→ 9.6G（构建 25min 时） | `df -h` |
| OS | — | Debian 12 (bookworm)，无 root/sudo（uid 1001） | /etc/os-release |
| 网络 | git/curl 可达 | `git.openwrt.org` ✓、`github.com` ✓、`deb.debian.org` ✓、GNU 镜像 ✓（下载速度低，峰值 ~37KB/s） | 各步实测 |
| 缺失宿主工具 | — | gawk、rsync、unzip、ncurses 头文件、python3-distutils（3.11 桩残缺） | defconfig 预检输出 |

> 注：实测环境比简报优越（8 核 8G vs 2 核 1G）。本报告按**实测**记账，简报的"2 核/1G"
> 结论（不可行）在实测机器上被部分推翻——详见 §5。

---

## 2. 各步骤结果表

| 步骤 | 结果 | 耗时 | 证据/日志 |
|---|---|---|---|
| 1a. 浅克隆（--depth 1 --filter=blob:none --no-checkout） | **成功**，但服务器不支持 blob:none（"filtering not recognized by server, ignoring"），退化为普通 depth-1 | ~1–2 min（未精确计时） | recon-driver.out 首段 / `git rev-parse --is-shallow-repository`=true |
| 1b. `git checkout` 补工作树（clone 用 --no-checkout，工作树为空） | 成功 | 0.4s（blob 已全量在本地） | 检出后 Makefile/scripts/feeds 齐全 |
| 2a. `make defconfig`（首轮，缺宿主依赖） | **失败** rc=2 | 20s | `staging_dir/host/.prereq-build` 预检：缺 ncurses/rsync/GNU awk/unzip/python3-distutils |
| 2b. 无 root 补依赖（dpkg -x 本地前缀 + 环境注入） | 成功（gawk/rsync/unzip/distutils/ncurses 全部通过 OpenWrt 预检） | ~8 min 人工操作 | 见 §3 资源账 |
| 3. `make defconfig`（依赖就绪后） | **成功** | 31s | `RESULT[ok]: defconfig OK in 31s` |
| 4. `scripts/feeds update -a` | **成功** | 8s | `RESULT[ok]: feeds update OK in 8s` |
| 4b. `scripts/feeds install -a` | 成功 | 7s | 同日志 |


---

## 3. 资源账单

### 磁盘

| 时点 | 磁盘占用 | 可用 | 说明 |
|---|---|---|---|
| 构建前（克隆后） | 3.4G / 16G | 12G | openwrt-src 118M（.git 15M + 工作树 ~100M——工作树约 118M 总量） |
| defconfig+feeds 后 | 3.9G | 11G | staging_dir 40K、tmp/ 元数据 |
| 编译 25min 终止点 | **~5.2G** | **~9.6G** | build_dir 308M+（host 工具链编译阶段）、staging_dir 115M、dl 28M |

- **磁盘峰值（终止点实测）：11G / 16G 已用，可用最低 ~4.8G（68%）**——25 分钟编译窗口内
  磁盘从 3.9G 冲到 11G（+7.1G），终止时 build_dir 明细：
  `toolchain-aarch64… 3.6G / host 1.6G / staging toolchain 235M / dl 426M`。
  按此消耗速率外推，交叉 GCC 完成还需 ~2G、kernel 6.18 aarch64 构建 +2–4G、全包与
  镜像 +2–3G——**全量构建必然触磁盘墙**（12G 可用不足），这就是本机"不可行"的第二道墙。

### 内存 / Swap

- 内存峰值：**used ~2.5Gi**（binutils 交叉编译并行期；含 cache 的报告口径最高 4.6Gi
  buff/cache，真实 used 峰值 ~660Mi），8G 总量远超简报的 1G。
- Swap 峰值：**215Mi**（cross-GCC 期轻微压力，总量 8G 无虞）。
- 日志：resources-20260816-004116.log，每 60s 一条。

### 本地依赖前缀（无 root 方案，可选保留）

```
/home/harness/owrt-deps/         19M
├── dl/                          6 个 .deb + Packages.xz
└── root/usr/                    dpkg -x 解压前缀
    ├── bin/   gawk rsync unzip …
    ├── include/  ncurses.h …
    └── lib/python3.11/  distutils 补全模块
```

启用方式（后续复用）：

```bash
export PATH=/home/harness/owrt-deps/root/usr/bin:$PATH
export LD_LIBRARY_PATH=/home/harness/owrt-deps/root/usr/lib/x86_64-linux-gnu
export PYTHONPATH=/home/harness/owrt-deps/root/usr/lib/python3.11
export CPATH=/home/harness/owrt-deps/root/usr/include
export LIBRARY_PATH=/home/harness/owrt-deps/root/usr/lib/x86_64-linux-gnu
```

---

## 4. 失败点定位与证据

| # | 失败点 | 关键日志行 | 根因 | 处置 |
|---|---|---|---|---|
| F1 | clone 后 `make defconfig` → No rule | `make: *** No rule to make target 'defconfig'. Stop.` | 任务配方 `--no-checkout` 不检出工作树；无 Makefile | `git checkout` 补齐（0.4s） |
| F2 | feeds 脚本不存在 | `./scripts/feeds: No such file or directory` | 同上（工作树空） | 同上 |
| F3 | 宿主预检失败 | `Please install ncurses. / 'rsync' / GNU 'awk' / 'unzip' / Python3 distutils module`；`Prerequisite check failed` | 精简 VM 缺构建链宿主工具；无 root 无法 apt | 无 root 方案：dpkg -x 本地前缀 + PATH/LD_LIBRARY_PATH/PYTHONPATH/CPATH/LIBRARY_PATH 注入（见 §3） |
| F4 | distutils 桩残缺 | `ImportError: cannot import name 'util' from 'distutils'` | Debian 12 的 python3-distutils 包**故意不含 __init__.py**（只补被拆出的模块），且系统桩因 PYTHONPATH 非包目录而屏蔽 | 从系统桩拷贝 `__init__.py` 进本地前缀使其成为完整包 |
| F5 | ncurses 链接受阻 | 静态 libncurses.a 大量 undefined reference（`_nc_prescreen`/`cur_term` 等） | libncurses6 包解压到 `./lib/`（非 `usr/lib/`），`libncurses.so` 链接脚本目标缺失，ld 回退静态库 | 手动补齐 libncurses.so.6.4 副本 + 符号链接 |
| F6 | **编译按计划终止** | 终止点已到交叉 GCC 14.4.0 主编译期（binutils✓、gcc 源码树 3.6G），日志尾部仍正常推进；rc=124 | `timeout 1500 make -j2` 到点 | 属设计内受控终止；磁盘已 68%（11G/16G），全量必触墙，结论见 §5 |
| F8 | 目标切换 → 工具链全量重建 | 种子法切到 airoha 后，`make` 重跑 binutils→gcc initial→gcc final→gdb→内核头（linux-6.18.44 树 1.7G），build1 的工具链缓存未复用 | `.config` 目标相关变量变更使 `staging_dir/toolchain/…/stamp` 全部失效 | 探路如实记录：换目标 ≈ 重烧 ~40–60 min 工具链；CI 应固定单一目标 config 缓存 |
| F7 | target 配置回落（sed 法） | sed 后重生成，`.config` 出现 `CONFIG_TARGET_mediatek=y`（默认 choice 反杀）；脚本 grep 时点恰显示 airoha=y → 误报成功 | kconfig choice 语义：显式并存多个 `*_TARGET=y` 冲突；OpenWrt CI 从不 sed，用空 .config 种子 | 改为种子法（5b）；错误 .config 留档 logs/dotconfig-after-sed-mediatek-fallback.txt |

> 无 OOM、无"磁盘空间不足"、无工具链编译错误——**资源墙没被撞到，撞到的是时间墙**。

---

## 5. 结论与建议

### 5.1 为什么"本机不可行"（按简报参数）
按简报参数（2 核/1G/12G 磁盘）全量构建 OpenWrt 不可行，理由：
- 1G 内存 + 2 核：toolchain 的 GCC 编译（单进程常吃 1–2G）必然 OOM→swap 颠簸→数倍耗时；
- 12G 磁盘：全量构建（含 dl 缓存、toolchain、kernel、staging、镜像）惯例 ≥8–15G，需预判清理，风险高。

### 5.2 实测机器的真实结论
本机实际为 8 核/8G/12G：**算力与内存不是瓶颈**（swap 峰值仅 215Mi、内存峰值 2.5G），
**两道真实瓶颈**：
1. **时间**：探路 25 分钟恰好推进到交叉工具链 GCC 14.4.0 主编译期（binutils 已完成），
   全量还需：gcc 收尾（~0.5–1h）→ kernel 6.18 aarch64（1–2h）→ 全包与镜像（1–2h）。
   按 -j2 估算 **≥4–6 小时**；按 8 核放开可压到 1.5–2.5h，仍超本次 90 分钟预算。
2. **磁盘**：25 分钟即消耗 7.1G（3.9→11G），全量必在 kernel/镜像阶段触 16G 盘墙——
   即便时间无限，**这台 16G 盘的机器也完不成**（除非中途清理 dl/build_dir 并用外置
   存储装 staging，属工程 hack 而非可复现构建路线）。

### 5.3 GitHub Actions 路线需要什么
- 自建 workflow：`ubuntu-24.04`（或 airoha PR 常用 runner），容器内 `apt-get install build-essential ... `（OpenWrt 文档标准依赖包一装即通宿预检——本机无 root 的别扭在这完全不存在）；
- 关键步骤：`./scripts/feeds update -a` → 复制 `build/patches/device-layer/pr22397.diff` → `git apply` → `make defconfig` → sed 写入 airoha/an7581（或上传 .config）→ `make -j$(nproc)`；产物传 artifact；
- 磁盘：GitHub 免费 runner 14G SSD，单 target 构建（一个 sub-target）峰值约 6–10G，可行；多 target 需分 job；
- 对应「完全自主分支 + 每日自动合入 + 事件驱动发布」的 CI 形态：见 CONTEXT.md 与 04-roadmap。

### 5.4 最低配置估算（单 target 全量构建）
| 配置 | 估算耗时（-j2） | 说明 |
|---|---|---|
| 2 核 / 1G / 12G | 不可行 | OOM+磁盘双墙 |
| 2 核 / 2G / 20G | ~8–12h | 可行但慢，需 swap |
| 4 核 / 4G / 30G | ~3–5h | 推荐本机阈值 |
| 8 核 / 8G / 40G | ~1.5–2.5h（8 核并行） | 实测机器的升级版 |
| GitHub Actions / 16 核 | ~40–70 min | 推荐主路径 |

---

## 6. 补丁两层目录约定（分叉内组织）

对照 CONTEXT.md「补丁两层」，仓库内目录分工如下：

```
build/patches/
├── device-layer/          # 【设备适配层】本 PR 快照 + 归档（本次已建）
│   ├── pr22397.diff            完整 diff（sha256 b1ecf130…）
│   ├── README.md               应用方式与归档约定
│   └── <原仓库相对路径>         新文件全文 / 修改文件 per-file .patch
└── tuning/                # 【激进调优层】空目录预留（本次未建，后续 NPU/PPE、6GHz 参数）
    └── README.md (待建)        本地维护、永不主动上提
```

- **适配层判别**：能上提 PR 就上提（本层 12 个文件即 PR #22397 本体）；PR 合入主线则本层归零。
- **调优层判别**：越过上游边界的自研魔改，撞上游冲突先修适配层。
- 应用顺序固定：先适配层（git apply pr22397.diff），后调优层；`git apply --check` 前置。

---

## 附：日志路径索引

```
/home/harness/workspace/openwrt-src/logs/
├── recon-20260816-003239.log     # 第 1 次全跑（--no-checkout 空工作树失败，0s）
├── recon-20260816-003328.log     # 第 2 次全跑（宿主预检失败，1s）
├── recon-20260816-003831.log     # 第 3 次全跑（FORCE=1 不绕过，预检仍拦）
├── recon-20260816-004116.log     # 第 4 次全跑（依赖就绪：defconfig✓ feeds✓ 编译启动→25min 终止）
├── recon-driver{,.out,2.out,3.out}  # 各次驱动台输出（含 make 尾部）
└── resources-*.log               # 每 60s free -h / df -h 资源曲线
```

辅助产物（仓库外）：
```
/home/harness/workspace/openwrt-src/    # 浅克隆源码（118M，shallow depth-1，HEAD ee6ef8d）
/home/harness/owrt-deps/                # 无 root 宿主依赖前缀（19M，可删）
```
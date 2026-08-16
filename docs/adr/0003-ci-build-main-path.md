# ADR-0003: CI 构建为「基线可刷」(M1) 的主路径，xr1710g config 由 CI 现场生成

**Status**: accepted

**2026-08-16**。上下文：M1 主目标「基线可刷」需要产出 XR1710G 专属镜像三件套（sysupgrade / initramfs-recovery / chainload-uboot .itb）。探索结果（06 号报告 + 本日复核）表明：本机（8 核/8G/30G）续跑被宿主依赖墙 **F9**（u-boot prereq 缺 `python3-setuptools`，无 sudo）阻断，且存在时间墙（-j2 ≈ 2.5–4.5h）+ 磁盘墙（峰值估 20–22G/30G）+「单机一次快照不可复现、不满足可复现构建/GPL」三问题；06 报告「16 核/40–70min」口径已过时（GitHub 标准 runner = 4 vCPU/16G/14G，全新构建约 1.5–2.5h、缓存命中约 1–1.5h）。

**决定**：以 **GitHub Actions CI 为「基线可刷」构建主路径**，落地 `.github/workflows/build.yml`：

- **触发**：`push`（build/**）+ 每夜保底 cron（03:30 UTC，兼缓存生存线：条目 7 天不访问即淘汰）+ 每 6h 轮询 PR #22397 / upstream main HEAD（合并或前移即触发）+ `workflow_dispatch`。
- **矩阵**：`airoha/an7581 × {gemtek_w1700k-ubi（PR 合入前占位，main 原生 canary）, gemtek_xr1710g-ubi（种子自举档）}`。
- **xr1710g config 由 CI 现场生成**（种子自举）：以仓库 w1700k 配置快照为种子 → 器件符号整行对变换 → `make defconfig` → 断言 profile 与 target 生效。仓库**不维护** xr1710g config 静态快照，避免与上游翻新脱节。
- **缓存**：dl/ 与工具链两组 `actions/cache@v4`（工具链 key 用 stamp 内容 sha256 指纹自动换代），build_dir/target 默认不缓存（标准 runner 14G 起点即爆），仅在显式开关+更大 runner 时启用。
- **补丁应用双路径**（device-layer 对演进中的 main 冲突面已实测存在）：先 `git apply --check pr22397.diff`，干净则整体应用；冲突则新文件覆盖 + per-file 补丁逐个应用，冲突产物归档 `conflict-archive/`、job 失败不静默。
- **产物**：三件套 `.itb`（按类别通配，兼容 main 命名演化）+ sha256sums + config/feeds/version.buildinfo（GPL/可复现归档）+ 现场导出 config，上传 artifact。CI 只证明「构建成功 + sha256 可下载」；真机「可刷」验证仍归人类最小集。

**Considered Options**：
- (a) 本机续跑（补 setuptools 后 -j4）——F9 墙 + 时间不可再生 + 单机快照不可复现，且「基线可刷」交付口径要求可复现，否决；本机降级为「CI 就绪前的对照验证」。
- (b) 专用构建机（≥4 核/≥40G）——成本与运维，无即时效用，本轮不选；若 CI 不满足（如 build_dir 缓存需求）再评估。
- (c) 仅保持现状（纯文档/探路结论）——与 ADR-0001「事件驱动发布」冲突（无构建即无镜像可发），否决。
- CI 标准 runner 方案（采纳）结构性消除 F1–F5/F7/F9 探路失败点，且事件驱动 + 每夜保底与 ADR-0001 发布节奏天然一致。

**Consequences**：
- **xr1710g 档在冲突消解前按设计必红**：现网 main 上 5/9 个 per-file 补丁冲突（an7581.mk / uboot-airoha Makefile 等），CI 双路径 + 失败不静默会如实标红并归档冲突产物；消解路径 = PR #22397 合入（最优先）、或按 ADR-0001 冲突流程人工/AI 消解后 re-roll 补丁。w1700k 占位档为绿灯 canary，管线健康可观测。
- PR #22397 合入后：xr1710g 档自动转绿（补丁无冲突），config 自举生成，镜像三件套进 artifact。
- 工具链缓存指纹在全新 GitHub runner 上恒为空 sha（stamp 只在残留工具链时换代），靠 restore-keys 降级保证命中；自托管 runner 才充分体现指纹换代价值——已知且可接受。
- 首个全量 world 构建耗时未实跑验证（240min 按 2.5h+余量设计），待真 runner 首跑校准。
- 发布闭环（自动建 Release）本 ADR 不覆盖，gh CLI 凭证与 `contents: write` 权限就绪后另行扩展（Q9 已确认本轮到「CI 构建 + 发布流程文档化就绪」）。

---

## 2026-08-17 修订（alpha 战役 D0，经用户确认）

**变更 1 · 不等 PR，主动消解常态化**：撤销"消解路径 = PR #22397 合入（最优先）"的等待
策略。补丁双路径之后新增**第三步 roll 路径**：CI 冲突（an7581.mk COMPAT_VERSION 2.0 /
uboot-airoha PKG_VERSION 等演化面）→ 双路径失败即触发 AI 主动 re-roll 对齐现网 main，
**9 修 0 舍**；PR 合入只当 bonus，消解产物可反哺 PR #22397（已有 APPROVED 评审）。

**变更 2 · 每夜保底语义扩展**：从"缓存生存线"扩展为"**每晚镜像供给源**"——alpha 期
每夜档产出可刷镜像 + 冒烟校验，人工放行后即可刷入。

**变更 3 · 回归耦合（新增）**：CI 产物 sha256 与真机自动回归循环耦合——D7 起每版镜像
自动进入真机回归（刷写-冒烟-指标回填-报告），回归通过率进入发布门槛；详见
`docs/plan/alpha-campaign.md`。
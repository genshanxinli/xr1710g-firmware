# XR1710G · Alpha 冲刺作战 kanban（进度权威源）

> **本文档是 alpha 战役的跨会话进度权威源。任何新会话开工前先读本文件**，从看板中
> 最小的未完成 D 项继续；每完成一步立即更新看板状态与「会话记录」。
> 决策语义以 CONTEXT.md 术语表与 docs/adr/ 为准；本文档承载战役级排期与事实基线。
> 创建：2026-08-17（D0，本会话）。

## 0. 战役目标与验收

- **目标**：自建分叉上两周内交付 **v0.1 私人 alpha**——基线可刷 + 真机自动回归迭代；
  P0/P1 bug 清零后锁稳定基线，之后恢复上游自动跟随。
- **验收（D14）**：xr1710g CI 档绿 → 首版镜像三件套（含社区独有的 chainload-uboot.itb）
  → 人工首刷放行 → 每日真机回归跑通 → v0.1 锁基线（P0/P1=0）→ 恢复上游跟随 → alpha 交付。
- **Bug 分级**：P0/P1（起不来/变砖/断流/无线不工作）必须清零才锁 v0.1；
  P2/P3（边缘功能/性能次优/体验）转 known-issues 清单留档排队，不算「未清零」。

## 1. 设计决策锚点（2026-08-17 经用户逐项确认，勿单方面更改）

| # | 决策 | 定案 |
|---|---|---|
| 集成 | Q4-A | **激进集成 = 加速不扩界**：压缩路线时间；ADR-0002「设备能力全集」边界不动；优先级（前沿跟踪 > 功能集成 > 激进改造）不动 |
| PR 策略 | Q5-A | **主动消解** device-layer 对齐现网 main（9 修 0 舍）；PR #22397（open + APPROVED）合入只当 bonus，消解产物可反哺 PR |
| 刷机自动化 | Q6/Q11/Q18 | AI 经 SSH sysupgrade 刷机，**永不碰 bootloader 槽**（一机一路线）；**首刷人工放行**；失败兜底 = 人按 reset → YYH http-uboot 恢复页 |
| 回归范围 | Q12/Q20 | 冒烟 + NPU 指标 v0 自动回填 + 条件专项（首波按测试条件选） |
| 稳定锚 | Q13/Q19 | 滚动锚：alpha 期逐 bug 锁 commit；**v0.1 = P0/P1 清零锚点**；之后恢复上游自动合入 |
| CI 节奏 | Q14 | 稳定期内每夜保底照跑（缓存生存线 + 每晚镜像），「上游 main 前进」触发挂起；v0.1 后恢复「上游有更新才自动合入+发布」 |
| 过渡期 | Q16 | 自建首版镜像前，AI 对测试机**只读采集**（只跑采集管线，不刷机） |
| 真机分工 | Q17-C | 一台 alpha 主力（可测）+ 一台封存（救砖素材）→ **无对照机**，bug 归因用「社区基线参照」 |
| 发布 | Q8-A/Q15 | 私人 alpha（两周）；对外发布顺延到 v0.1；文档侧按 Q15-B 全套修订 |
| 接入 | Q18 | SSH root@192.168.123.1 密码登录（askpass 注入）；**密钥认证待用户装公钥**（collect.sh BatchMode 必需） |

## 2. 真机事实基线（2026-08-17 D0 实测，全部只读命令）

- **设备**：XR1710G；board_name `econet,xr1710g-ubi`；2GB DDR4 / 512MB NAND；无 USB/WPS
- **固件**：OpenWrt SNAPSHOT **r2177-f5fafce4c7 · 内核 6.18.41**（构建 2026-08-05）；
  target `airoha/an7581`；**无 distfeeds/customfeeds 配置**（此线禁用更新）——判定 YYH2913 系构建
- **网络**：br-lan `192.168.123.1/24`；**wan PPPoE 在线 `172.26.13.45`**（PPPoE 凭据见访问笔记，
  **不入库**）；开发机 `192.168.123.200` 同 LAN 直连
- **无线**：单 phy0（PCIe `0000:01:00.0` MT7996E）承载三 band；radio0=2g EHT20 ch1、
  radio1=5g 160MHz ch36 启用；**radio2=6g `disabled=1`**；SSID「K2P」
- **NPU**：fw **0.1111** 在册（airoha-npu 与 mt7996e 双加载日志）；`/proc/iomem` npu 保留区
  （npu-txpkt 64MiB / npu-ba 2MiB）在场；**debugfs `/sys/kernel/debug/{airoha,flow}` 不存在**
  → 本线固件无 NPU 流表/计数可观测性（我们固件的改进点，对照「NPU 全功能」词条）
- **6GHz（2026-08-17 补充）**：phy0 只枚举 2.4/5GHz 信道；**6GHz 频段未枚举**（radio2
  disabled 已知态；iw 仅 EHT 能力文本到 7200MHz）→「6GHz EHT320 冒烟」专项在自建镜像中
  是"enable radio2 后验证信道枚举"的真任务，本线固件无法验证
- **系统**：mem 1.87G 总 / 1.63G 可用、swap 0；overlay 353.9M（用 60K）；load 0.09；无 OOM/panic 痕迹
- **接入**：SSH `root@192.168.123.1`；本环境经 `~/.ssh/xr1710g-askpass.sh` +
  `~/.local/bin/xr1710g-ssh`（SSH_ASKPASS_REQUIRE=force 非交互密码登录）；
  本机无 sudo/pip/sshpass/expect/paramiko
- **回归管线前置**（collect.sh 要求，D5 前需解锁）：路由器缺 **bash**（opkg 装）+ **密钥认证**

## 3. 上游与社区事实（2026-08-17 子代理网络调研）

- **PR #22397**（openwrt/openwrt「airoha: add support for Gemtek XR1710G」）：**open 非 draft**，
  08-03 `peterwillcn` APPROVED，08-14 最后活动；当前仍未合入。
  https://github.com/openwrt/openwrt/pull/22397
- **OpenWrt main**：内核 **6.18.44** + hostapd 2.12；airoha 默认内核 6.18（06-04 起）；
  w1700k 已进 main（PR #17869，2026-03-10）；**main 无 gemtek_xr1710g**。
- **社区三条线均有现成可刷镜像**：orangeyoo v1.2.0-pre（6.18.41 + YYH uboot 配套）、
  naoki66 20260815（6.18.41）、hx801217 istoreos 24.10（6.6.141，econet 命名）；
  社区 **6GHz 802.11s 「稳定」claim 锚在 6.18.41**（论坛实测 ESTAB）；
  **社区均未发布 chainload-uboot.itb**（我们 CI 三件套中此件为独有交付）。
- 来源：pr22397 / openwrt 仓库 an7581.mk 历史 / orangeyoo、naoki66、hx801217 仓库 Release / 论坛帖 252504 / 恩山 8484444

## 4. 看板（列：🚧 进行中 · ⏳ 待办/待人工 · ✅ 完成）

| ID | 项 | Owner | 验收 | 依赖 | 状态 |
|---|---|---|---|---|---|
| D0-1 | SSH 接入验证（192.168.123.1:22 + 密码登录） | AI | AUTHPASS_OK | — | ✅ 2026-08-17 |
| D0-2 | 只读基线采集（版本/接口/无线/NPU/mem） | AI | §2 全项 | D0-1 | ✅ 2026-08-17 |
| D0-3 | 文档修订（ADR-0001/0003 + CONTEXT.md + 本 kanban + README 索引） | AI | 各修订落盘 | — | ✅ 2026-08-17 |
| D0-4 | **公钥装进路由器**（authorized_keys） | 人工 | `ssh -i key` 免密 | — | ⏳ 待人工（用户） |
| D0-5 | 测试机装 bash（opkg） | AI+人工 | `command -v bash` | D0-4（密钥） | ⏳ D0-4 后 |
| D1 | **消解启动**：device-layer re-roll 对齐现网 main（v2 补丁集，10 文件） | AI | 冲突清单清零 | D0-3 | ✅ 2026-08-17（v2 全绿 + defconfig 三断言） |
| D2 | CI xr1710g 档转绿（w1700k 占位档绿灯对照） | AI | Actions 绿 | D1 | 🚧 **RUNNING**（run 31964412187，18:22 起；⚠️ 前两 run 均被本仓推送取消——教训见关联待办，修复已生效） |
| D3 | 首版镜像三件套（sysupgrade/initramfs-recovery/chainload-uboot） | AI | artifact 齐全 | D2 | ⏳ 工具就绪：tools/ci/fetch-artifacts.sh（凭据 PAT 已验证可下载） |
| D4 | 产物自检 + sha256 归档（对照双路径冲突面复核） | AI | 清单 | D3 | ⏳ 工具就绪：tools/ci/check-artifacts.sh（逻辑实测 PASS） |
| D5 | 真机回归管线：冒烟 + 每日驱动 + collect.sh | AI | run-daily 8/8 PASS ✅；一次全量 real 采集 | D0-4/D0-5 | 🚧 smoke/run-daily 落地实测 8/8；collect.sh 待 bash+密钥 |
| D6 | **首刷人工放行**：AI 产镜像 + 刷机卡 → 通知用户 → 用户手动刷入 → 回报 | 人工 | 首刷成功日志 | D3/D5 | ⏳ 待人工 |
| D7–D13 | 每日真机回归循环（冒烟 + NPU v0 回填 + 条件专项）+ P0/P1 修复迭代 | AI+人工兜底 | 逐日报告；P0/P1→0 | D6 | ⏳ |
| D14 | **v0.1 锁基线**（P0/P1=0）→ 恢复上游跟随 → 私人 alpha 交付 | AI+人工 | 基线锁定 + alpha 交付 | D7–D13 | ⏳ |

关联待办（非 D 序列）：
- ~~known-issues 清单~~ → 模板已建 `docs/testing/known-issues.md`（P2/P3 分级 + 社区基线参照归属口径）
- ~~build.yml 注释与策略同步~~ → D1 已完成（双路径 v2；主动消解第三路径流程见 ADR-0003 修订）
- **结构性修复（✅ 已在远端生效）**：`fetch/check-artifacts.sh` 已移出 `build/`（→
  `tools/ci/`，路径已修）+ `.gitignore` 加 `build/artifacts/` + build.yml push 触发收窄为
  `build/patches/**`+`build/configs/**`——**教训：push 到 `build/**`（含 workflow 文件自身）
  触发 build.yml 且 `concurrency.cancel-in-progress` 会取消在跑构建**；本修复原计划延迟推送，
  但 `git push` 推整分支时随 47ba394 一并上车，现已在远端生效。**流程纪律：run 完成前不改
  动/推送 build.yml 与 build/patches、build/configs（docs/、tools/ 推送安全）**

## 5. 交接协议（新会话必读）

1. 先读本文件 → 看板定位最小未完成项 → 从未完成项继续，**不重启已完成的 D0-1/2/3**。
2. 每个动作前自查红线：**永不碰路由器 bootloader 槽**；测试机固件切换只在「社区线内
   sysupgrade / 自建镜像经人工放行」两条通道；真机上不跑任何写类命令于 D6 之前（D5 起
   采集脚本为只读）。
3. 接入工具在 HOME（不入库）：`~/.local/bin/xr1710g-ssh <cmd>`；密码经
   `~/.ssh/xr1710g-askpass.sh` 注入；SSH 密码与 PPPoE 凭据**只许出现在会话与 HOME 文件**。
4. 完成一项 → 更新看板状态 + 在 §6 会话记录追加一行（日期/会话/做了什么/遗留）。

## 6. 会话记录

- **2026-08-17 · D0 会话**：SSH 接入验证（AUTHPASS_OK）→ 只读基线（§2 全项）→ 文档修订
  （ADR-0001 稳定期语义+alpha 发布；ADR-0003 主动消解常态化+每夜镜像+回归耦合；CONTEXT.md
  词条修订与 4 个新词条）→ 本 kanban 建立。遗留：D0-4 公钥安装待用户；D1 消解未开工；
- **2026-08-17 · 目标轮 1（D1）**：主动消解完成——v2 补丁集（10 文件）re-roll 对齐现网
  main 20d94d5；`git apply --check` 全绿 + defconfig 冒烟三断言过（target/profile/u-boot
  变体）；xr1710g dts 独立成文、公共 dtsi 弃用（等 PR 自带）、w1700k 零回归；pr22397.diff
  升级 v2 + v1 归档；build.yml 双路径与注释同步。遗留：**D2 已 push 触发（run
  31963237947 running）**；D0-4 公钥安装待用户。
- **2026-08-17 · 目标轮 2 跟进**：推送成功（仓库有存量凭据）→ build.yml 被 push 触发，
  Actions run 31963237947 in_progress（API 确认）；冒烟脚本 `tools/regression/smoke.sh`
  落地并实测 **PASS=7 WARN=1→0 FAIL=0**（6GHz 频段未枚举修正为已知态）；发现基线事实：
  phy0 只枚举 2.4/5GHz 信道，6GHz 需自建镜像 enable radio2 后验证。
  build.yml 策略注释同步归 D1。
- **2026-08-17 · 目标轮 2 续**：D3/D4/D6 工具就绪——`build/fetch-artifacts.sh`（git 凭据
  PAT 已实测可访问 Actions 产物 API）、`build/check-artifacts.sh`（三件套+GPL 校验，逻辑
  实测 PASS）、`docs/sop/flash-card-template.md`（D6 人工卡）、`docs/testing/known-issues.md`
  （P2/P3 留档模板）；已提交推送（c0fdf9b）。run 31963237947 双 job 仍在构建
  （world ~1.5–2.5h）。遗留：查 run 状态 → 绿则 `bash build/fetch-artifacts.sh <run-id>`；
  D0-4 公钥安装待用户。
- **2026-08-17 · 目标轮 3**：run 31963237947 在 make 阶段被 **cancelled**——根因 = 我上轮把
  工具脚本放进 `build/**`，push 触发新 run（31963637357），`concurrency.cancel-in-progress`
  取消旧构建。**当前 run 31963637357 双 job 已在 make（勿再提交 build/**，直到完成）**；
  公钥仍未装（BatchMode 测试 Permission denied）。结构性修复（脚本移出 build/ → tools/ci/
  + gitignore build/artifacts）挂起至 run 完成后执行。教训已入关联待办。
- **2026-08-17 · 目标轮 4**：run 31963637357 双 job make 已跑 1.5h+（18:09 起，ETA ~21:00
  UTC）；结构性修复**本地完成**（脚本→tools/ci/ 并修路径、.gitignore += build/artifacts/、
  build.yml 触发收窄为 patches/configs）——**只本地提交未推送**（避免再次触发取消）；
  推送随 run 完成后的下一批。遗留同前：D2 待绿、D0-4 公钥待用户。

## 7. 入库存档红线

- 不提交：SSH/PPPoE 凭据、内网敏感拓扑；此文档 §2 已打码（仅公网侧 IP 与网段）。
- README/CONTEXT/ADR 只承载概念与决策，不承载任何访问凭证。- **2026-08-17 · 目标轮 6**：run 31963637357 又被 cancelled——根因 = `git push` 推整分支，
  结构性修复 6ee1e7e 随 47ba394 一并推送（改动 build.yml 自身 → 必触发）→ 新 run
  31964412187（18:22）取代之。**修复现已远端生效**（后续 tools/docs 推送不再触发构建）。
  当前 run 31964412187 双 job 已达 feeds 阶段（冷构建 ETA ~21:30 UTC）。

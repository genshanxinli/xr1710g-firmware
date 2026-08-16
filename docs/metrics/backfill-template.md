# NPU 指标盘点 · 真机回填模板（backfill-template）

> 配套：`tools/metrics/collect.sh`（采集端，8 模块 53 指标位）← `docs/metrics/v0.md`（版本化盘点清单 v0）
> 落位 04 §3「闭环机制：AI 出全量抓取脚本 → 真机跑一遍 → 以实机面板为准滚动收录 → 矩阵版本化」。
> **本文件是流程模板 + 字段说明 + 版本化规则 + 兜底机制，不含真机数据**（本机无真机）。

## 1. 回填流程（M0 真机到场后）

1. **前置**：真机刷入分叉基线（或社区参考基线：orangeyoo v1.2.0 / naoki66 ImmortalWrt）→ root 登录 → 安装依赖（见 `tools/metrics/README.md` §3：`bash`、`iperf3`、`luci-app-airoha-npu`、`flowsense/flowm`、`ethtool`、`fancontrol` 等，社区构建大多内置）。
2. **全量采集**（真机上本机跑，或从任意主机 `--host` 远端跑）：
   - 本机（真机 root）：`bash /root/tools/metrics/collect.sh -o /root/metrics-<date>.tsv`
   - 远端（开发机）：`bash tools/metrics/collect.sh --host root@<IP> -o /root/metrics-<date>.tsv`
   - 真机上设备自检命中 → 自动进入 real 模式（逐指标 OK/NA）；确认文件头 `mode=real`。
3. **对照采集（一键开关）**：NPU offload 关闭状态下再跑一遍全量（`-o metrics-<date>-off.tsv`），与第 2 步（开）构成「一键开关对照」双组。开关手段先固化：uci（flowsense/airoha-npu）+ debugfs 写 + 面板开关，三者任选并在采集记录中注明用了哪个。**关态对照必须包含 `iperf3.template.wifi10g`（10G↔Wi-Fi）位点**：词条③「与 mt76/社区特性共存无降级」需 on/off 双态同点位数据构成直接证据（开态吞吐不劣于关态），不能只靠开态 CPU<5% 的间接证据。
4. **手动阶段（iperf3 不自动跑）**：按第 2 步产出文件中的 `iperf3.template.*` 预留参数逐条执行（换 `<IP>` 占位）：
   - 双 10G 双向近线速（`dual10g`）→ 记吞吐数值；
   - 10G↔Wi-Fi（`wifi10g`）→ 同时另开一个终端跑 `collect.sh --module cpu` 截 `cpu.top_snapshot`（CPU<5% 口径需要同刻数据）；
   - UDP 硬 NAT（`udp_nat`）→ 记吞吐与 `flowsense.flows` 命中；
   - 6GHz 802.11s 回程（`backhaul`）→ 记吞吐/时延 + `iw dev` mesh 状态 + `tx failed` 计数。
5. **回填清单**：把 OK/NA 与关键实测值按 §3 记录表填写；按 §4 版本化规则决定是否 bump v1。
6. **归档**：原始 .tsv/.json 采集文件与面板截图一起归档到 `docs/metrics/runs/`（命名/元信息/截图约定见 `runs/README.md`：`metrics-<YYYYMMDD>-<真机标识>-<on|off>-<序号>.tsv|json`；截图 `runs/screens/<前缀>-panel-<n>.png`；**`-o` 为追加模式，勿复用旧文件，新 run 一律新文件名**），清单引用文件名。

## 2. 字段说明（v0.md 五列）

| 字段 | 含义 | 取值示例 |
|---|---|---|
| 指标名 | 唯一指标 id；与 collect.sh 输出 `metric` 列同名（`模块.子项`） | `mt76.phy0.tx_failed` |
| 采集命令（脚本条目） | 脚本模块与命令或操作模板；`--module <名>` 对应模块 | `mt76 模块 · grep "tx failed" …` |
| 期望值或口径 | 判定「验收通过」的量化/布尔标准（硬性），引用报告并注 `[来源]` | `tx failed = 0 [04 §3 核心口径②]` |
| 真机回填状态 | 采集状态（见下） | `待回填` → 回填后改写为 `已采集·通过 / 已采集·未通过 / 不适用(NA)` |
| 来源 | 报告/文档引用 | `04 §3 核心口径②；02 §7 恩山⑤` |

现状取值全集（v0 未上真机）：`未采集·脚本已含 / 未采集·模板待手动 / 未采集·操作模板 / 未采集·构建态 / 未采集·面板兜底`——**v0.md 全文以「待回填」合并标记即此五值的简写**，回填时按实际采集来源拆分改写；回填后为 `已采集·通过 / 已采集·未通过 / 不适用（NA）`（NA 需在备注写原因：命令缺失 / 接口不存在 / 场景未跑）。**两处词表一致，粒度以本 §2 为准。**

## 3. 回填记录表（每台真机一次；M0 两台都填）

| 字段 | 值 |
|---|---|
| 回填日期 | （UTC） |
| 真机标识 | （SN/昵称，区分两台） |
| 固件版本 / 构建号 | （如分叉 baseline / orangeyoo v1.2.0） |
| 内核版本 | （如 6.18.44） |
| mt76 commit / hostapd commit | （清单 F 组核对用） |
| 使用开关手段 | （uci / debugfs / 面板） |
| 采集文件 | （metrics-<date>.tsv / -off.tsv / json） |
| 工作模式 | （路由 / AP / 桥接 / mesh） |
| offload 状态 | （开 / 关） |

**指标回填快照**（复制 v0.md §1–§6 各章表，把「真机回填状态」改写为实测结果）：

| 指标 | 实测值 / 摘要 | 判定 | 备注 |
|---|---|---|---|
| `npu.fw_version` | | | |
| `npu.firmware_glue` | | | |
| …（全量指标逐行，含 v0.md §1–§3 的 CVE 在场逐条） | | | |

## 4. 版本化规则（v0 → v1 → …）

- **升版一句话**：**指标集 / 通过口径有任何新增、删除或修改 → 版本 bump（v0→v1），由 AI 改清单+collect.sh 并附 changelog，真机数据由人类最小集采集确认后合入；仅回填数值变化（指标集不变）不 bump，只更新「现状」列与回填记录。**
- **主版本（schema）bump**：**指标集有任何新增/删除/改口径** → `v0 → v1`。
  - **谁 bump**：AI（本工作流）负责改清单+变更日志；真机数据由人类最小集采集确认后合入；bump 必须带 changelog。
  - **触发条件**：
    a. 真机回填揭示新的可采集指标（脚本缺、面板有）；
    b. 上游新增 NPU 能力/修复提交（mt76/airoha target 提交史滚动）；
    c. 实机面板新增展示项（luci-app-airoha-npu / FlowSense）；
    d. 验收矩阵本身变更（04 §3 修订）。
  - bump 动作：更新本文件头 `清单版本：v1（日期）` + manifest §1 行增删 + collect.sh 模块同步 + 附录 B 改进项消化。
- **数据修订（不改版）**：仅回填数值变化（如二次回填、重测），指标集不变 → 不 bump，只更新 §3 记录表与 manifest「现状」列，并在头注「最近回填」日期。
- **一致性约束**：manifest 指标 id 必须与 collect.sh 输出 `metric` 列一一对应；新增指标必须先在 collect.sh 有采集项（或明确标「操作模板/构建态」），否则算改进项而不是验收项。

## 5. 兜底机制（以实机面板为准滚动收录）

04 §3 闭环的兜底语义：

1. **面板优先**：真机上 `luci-app-airoha-npu` 面板 / FlowSense 面板出现**脚本未覆盖**的指标 → 登记到 v0.md §7「改进项」，下版 collect.sh 增加采集项并 bump（规则 4a/4c）。
2. **来源不全不进验收**：没有直接实测来源的条目（如 PPPoE 硬卸载）只进改进项，**不进 v1 验收**；等真机数据补上才转正（manifest §5 附录 B 已列）。
3. **滚动收录**：每次真机跑完后，用 §6 核对清单自检「脚本指标位 + 附录 A CVE 逐条」是否全覆盖；未覆盖项按 1/2 处置后仍缺 → 记为采集缺口，随 v1 补脚本。
4. **两面互证**：核心口径（吞吐/CPU/tx failed）至少要有「脚本输出 + 面板截图」两条证据链，防单点工具误判。

## 6. 核对清单（回填完成后逐项打勾）

- [ ] 全量采集文件（开）已产出、`mode=real`、无中断、退出码 0
- [ ] 对照采集文件（关）已产出
- [ ] 53 个脚本指标位逐行有判定（OK/NA 均注明，含 `iperf3.bin_present` 工具链在位检查）
- [ ] `iperf3.template.*` 四条手动执行完毕、数值已记
- [ ] 10G↔Wi-Fi 的 CPU<5% 同期截屏已取
- [ ] mesh 回程：ESTAB + 吞吐/时延 + `tx failed=0` 已记
- [ ] CVE 在场：v0.md §1–§3 构建态行逐条打勾（git 核对 + 运行态日志核对）
- [ ] 面板新增指标已登记改进项（如有）
- [ ] 版本化动作已执行（bump v1 或数据修订）
- [ ] 采集文件与截图已归档 `docs/metrics/runs/`（按 runs/README.md 命名约定：`metrics-<YYYYMMDD>-<真机标识>-<on|off>-<序号>.tsv|json`；截图放 `runs/screens/`；勿复用旧文件）

## 7. 示例（示意数据，非真机实测；仅供填写格式参考）

```
回填日期   : 2026-08-20
真机标识   : XR1710G-02（远楼层）
固件/内核  : fork-baseline / 6.18.44
mt76       : b2704cf5+
开关手段   : uci flowsense 启停
| 指标                     | 实测值                    | 判定     | 备注 |
| npu.fw_version           | NPU fw version: 0.1111    | 已采集·通过 | 与 01 §1 一致 |
| mt76.phy2.tx_failed      | tx failed = 0             | 已采集·通过 | 6GHz 回程 radio |
| iperf3.template.backhaul | 6G mesh 回程 2.1Gbps/1.8ms | 已采集·通过 | offload 开启 |
| CVE-2025-68360           | 修复提交在场 + 运行无崩溃   | 已采集·通过 | 构建态+运行态互证 |
```
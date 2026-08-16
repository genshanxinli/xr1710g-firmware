# tools/metrics · NPU 指标盘点采集端

XR1710G（Airoha AN7581 + MediaTek MT7996）NPU 全功能验收的**指标全量抓取**工具（04 §3 闭环机制的采集端）。

- 采集脚本：`collect.sh`（bash，8 模块 53 指标位）
- 指标清单：`../../docs/metrics/v0.md`（版本化盘点清单 v0，按 ①–⑤ 验收矩阵章节组织）
- 真机回填：`../../docs/metrics/backfill-template.md`（流程 / 字段定义 / 版本化 / 收录规则）
- 目录所有权：本目录归 NPU 指标盘点工作流唯一使用（任务约束：只写 `tools/metrics/` 与 `docs/metrics/`）。

## 1. 快速开始

```bash
# 本机（无真机）dry-run：自动探测后全部占位 PENDING_DEVICE + 结尾【缺真机清单】，退出码 0
bash tools/metrics/collect.sh

# 强制 dry-run（即使 --host / 设备自检命中也不采集）
bash tools/metrics/collect.sh --dry-run

# 真机·远端（ssh，推荐）：远端需已装 bash；命令 base64 管道执行；iperf3 仍只出模板
bash tools/metrics/collect.sh --host root@192.168.50.1 -o /root/metrics-$(date +%F).tsv

# 真机·本机（OpenWrt root）：设备自检命中自动进入 real-local
bash tools/metrics/collect.sh -o /root/metrics-$(date +%F).tsv

# 单选模块 / JSON 输出 / 模块清单 / 帮助
bash tools/metrics/collect.sh --module npu
bash tools/metrics/collect.sh --dry-run --module thermal -o run.json --format json
bash tools/metrics/collect.sh --list
bash tools/metrics/collect.sh --help
```

## 2. 三种运行态

| 运行态 | 进入条件 | 行为 |
|---|---|---|
| **dry-run** | 未指定 `--host` 且本机设备自检未命中；或 `--dry-run` 强制；或 `--host` 的 ssh 不可达（回落并打 warn） | **不执行任何探测命令**；每条指标输出占位值 `(无真机 · PENDING_DEVICE)` + `PENDING_DEVICE` 标记 + 期望值/口径列（含 `[来源]` 标注）；stderr 结尾汇总**【缺真机清单】**（逐条指标名 + 期望摘要）；退出码 0 |
| **real (local)** | root 真机 + 设备自检命中（`/proc/device-tree/model` 含 `xr1710g\|w1700k\|an7581`；`/sys/kernel/debug/airoha` 或 `…/flow` 存在；`/lib/firmware/mediatek/en7581_MT7996_npu_rv32.bin` 存在；aarch64 且 firmware 目录含 en7581；`ubus` 存在） | 逐模块实际采集；符合口径 → `OK`，空输出/不符合 → `NA` 并继续 |
| **real (remote)** | `--host <user@ip>` 且 ssh 可达（BatchMode=yes / ConnectTimeout=5 预检） | 每条命令 `base64` 编码后 `ssh HOST "echo …\| base64 -d \| bash"` 执行，逐指标 `OK/NA`；iperf3 仍只出模板 |

dry-run 与真机模式的**唯一差异是执行与否**：指标集合、期望值/口径列、输出列结构完全一致——dry-run 输出可直接视为"回填模板的字段清单"。

## 3. 依赖（真机/远端侧 + 本机侧）

| 位置 | 依赖 | 用途/说明 |
|---|---|---|
| 远端（OpenWrt） | `bash` | collect.sh 命令管道解释器（OpenWrt 默认 ash，需 `opkg install bash`） |
| 远端 | `iperf3` | 吞吐位点（脚本**只出预留模板，绝不自动测速**） |
| 远端 | `luci-app-airoha-npu` | NPU 面板/可观测/开关（`npu.luci_panel`/`npu.luci_counters`；上游 opkg 一般无此包 → 社区构建 naoki66 / orangeyoo 内置或自编译） |
| 远端 | `flowsense`（含 `flowm`） | FlowSense 流表/PPE 计数（同社区构建内置） |
| 远端 | `ethtool` | `eth.ethtool_dump` / `eth.phy_driver`（未装则该两行 NA，sysfs `eth.port_*` 行仍可采集） |
| 远端 | `dmesg`/`logread` 可读 | alerts / npu / flow 模块需要内核日志；root 下可直接读，非 root 需 `sysctl kernel.dmesg_restrict=0` 或 sudo |
| 远端 | debugfs 挂载 | `/sys/kernel/debug/{airoha,flow,ppe,ieee80211}`；未挂载先 `mount -t debugfs none /sys/kernel/debug` |
| 远端 | `iw` | mt76 频段/6GHz 判定（OpenWrt 默认有） |
| 远端 | `procps-ng`(可选) | `cpu.pidstat`（未装→该行 NA 不阻塞） |
| 本机（跑 `--host` 时） | `ssh` client + `base64` | 远端执行管道（base64 编码避免引号转义地狱） |
| 本机（dry-run） | `date` | 时间戳；**无需 root/无特殊权限** |

建议先刷社区参考构建（orangeyoo v1.2.0 / naoki66 ImmortalWrt）再跑，上述多数包已内置。

## 4. 输出格式

**列（text/TSV 一致）**：`时间戳(UTC) | 指标名 | 期望值/口径[来源] | 值 | 来源命令 | 标记`
**标记**：`OK`（采集且含口径关键词）/ `NA`（空输出或不符合）/ `PENDING_DEVICE`（缺真机占位）。
**JSON（JSONL）**：每行一个对象 `{"ts","module","metric","expect","value","command","flag"}`；文件首行 `_meta`。

- 默认 stdout 为 text；`-o 文件` 时默认 TSV、`--format json` 为 JSONL；`-o` 为追加模式。
- `#` 开头行为元信息/模块分隔（TSV/JSON 解析统一先 `grep -v '^#'`；JSON 另跳过 `_meta` 行）。
- 来源命令里的管道符显示为 `¦`（列安全转义，展开即 shell 管道）。
- 值/期望/命令列超长自动截断（400/180/230 字符）；多行折叠单行。
- `NA`/`PENDING_DEVICE` 均不中断：真机模式单指标失败继续；参数错误才 exit 2，运行恒 exit 0。
- 期望值/口径列**只引用报告原文并注明出处**（`[来源: 04 §3 …]` / `[来源: 02 §7 …]` / `[来源: 01 §1.25 …]`），本工具不产生任何实测值。

## 5. 模块一览（8 模块 / 53 指标位）

| 模块 | 指标位 | 对应 v0.md 章节 | 说明 |
|---|---|---|---|
| `npu` | 8（fw_version / firmware_glue / reserved_mem / dts_node / debugfs_tree / luci_panel / luci_counters / dmesg_ring） | ①④ | NPU 固件版本、路径、可观测、**luci-app-airoha-npu 面板与计数** |
| `mt76` | 1 + 5×per-phy（band / is_6ghz / **tx_failed** / wed_queue / mt76_debugfs） | ①⑤ | per-radio + WED 计数，含 6GHz 判定；dry-run 按 phy0/1/2 示例展开，真机按实际 phy |
| `flow` | 6（bin / uci / flows / flows_pattern / log / ppe_debugfs） | ②③⑤ | **FlowSense 流表（PPPoE/VLAN/AP 模式）** 与 PPE debugfs |
| `eth` | 5（port_list / port_speed / port_link / ethtool_dump / phy_driver） | ② | **ethtool+sysfs 链路状态**（2×10G RTL8261BE + 2×1G MT7530） |
| `cpu` | 4（loadavg / top_snapshot / pidstat / softirqs） | ③④ | 占用采样（10G↔Wi-Fi CPU<5% 证据链） |
| `iperf3` | 1 + 4 预留模板（dual10g / udp_nat / wifi10g / backhaul） | ①②③⑤ | **只生成命令模板，不自动测速** |
| `alerts` | 6（dmesg_oom / dmesg_panic / dmesg_wed / dmesg_airtime / governor / max_inactivity） | ③ + M3 | **dmesg OOM/CVE/崩溃告警扫描**（ABSENT 语义：空输出=OK） |
| `thermal` | 3（zones / hwmon / fancontrol_cfg） | M3 环境 | 温度 52–57°C 常态（旗舰口径，非 04 §3 硬性） |

## 6. 维护约定（新增指标）

1. 在 `collect.sh` 加 spec 组（**严格 4 行**：`指标名 / 采集命令 / 期望值或口径[来源] / 关键字`；关键字：实际关键词=输出须含、`ABSENT`=须为空、`TEMPLATE`=不执行、`-`=不检查；新模块需加进 `MODULES_ALL` 并提供 `SPEC_<大写模块名>`）。
2. 同步 `docs/metrics/v0.md` 对应章节加行（指标 id 与脚本 `metric` 列一致），并走 `backfill-template.md` §4 版本化 bump（v0→v1）。

## 7. 验收自检（开发环境复现）

```bash
bash -n tools/metrics/collect.sh                 # 语法检查
bash tools/metrics/collect.sh; echo $?           # dry-run：全 53 条 PENDING_DEVICE，exit 0
bash tools/metrics/collect.sh --dry-run --module npu -o /tmp/n.tsv          # TSV
bash tools/metrics/collect.sh --dry-run --module cpu -o /tmp/n.tsv --format json  # JSONL
bash tools/metrics/collect.sh --host root@<IP> --module eth                # 远端 eth 模块
```

dry-run 自检要点：stdout 逐行可见 `PENDING_DEVICE` 标记；stderr 结尾出现 `[summary] … PENDING_DEVICE=53 total=53` 与**【缺真机清单】**；退出码 0；本机未命中真机检测即自动进入 dry-run（无需任何设备）。
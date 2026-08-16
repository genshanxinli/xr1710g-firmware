# docs/metrics/runs · 真机采集归档目录

> NPU 指标真机回填产物的**唯一归档处**（配合 `tools/metrics/collect.sh` 与
> `docs/metrics/backfill-template.md` §1 第 6 步 / §6 核对清单）。
> **当前状态：真机未到场，本目录仅含本说明文件（占位），尚未有任何 run。**

## 目录约定

- **采集文件**：`metrics-<YYYYMMDD>-<真机标识>-<on|off>-<序号>.tsv|json`
  - `<YYYYMMDD>`：采集日期（UTC，与文件内时间戳一致）
  - `<真机标识>`：真机 SN/昵称（须与 backfill-template.md §3 回填记录一致，区分两台）
  - `<on|off>`：本次采集时 NPU offload 开关状态（一键开关对照双组各一份）
  - `<序号>`：同日同机同态多次采集的递增序号（从 1 起），保证文件名唯一
  - 例：`metrics-20260820-XR1710G-02-on-1.tsv`、`metrics-20260820-XR1710G-02-off-1.tsv`
- **面板截图**：`runs/screens/<前缀>-panel-<n>.png`
  - `<前缀>`：与采集文件同前缀（如 `metrics-20260820-XR1710G-02-on-1`），
    `n` 为第几张（luci-app-airoha-npu / FlowSense 面板、iperf3 结果、CPU 快照、mesh 状态等）
- **补充证据**（可选）：同一 run 的日志片段/截图放 `screens/` 或同前缀子目录，文件名带前缀即可

## 元信息（每个 run 必须附）

每 run 至少含以下回填元信息（collect.sh `-o` 自动在文件头写 `# meta: …` 行；
JSON 为 `_meta` 行；其余字段记入 backfill-template.md §3 回填记录表）：

| 字段 | 说明 |
|---|---|
| 真机标识 | SN/昵称（同 §3，区分两台） |
| 基线版本 / 固件 | 分叉基线或社区参考基线（orangeyoo v1.2.0 / naoki66 ImmortalWrt 等） |
| 采集时间 | UTC 日期时间（collect.sh 逐行时间戳） |
| 脚本版本 | collect.sh v0（meta 行 `script=collect.sh v0`） |
| offload 开关状态 | on / off（文件名亦含） |
| 开关手段 | uci / debugfs / 面板（同 §3「使用开关手段」） |

## 采集纪律

- **`-o` 为追加模式**：切勿在旧文件上追加/复用——新 run 一律新文件名，
  否则旧 run 的时间戳与元信息被污染，回填按文件断言失真。
- 同一次「一键开关对照」至少产出 on / off 两份文件 + 对应 `screens/` 截图，
  满足 04 §3「两面互证」（脚本输出 + 面板截图）可追溯。
- run 内 `iperf3.template.*` 手动执行数值记入 backfill §3 回填记录表或随文件附注，
  不在本目录另建汇总表（汇总走版本化清单 `docs/metrics/v0.md`）。
- 「连续稳定运行 7×24h」证据（运行时长 + 日志/截图）由本目录承载（v0.md §6 说明，
  状态位 `M3.run_duration`）；UBI/I/O 错误扫描证据亦随 run 归档（v0.md §7 改进项）。
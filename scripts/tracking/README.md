# scripts/tracking —— 自动跟进循环（M4）· 抓取 + 报告

把调研报告 `docs/research/05-watchlist.md`（盯梢清单 18 条源）里可在 CI 自动化的源，
落地为可实跑的**两段式**流水线：`fetch.sh` 抓原始数据 → `report.py` 汇总跟踪报告。

交付物（本目录）：

| 文件 | 作用 |
|---|---|
| `fetch.sh` | 抓取阶段（bash + curl + git，python3 做日期/解析）。每源一文件，源失败记 SKIP 不中断 |
| `report.py` | 报告阶段（python3，无第三方依赖）。固定四节模板 + "今日无数据"占位 |
| `README.md` | 本文档 |
| `.github/workflows/tracking.yml` | 每周一 03:15 UTC + 手动触发：fetch → report → commit+push `docs/tracking/` |
| `docs/tracking/YYYY-MM-DD.raw/` | 每日原始数据（每源一个文件 + `99_STATUS.tsv` + `00_fetch.log`） |
| `docs/tracking/YYYY-MM-DD.md` | 每日跟踪报告（公开可审计） |

## 运行命令

```bash
# 一步跑完（fetch → report → 当日报告）
bash scripts/tracking/fetch.sh                 # 今天 UTC
python3 scripts/tracking/report.py

# 指定日期 / 单独跑某一阶段
bash scripts/tracking/fetch.sh 2026-08-16      # 补跑指定日期
python3 scripts/tracking/report.py --date 2026-08-16
python3 scripts/tracking/report.py --raw docs/tracking/2026-08-16.raw   # 只看某期 raw
```

- `fetch.sh` 退出码：`0` = 至少一个源成功（其余如实 SKIP）；`1` = 全部源失败（网络整体故障，CI 判失败）；`2` = 参数非法。
- `report.py` 退出码恒 `0`（raw 缺失时输出"今日无数据"占位，便于 debug）。

## 覆盖源（对应 05-watchlist / 03 第 6 节）

| 源 | 通道 | 原始文件 | 频率建议 |
|---|---|---|---|
| #1/#3 git.openwrt.org | `git ls-remote main` + 浅克隆定向日志（`git log --since=14d -- target/linux/airoha package/network/services/hostapd package/kernel/mt76`，`--filter=blob:none --shallow-since=30d`，临时目录用完即删） | `01_git_lsremote.txt` / `03_git_openwrt_log.txt` | 每日 |
| #4 GitHub 镜像 airoha | API `commits?path=target/linux/airoha&since=14d` | `04_gh_airoha_commits.json` | 每日 |
| #5 GitHub 镜像 mt76 | API `commits?path=mt7996&since=14d` | `05_gh_mt76_commits.json` | 每日/隔日 |
| #6 w1.fi | `w1.fi/releases/` 目录页，grep hostapd 版本号 | `06_w1fi_hostapd_versions.txt` | 每周 |
| #14 snapshot an7581 | `downloads.openwrt.org/snapshots/targets/airoha/an7581/profiles.json` | `14_an7581_profiles.json` | 每周 |
| #14b（附加）an7583 | 同上 an7583 profiles（盲区预判 2 证据） | `14b_an7583_profiles.json` | 每周 |
| #15（附加）releases | `releases/` 目录 + 最新版 `targets/` 探测（预判 1：稳定版 airoha） | `15_releases_dir.txt` / `15b_latest_release_targets.txt` | 每发布周期 |
| 附加 | API `pulls/22397`（构建触发信号） | `07_gh_pr22397.json` | 每日 |
| 附加 | API `torvalds/linux commits?path=arch/arm64/boot/dts/airoha`（预判 3） | `16_gh_linux_airoha_dts.json` | 每周 |

**不自动化的盯梢条目**（按 05 清单保留人工/通知驱动）：论坛帖 #222776/#247242/#252504、
论坛 `search.json`（⩽1 次/分否则 429）、恩山（需登录）、社区 GitHub Releases
（naoki66/orangeyoo/hx801217，API 开销换低信息量，改 Watch→Releases only）、
lore.kernel.org、TechInfoDepot、中文博客。

## 依赖

- bash（GNU）、curl、git、python3（≥3.8，无第三方包）、`sort -V`、grep/sed/awk。
- 单次运行网络开销：**4 次 GitHub API** + 3 次静态页（w1.fi / downloads×2）+ 2 次 git 协议操作（ls-remote、浅克隆）+ 1 次 linux 主线探测 ≈ 15–90 秒（浅克隆是主要耗时）。

## 限流约定（实测事实为本）

- **GitHub API 未认证 60 次/时**（按出口 IP）：脚本每次运行恰 4 次（#4/#5/PR/linux-dts），
  且 **curl 无 --retry**——失败即记 SKIP，绝不重试轰炸；撞 403 时错误体落盘、`99_STATUS.tsv` 记原因。
- 论坛 `search.json` **⩽1 次/分**（否则 429）：本流水线不抓论坛，避免触发反爬。
- 恩山需登录：人工每周回填。
- CI 每周 1 次 + 手动触发，与"每夜保底"构建节奏解耦；如需提升配额，在 workflow 加 `env: GH_TOKEN`
  并在抓取层透传 `Authorization` 头（默认未认证路径保持可用）。

## 输出目录与报告结构

- `docs/tracking/<date>.raw/`：每源一个原始文件 + `99_STATUS.tsv`（`源\t状态\t原因`）+ `00_fetch.log`。
  全部 UTF-8；临时文件走 `mktemp -d`，不落仓库（.gitignore 只豁免 `docs/tracking/*.tmp`）。
- `docs/tracking/<date>.md` 固定模板四节：
  ① 上游动态（airoha/mt76/hostapd 提交与版本）② 构建触发信号（PR #22397、新设备 profile、
  新 hostapd 版本——有则 GitHub admonition 显著标出）③ 风险变化（R1–R10 逐项：自动信号或"人工"）
  ④ 盲区监测点（03 第 5 节 6 条预判逐条检查：命中/未命中/数据缺失）＋附录源状态表。
- raw 缺失时 report.py 输出"今日无数据"占位，debug 友好。

## 排错速查

| 现象 | 处理 |
|---|---|
| 某源 SKIP | 看 `99_STATUS.tsv` 原因列 + `00_fetch.log`；单源失败不影响其余源与报告 |
| GitHub 403/429 | 本时段配额耗尽，SKIP 如实保留；勿立即重跑（60 次/时窗口），等下一小时或换 IP |
| git 浅克隆失败 | `03_git_openwrt_log.txt` 缺失 → SKIP；可临时用 #4/#5 API 侧数据交叉核对 |
| 报告缺某节数据 | 对应 raw 文件缺失即该源 SKIP；检查 fetch 阶段日志 |

新增源：在 `fetch.sh` 加抓取块（复用 `fok`/`fskip`/`http_get`），`report.py` 对应节加渲染即可。
# Airoha AN7581 / MediaTek MT7996（Wi-Fi 7）平台 · 前沿情报与盯梢清单

**情报快照日期：2026-08-15（UTC，本文所有"今日/最近"均指 8 月中旬；□=已核实 ✓，△=部分核实，✗=未能确认）**

---

## 0. 结论快览（TL;DR）

- OpenWrt 主线已进入 **Linux 6.18 时代**（airoha target `KERNEL_PATCHVER:=6.18`，当前 6.18.44，2026-08-10 bump）；25.12 稳定分支为 6.12；24.10 为 6.6。**AN7581 支持已含于 24.10 与 25.12 分支代码（含 an7581 sub-target；具体引入时间未逐一核证），但官方**二进制镜像**只有 main snapshot（`downloads.openwrt.org/snapshots/targets/airoha/an7581/`），25.12.x 与 24.10.x 发布目录均无 airoha。**
- **新 SoC：Airoha AN7583**（2026-05 起入主线，Nokia XG-040G-MF 是首发机型，8 月刚完成 UBI 支持）——这是平台线最大的新增量。
- mt76/mt7996 2026 年里程碑：**eMLSR（2026-02）、MT7992 variant（2026-02）、MT7990/NPU 支持（2026-01）、HW ATF（2026-06）**，MLO 修复贯穿整年（最近 2026-07-22 "fix MLD ID in MAC TXD and HIF TXP"）。
- **hostapd 2.12 于 2026-08-07 发布，OpenWrt 当天同步**；OpenWrt ucode 层 7 月已补 320MHz/CSA/MLD 处理。
- XR1710G = W1700K 同硬件（Brightspeed 版），**2×10GbE（RTL8261BE/USXGMII）+ 2×1GbE**；已知坑：双 10G 口同时接线会令 Web UI 失联（论坛 2026-08-15 报告）。
- 社区非常活跃：OpenWrt 论坛 #222776 已 3779 楼 / 10.9 万浏览；GitHub 上 naoki66 的 ImmortalWrt 构建 ★86、每日发布；iStoreOS/OpenWrt 社区固件 v1.2.0（2026-08-13）已带 6GHz EHT320/802.11s Mesh、PPE 硬卸载（含 PPPoE）、Docker。

---

## 1. OpenWrt 上游动态

### 1.1 主线内核版本与 airoha target 状态

- airoha target 现含 3 个 sub-target：`en7523 / an7581 / an7583`，`KERNEL_PATCHVER:=6.18`（`target/linux/airoha/Makefile`，main 分支，2026-08-15 抓取）。
- 主线内核细节：`target/linux/generic/kernel-6.18` → `LINUX_VERSION-6.18 = .44`，即 Linux 6.18.44（commit `53a0d54766` "kernel: bump 6.18 to 6.18.44"，2026-08-10）。
- 迁移时间线：`bc864d2978` "airoha: use kernel 6.18 by default and drop 6.12"（2026-06-03）；`e89e9c412f/b0687062bd` "kernel/airoha: create/restore files for v6.18 (from v6.12)"（2026-06-03）。
- 分支对照：openwrt-25.12 分支 airoha `KERNEL_PATCHVER:=6.12`；openwrt-24.10 分支同样含 `an7581/an7583` sub-target（2025 年初引入）。GitHub 发布标签：**v25.12.0 = 2026-03-05**（`python` 从 releases/tag/v25.12.0 页 `<datetime>` 解析）、**v25.12.5 = 2026-07-01**（最新点版本）。
- **上游 Linux 主线仍无 AN7581 设备树**：`torvalds/linux` master `arch/arm64/boot/dts/airoha/` 仅 en7581（2026-08-15 检查）；OpenWrt 正在把 AN7581 相关驱动"回移上游"（2026-07-20 `79da6837d7` "backport pinctrl patches from Linux mainline"、2026-06-17 `3ed5f08733` "replace multi serdes patch with upstream kernel version"），说明 SoC 级驱动正在逐步上游化。

### 1.2 git.openwrt.org 近期提交（airoha 路径，2026-05 → 2026-08-15）

抓取自 cgit 路径过滤视图（`log/?h=main&path=target/linux/airoha`）与 GitHub 镜像 commits API（100 条，2026-05-01 起）。主题归纳：

- **新设备**：5/23 `a6ecb09985` Nokia XG-040G-MD（AN7581）；6/15 `42b8e0d9b7` Nokia XG-040G-MF（AN7583）初版；8/9 `cbe75a7bb1` XG-040G-MF (UBI) 完成；Nokia Valyrian（AN7581，SFP+）。
- **AN7583 成长线**：5/16 去 source-only（`25667811da`）、USB PHY 驱动（8/7 `38ac788893` + DT binding 8/9）、SFP/switch port/LED 修正（6/30 一组）、UBI 支持（8/9）、eMMC EVB 默认构建（7/18）。
- **以太网/卸载面**：6/16 `2c122bdd74` "introduce HW-GRO support"；5/25 `d22ceb8d24` "Improve LRO performances"；6/19 `d3e13c05f7` "account for L2 overhead in PPE MTU configuration"；5/22 `e1915674ab` "multi-serdes on same GDM port"；5/22 `5b25d4235d` GDM2 回环修复；7/16 `5625dadb4b/4be1036213` AN7583 PCS 端口数修正；8/7 `3d25753554` NPU 固件加载去掉 sysfs fallback。
- **Wi-Fi 相关**：8/7 `ab2dc6ab16` "an7581: reserve NPU Wi-Fi regions only on Wi-Fi boards"；7/14 `4fa33a0724` eMMC 板 PCIe x2-lanes 模式（配 mt7996/7992）；8/10 GPIO 数量修正；7/22 OPP/ATF 内存标签对齐。
- **工程化**：7/16 `94a21b3fe9` "uboot-airoha: move FIP generation to target"；ATF/U-Boot 产物（BL2/BL31）脚本化；6/15 `581134305e` base-files IPKG_INSTROOT 修正。
- 代表性全量提交（GitHub API，查证日 2026-08-15）：见本报告末尾"来源"；盯梢可直接用第 6 节清单里的 API/git 命令。

### 1.3 mt76 近期提交（MT7996/MT7992，2026-01 → 08）

`openwrt/mt76`（官方 mt76 维护树的 GitHub 镜像；上游补丁最终经 linux-wireless/无线子系统合入内核）：

- **NPU/新芯片**：2026-01-22 一组 10 连发为 MT7990 chipset 加 NPU 支持（`01575edfc3` "Add NPU support for MT7990 chipset"、`8a02211445`/`9e10bcac81` DMA/init 集成等）；2026-02-12 `f656567eff` "add variant for MT7992 chipsets" + `8831fa78cb` "add external EEPROM support for mt799x chipsets"。
- **MLO/eMLSR**：2026-02-03 `4aa63d4c5b` "Add eMLSR support"；2026-03 一组 MLO link 生命周期管理（`a4c790aef4` "Add mcu APIs to enable/disable vif links"、`fb6a584e71` "add per-link beacon monitoring for MLO"、`39c960c3ad` "fix frequency separation for station STR mode"）；2026-07-22 `4efe882252` "fix MLD ID in MAC TXD and HIF TXP"、`4ac697d5fb` "fix non-AQL packet accounting for MLO stations"。
- **EHT**：2026-03-13 `968dc6335a` "fix capability of EHT-MCS 15 in MRU"；`763e99aadb`（6/21）`mt7996_mcu_sta_bfer_eht()` NULL 解引用修复。
- **其他**：2026-06-29 `910db36ae5` "HW ATF support"；6/20 `1ee3e2f6c2` "expose per-band MAC addresses to cfg80211"；7/05 `5ecae46405` "select net_setup_tc handler at runtime"；8/01 一批 PS（Power-Save）/out-of-bounds 修复（`b2704cf5a4` 等）。
- 注：320MHz/6GHz 是 mt7996 的存量能力（非本次窗口新增）；2026 年的重点是 MLO/eMLSR/NPU 路径稳定性与 MT7992/MT7990 变体。

### 1.4 hostapd / wpa_supplicant：2.12 + EHT/MLO/320MHz/6GHz 落地

- **hostapd 2.12 于 2026-08-07 13:23 UTC 发布**（w1.fi/releases/hostapd-2.12.tar.gz），**OpenWrt 当天同步**（`4abffae9b4` "hostapd: update to 2.12"，2026-08-07；PKG_SOURCE_DATE=2026-08-07）。ChangeLog 亮点：EHT/IEEE 802.11be **"more complete support"** + 报文校验 DoS 修复 + 组密钥重协商修复；**6GHz AFC（自动频率协调）支持**；SAE group 20 默认开启（配 SAE-EXT-KEY）；DPP release 3；后台 radar/CAC 支持。
- wpa_supplicant 2.12（同日 tarball）ChangeLog 亦含 EHT/802.11be 章节。
- **OpenWrt hostapd ucode（2026-07-10 一波，Wi-Fi 7 配置面）**：`c5c316b0ab` "support 320 MHz in freq_info"、`b92df1e8da` "fix CSA bandwidth for 320 MHz and 80+80 channels"、`26a4d50806` "filter MLD loops by phy in phy_set_state/phy_status"、`247595eac1` "parse frequency and STA-channel radio markers"、`a2c5be2783` "compute 6 GHz segment centre in iface_freq_info"。
- MLO 现状：OpenWrt 配置面已有完整 MLD 处理链（ucode `mld_set_config`、MLD 环路过滤等）；mt76 侧持续修 MLO（见 1.3）；论坛有用户实测 2+5+6 MLO（见 2.1）。仍属"可用但不等于开箱即稳"的实验性阶段。
- 安全：2026-07-02 `8614a2ba68` "hostapd: fix security advisory 2026-1"。

### 1.5 官方镜像与发布渠道现状

- **snapshot（每日）**：`downloads.openwrt.org/snapshots/targets/airoha/an7581/` 有 7 个 profile 的完整镜像：`airoha_an7581-evb`、`evb-emmc-eagle`（MT7996）、`evb-emmc-kite`（MT7992）、`gemtek_w1700k-ubi`、`nokia_valyrian`、`nokia_xg-040g-md(-ubi)`——即 **W1700K / XG-040G-MD 已有官方 snapshot 镜像**（含 wifi：`wpad-basic-mbedtls` + `kmod-mt7996-firmware` + `airoha-en7581-mt7996-npu-firmware`）。
- **25.12.x 稳定版：无 airoha**。`releases/25.12.5/targets/` 目标列表无 airoha（24.10.8 同样 404）——稳定版尚未发行 AN7581 镜像（分支代码在，发布管线未出）。XR1710G 在 OpenWrt 侧无独立 profile（= W1700K same hardware，社区以自定义 dts `an7581-xr1710g-ubi.dts` 覆盖）。

---

## 2. 社区活跃度

### 2.1 OpenWrt 论坛

| 帖子 | 主题 | 建帖 | 规模 | 最后回帖 | 近期要点 |
|---|---|---|---|---|---|
| **#222776** | Quantum Fiber W1700k support ✓ | 2025-01-27 | **3779 楼 / 10.9 万浏览** | **2026-08-14** | MLO(2+5+6) 与 legacy 双网络对比实测；6GHz 160MHz（Apple 客户端限制 320MHz）；HW offload 开启；fanboy UBI2 固件；硬件 rev 2.1 |
| **#247242** | Brightspeed XR1710G same device as the W1700K ✓ | 2026-03-06 | 159 楼 | **2026-08-15（当日）** | **双 10G 口（10G WAN + 10G LAN）同接 → Web UI 失联**（网络仍通，拔 WAN 不恢复，须退回 1G LAN 口操作；KK612 2026-08-15 报告） |
| **#252504** | Gemtek XR1710G community build（orangeyoo）✓ | 2026-08-07 | 1 楼（新） | 2026-08-07 | 社区首版：Airoha AN7581 + MT7996，**6GHz 802.11s Mesh / EHT320**、iStoreOS 风 LuCI、U-Boot Recovery |

- 论坛 search.json API 对无登录/数据中心 IP 限流（实践中 429，需 ≳1 次/分钟节奏）；发现新帖可用 `https://forum.openwrt.org/search?q=XR1710G` 或用 DDG `site:forum.openwrt.org XR1710G`。

### 2.2 恩山论坛（✗ 未能确认）

- `www.right.com.cn/forum/` 从本环境不可达（TLS 连接失败，exit 35），且其搜索需登录。**未能确认任何具体帖子 URL/最新状态**；中文社区的活跃证据来自可访问源：Mobile01 开箱帖（"洋垃圾WIFI7路由XR1710G開箱"，f=110&t=7284929）与中文博客 "XR1710G 上手"（blog.yazawaniko.com/index.php/archives/336/，**2026-06-21**）。建议人工周期盯梢（见第 6 节）。

### 2.3 GitHub 相关仓库活动（2026-08-15 查询）

| 仓库 | ★ | 最近 push | 最近 release | 说明 |
|---|---|---|---|---|
| **naoki66/ImmortalWrt-for-Gemtek-XR1710G** | **86** | **2026-08-15** | 20260815-a8ed1a3815（每日/隔日构建） | 社区主构建；kernel 6.18.41；上游 sync 2026-08-07；含 luci-app-airoha-npu/flowsense/fancontrol/recovery |
| orangeyoo/XR1710G-OpenWrt-iStoreOS-Community | 9 | 2026-08-13 | **v1.2.0（Pre-release）2026-08-13**，v1.1.0 8/11，v1.0.0 8/06 | Linux 6.18.41 + hostapd 2026-07-09；Docker(Moby/compose/Dockerman) 预装；6GHz SAE Mesh 默认禁用空密钥；flow offload 默认开 |
| hx801217/iStoreOS-for-Gemtek-XR1710G | 21 | 2026-07-05 | 每日北京时间 00:00 定时编译 | iStoreOS 官方风格 |
| hurrian/w1700k-ubi-installer | 33 | 2026-04-25 | 2026.04.25（Installer for W1700K, XR1710G） | 一键刷机工具链 |
| OpenWRT-fanboy/w1700k-ubi-build | 15 | 2026-04-24 | 论坛 222776 常提的 "UBI2" builds | |
| Arthur97172/Gemtek-XR1710G-wrt-builder | 4 | 2026-08-12 | | OpenWrt/ImmortalWrt 构建器 |
| skyboooox/ImmortalWrt-Gemtek-17xx | 6 | 2026-08-10 | Releasable：XR1710G & W1700K | 可复现构建器 |
| Gilly1970/Gemtek-W1700K / Gemtek-W1700K-6.18 | 3/9 | 2026-08-14 | | fancontrol + FlowSense 来源 |
| rchen14b/luci-app-w1700k-fancontrol / luci-app-airoha-npu | 7 | 2026-03-08 | | 风扇/NPU LuCI |
| lvcdy/openwrt_xr1710g | 7 | 2026-05-12 | | 早期移植 |
| lotusmomo/airoha_sdk | 7 | 2026-05-13 | 无 | **"SDK for AIROHA AN7581"**（来源待考证，警惕非官方） |
| cooip-jm/an7581 | 3 | 2026-08-03 | | |
| Ljzd-PRO/xg040g-openwrt-switch | 1 | 2026-08-01 | | **XG-040G-MD 当 4 口 10G 交换机**的 OpenWrt 固件（1400MHz 软件交换优化、tcboot） |
| YYH2913/openwrt | — | — | — | 注意：README 自述是 git.openwrt.org 的 GitHub 镜像（"not active for check-ins… accept Pull Requests"），orangeyoo 在其上做板级支持基线 |

---

## 3. 同平台新设备（2026 年新出现）

- **AN7581（存量 SoC）新增**：
  - **Nokia XG-040G-MD**（10G ONT/uExpress？）2026-05 入主线；后续 GPS、LED、GPIO 修正；社区有"当 4 口交换机"玩法。
  - **Nokia Valyrian**（AN7581，含 SFP 口、AeonSemi AS21xxx PHY、MT7996 Wi-Fi、USB3）——已入 snapshot 镜像。
  - **Gemtek W1700K 硬件版本迭代**（论坛提及 rev 2.1；UBI 分区表变更曾触发 compat v2 提示）。
- **AN7583（全新 SoC，2026 年中现身）**：Nokia XG-040G-MF（8 月 UBI 支持完成）＋ AN7583 EVB（SNAND/eMMC）；新增 USB PHY 驱动、SFP 相关节点、Airoha EN8811H 10G PHY（`kmod-phy-airoha-en8811h`）。这是平台线未来 3-6 个月最值得盯的硬件变量。
- **零售市场**：✗ 未检出华硕/TP-Link/小米等零售品牌采用 AN7581——该 SoC 目前只见于 ISP 渠道（Gemtek 代工：CenturyLink/Lumen/Quantum Fiber W1700K、Brightspeed XR1710G、Nokia 系 ONT）；国内以洋垃圾/二手流通（Mobile01/中文博客开箱为证）。✗ Arcadyan/Sercomm 采用 AN7581 亦未能确认。

---

## 4. 前沿技术主题（Wi-Fi 7 固件圈激进玩法 × XR1710G 定位）

- **6GHz 无线回程 / EHT320**：naoki66 固件默认三频全开：2.4G HE20、5G EHT160/ch36、**6G EHT320/ch37**（README 将 6GHz MT7977AN 标注 "(backhaul)"）；#252504 帖子标题即 "6 GHz 802.11s Mesh / EHT320"。6GHz 用 WPA3-SAE Mesh 空密钥模板默认禁用（v1.2.0）→ 实际玩法是"6GHz 回程专线/802.11s 组网"。
- **MLO / eMLSR**：mt76 2026-02 加 eMLSR、03-07 月持续 MLO link 修复；hostapd 2.12 + OpenWrt ucode MLD 处理齐备；论坛实测 2+5+6 MLO 已有人用（8/14），但仍有稳定性反馈 → 定位"实验性可用"。
- **EasyMesh/QSDK**：OpenWrt 生态无 EasyMesh（那是高通/Vendor 私有栈）；此平台社区走 802.11s + MLO，无 QSDK 依赖。
- **SQM Cake**：✗ 未找到该平台 SQM 专项帖；一般结论：10G 口应走硬件卸载（PPE/flowtable），Cake 不适合 10G 线速；若 WAN ≤1-2.5G（如 PPPoE 千兆），Cake 在 6.18 + 4 核 A53@1.3GHz 上可行但需实测。
- **Docker 上路由**：orangeyoo v1.1.0+ **预装 Moby/containerd/runc/docker-compose/Dockerman**，默认停止；2GB 内存够轻量容器；配合 6.18/2GB 是圈内常见玩法。
- **DPU/硬件卸载（PPPoE/NAT）在 OpenWrt 的现状（该平台）**：airoha 有 **PPE/Frame Engine**（主线侧：PPE MTU 修正 6/19、HW-GRO 6/16、LRO 5/25、GDM 回环 5/22）；社区侧 FlowSense 支持 **PPPoE/VLAN/AP 模式加速 + XFRM 流**，firewall4 软件/硬件 flow offload 默认开启（naoki66 README）。即：**PPPoE/NAT 硬件卸载在社区固件已可用（PPE 路径），主线仍在逐步吸收**；此为 2026 年最"激进"也最实用的面。
- **XR1710G 双万兆的定位**：2×10GbE（RTL8261BE，USXGMII C45 PHY phy5/phy8）+ 2×1GbE 内建 —— 在社区方案里充当 **10G 边界路由/旁路交换机**（XG-040G-MD 四口交换固件是先例）；已知坑：双 10G 同接 Web UI 失联（#247242, 2026-08-15）。

---

## 5. 盲区与预判（2026-08 → 2027-02）

按事实时间线外推，非保证：

1. **AN7581/7583 在稳定版出镜像（中概率）**：分支代码已含，若维护者将 airoha 加入 release 白名单，25.12.6+ 的 `releases/.../targets/airoha/an7581/` 将出现 → 监测点：downloads 目录。
2. **AN7583 设备放量（高概率）**：XG-040G-MF UBI 8/9 完成 + EVB 默认构建 7/18，暗示 Nokia 出货在即；后续大概率有新 dts 变体、恩山/洋垃圾渠道出现 XG-040G-MF。
3. **Linux 主线吸收 AN7581 驱动（中概率）**：multi-serdes/pinctrl 已回移上游（6/17、7/20）；若 DTS 上游化，Linux 6.19/6.20 期 `drivers/.../airoha` 与 `dts/airoha` 会出现 AN7581（当前仅 en7581）。
4. **MT7992 设备出现（中概率）**：mt76 2 月已支持 MT7992 variant，AN7581 EVB "Kite" 是现成载体；若出现 AN7581+MT7992 的量产机，"洋垃圾"价位会比 MT7996 版更低。
5. **社区固件主线化（高概率持续）**：naoki66 每日构建（↑sync 至 8/7）、orangeyoo v1.2.0 已跑 6.18.41 底座；dual-10G UI bug 若修复会对装机量有明显拉动。
6. **hostapd 2.12.x 点版本与安全公告**：2.12 ChangeLog 明确修了 EHT 报文 DoS，未来 2-3 个月内 OpenWrt 会跟 2.12.x 补丁 + 安全公告（现有 2026-1）。

---

## 6. 盯梢清单表

| # | 源 | URL / 命令 | 盯什么 | 建议频率 |
|---|---|---|---|---|
| 1 | git.openwrt.org cgit 日志（路径过滤） | https://git.openwrt.org/openwrt/openwrt/log/?h=main&path=target/linux/airoha | airoha 提交主题/作者/日期（已验证可用，含 "15 小时前" 级新鲜度） | 每日 |
| 2 | git.openwrt.org Atom（全库） | https://git.openwrt.org/openwrt/openwrt/atom/?h=main | 全库新提交（hostapd/内核 bump 等） | 每 2-3 日 |
| 3 | git 命令行（clone 端点已验证） | `git ls-remote https://git.openwrt.org/openwrt/openwrt.git main`；`git clone --filter=blob:none --no-checkout ...` 后 `git log --oneline --since="14 days ago" -- target/linux/airoha package/network/services/hostapd package/kernel/mt76` | 全路径定向日志（可脚本化进 CI） | 每日 CI |
| 4 | GitHub 镜像 API（openwrt/openwrt） | `https://api.github.com/repos/openwrt/openwrt/commits?path=target/linux/airoha&since=...` | 同上（未认证 60 次/时，注意配额） | 每日 |
| 5 | mt76（官方维护树镜像） | https://github.com/openwrt/mt76/commits ；API `commits?path=mt7996` | MT7996/MT7992 特性与修复（eMLSR/MLO/NPU） | 每日/隔日 |
| 6 | hostapd/wpa_supplicant 上游 | https://w1.fi/releases/ ；https://w1.fi/cgit/hostap/ | 2.12.x 点版本、EHT/MLO/安全提交 | 每周 |
| 7 | OpenWrt 论坛 #222776 | https://forum.openwrt.org/t/222776 | W1700K 实测/固件帖（3779 楼） | 每周 |
| 8 | OpenWrt 论坛 #247242 | https://forum.openwrt.org/t/247242 | XR1710G 同机、双 10G 问题 | 每周 |
| 9 | OpenWrt 论坛 #252504 | https://forum.openwrt.org/t/252504 | 社区 build 迭代 | 每周 |
| 10 | 论坛新帖发现 | https://forum.openwrt.org/search?q=XR1710G（search.json 限流 ⩽1 次/分） | 新主题 | 按需 |
| 11 | GitHub Releases（社区固件） | naoki66（每日）、orangeyoo（v1.2.0 pre）、hx801217（每日 00:00 编译）—— Watch→"Releases only" | 新固件/变更日志 | 通知驱动 |
| 12 | 恩山 | https://www.right.com.cn/forum/ | AN7581/XR1710G/W1700K/XG-040G 帖（需登录；本环境不可达 ✗） | 人工每周 |
| 13 | linux-wireless ML | https://lore.kernel.org/linux-wireless/（q=mt7996 搜索） | mt76 补丁终审/RFC | 每周 |
| 14 | 官方 snapshot 镜像 | https://downloads.openwrt.org/snapshots/targets/airoha/an7581/（+`profiles.json`） | 新设备/新镜像 | 每周 |
| 15 | 官方 release 目录 | https://downloads.openwrt.org/releases/ | **监测 25.12.x 是否出现 targets/airoha**（稳定版镜像信号） | 每发布周期 |
| 16 | 硬件资料库 | https://techinfodepot.shoutwiki.com/wiki/Brightspeed_XR1710G （FCC MXF-XR1710G） | 新机型资料 | 按需 |
| 17 | 中文社区 | blog.yazawaniko.com（XR1710G 上手，2026-06-21）；mobile01 f=110&t=7284929（开箱） | 中文圈动态 | 每周 |
| 18 | SDK 异动 | github.com/lotusmomo/airoha_sdk（★7，无 release，push 2026-05-13） | AN7581 官方/泄露 SDK 动向（来源待考证） | 每月 |

---

## 7. 方法与可信度备注

- 全部数据取自查证日 **2026-08-15** 的公开源实时快照（git.openwrt.org cgit、GitHub API/页面、w1.fi、downloads.openwrt.org、OpenWrt 论坛 JSON、DuckDuckGo lite、TechInfoDepot、社区 README/Release 页）。
- 标 ✗ 的条目（恩山、零售品牌采用、SQM 专项帖、Arcadyan/Sercomm 设备）为**未能确认**，未编造；标 △ 的推断（上游化、稳定版镜像）在文中以"监测点/概率"表述。
- 论坛 search API 与恩山均有访问限制：前者本环境 429 限流，后者 TLS 不可达——盯梢清单已给出替代路径（DDG site: 搜索、人工登录订阅）。
# 02 · 固件生态与支持状态

> 调研日期：2026-08-15（UTC）；信息截至 2026-08-15，所有结论标注日期；[来源] 可跳转。

## 0. 平台背景速览

| 项目 | 内容 | 来源 |
|---|---|---|
| SoC | Airoha AN7581GT（1.3GHz 4 核 + 8 核 NPU） | 恩山 tid-8465834、yazawaniko |
| Wi-Fi | MT7996AV BE19000；MT7976GN 2.4G 4×4 / MT7977BN 5G 4×4 / MT7977AN 6G 4×5 | 论坛 #247242 |
| 内存/闪存 | 2GB DDR4 / 512MB W25N04KVZEIR SPI NAND | PR #22397 |
| 网口 | 2×1G（内置 MT7530）+ 2×10G（RTL8261BE） | PR #22397 |
| 引导 | U-Boot 2014.04-rc1（2024-03-15）AXON 1.6，BMT/BBT 坏块管理 | PR #22397 |
| 行情 | 闲鱼约 ¥300–388（2026-06） | 恩山 tid-8465834 |

## 1. OpenWrt 主线状态

### 1.1 PR #22397（Gemtek XR1710G 支持，hurrian）
- **状态：open（2026-03-13 创建，4 commits，2026-08-15 仍 open，非 draft）**；peterwillcn 已 APPROVE
- commits（2026-03-11）：`airoha: split common dts/recipe for gemtek 17xx`、`uboot-airoha: reorder patches`、`uboot-airoha: add chainloader support for Gemtek XR1710G`、`airoha: add support for Brightspeed XR1710G`
- 评审要点：需补 MAC 布局说明（wan_mac@0x5000、lan_mac@0x6000）；RTL8261BE 用 `kmod-phy-rtl8261n` + reset 时序 200000/200000us（OEM 同款值）
- **实机验证已过**：IceblueSakura 2026-08-14 用 main（OpenWrt r35778，Linux 6.18.44，board gemtek,xr1710g-ubi）测通 U-Boot chainloader 引导
- 安装流程：串口 → tftpboot chainload-uboot.itb → flash write @0x600000 → bootcmd 指向 → 菜单 TFTP 加载 UBI 安装器

### 1.2 airoha target 历史与内核
- target 建立 2022-09-05；EN7581/AN7581 SoC 2024-10-20 引入，10-23 改名 an7581
- 内核演进：6.6 → 6.12（2025-09-25）→ **6.18（2026-06-04），现 6.18.44（2026-08-12）**
- **25.12 分支**：airoha 存在（kernel 6.12，subtargets en7523/an7581/an7583）但**不含 XR1710G/W1700K 设备**；chainloader 补丁以 PR #22294（[25.12]）2026-03 合入
- **W1700K 进主线：2026-03-10**（同日 an7581 去 source-only 进 buildbot）

### 1.3 snapshot 可构建性
- `downloads.openwrt.org/snapshots/targets/airoha/` 现役 **an7581 / an7583** two subtargets
- an7581 快照已产：`gemtek_w1700k-ubi-chainload-uboot.itb`、`-initramfs-recovery.itb`、`-squashfs-sysupgrade.itb`、EVB（eagle/kite）、Nokia Valyrian、Nokia XG-040G-MD 等；**尚无 gemtek_xr1710g 镜像**（PR 未合）

## 2. mt76 驱动状态（MT7996/AN7581）

- AN7581 Wi-Fi 走 mt7996 驱动 + **NPU 硬件卸载**（dts `mt7996@0,0` + an7581-npu-mt7996.dtsi）
- NPU 固件 `en7581_MT7996_npu_rv32.bin` + `…_npu_data.bin`，OpenWrt 打包经 **PR #22289（2026-03-06 合入）**
- mt76 里程碑：NPU 通用层 **2025-10-17**；`Enable NPU support for MT7996 devices` **2026-01-22**；后续 WED+NPU 队列修复（2026-07-23）、NPU/PPE 仅 MMIO（2026-07-20）
- **能力（2026-08-15）**：AP/STA/802.11s mesh 可用；6GHz/EHT320 可用（US 监管域、PSC ch37、理论 6G 4x5 320MHz ≈10Gbps+）；**MLO 驱动有支持但社区默认关闭**（回程用 802.11s）
- **已知缺陷/未完成**：
  - W1700K 6.6.103 时代 mt76_set_irq_mask/mt7996_debugfs_rx_log 崩溃（2025-09-09）
  - **CVE-2025-68360**（2025-12-24）：mt76 WED 回调误用主 wed 设备，6GHz 链路开硬件卸载可致内核崩溃——对本项目 6GHz offload 验收直接相关
  - 恩山 2026-03-26：当时"最新版本硬件加速失效；有加速的版本随机 1Mbps 异常需重启"；**2026-06-20 回帖称"现在基本没有 bug 了"**（驱动快速收敛证据）
  - 重载/重启偶发 SAE 短暂失败与 mesh 重连（可恢复）

## 3. U-Boot / 引导链

- 厂商 U-Boot：2014.04-rc1（2024-03-15）AXON 1.6；bootcmd 只跑签名镜像但**可从 flash 直接 bootm 非签名镜像**（chainloader 突破口）；串口任意键可中断
- 上游 u-boot 含 `arch/arm/mach-airoha/an7581` + `an7581_evb_defconfig`（EVB 板，非 17xx）
- OpenWrt 包 `package/boot/uboot-airoha`（PKG_VERSION **2026.07**）带 W1700K patch、AN7583、Nokia 系、**chainloader 支持**
- **UBI 安装器**：hurrian/w1700k-ubi-installer（2026-03-04 建仓，dangowrt/owrt-ubi-installer 派生）；XR1710G 自 **2026.03.13-rev2** 支持，正式版 **2026.04.25**；另有 w1700k/ubi2-installer v2.0（2026-04-28）
- **YYH2913/http-uboot**：定制 U-Boot（10GbE、内置 DHCP、**HTTP 恢复页 192.168.255.1**、长按 reset 进恢复），恩山 2026-03-07 起广泛使用，社区刷坏后主要恢复入口

## 4. 社区构建

- **OpenWrt 论坛 #252504（orangeyoo，2026-08-07）**：AN7581+MT7996、6GHz 802.11s Mesh/EHT320、iStoreOS 风格 LuCI、U-Boot；Linux 6.18.38、mt76 b2704cf5；默认 192.168.50.1；6GHz 单跳回程（US/ch37/EHT320/WPA3-SAE），MLO 默认关；含 iStore/OpenClash、无线/Mesh/温度/NPU 诊断；2 台实机跨楼层 mesh ESTAB、tx failed=0、52.6/56.7°C；Pre-release
- **恩山 tid-8484444（2026.08.14，lhc87227 = orangeyoo 系列）**：v1.2.0 基于 Linux 6.18.41 + mt76 b2704cf5 + hostapd f08f2749（2026-07-09）；刷机=sysupgrade 或 YYH U-Boot "Firmware + UBI 2.0" 上传 ITB；三频请求功率 28/29/28dBm；5G US/ch36/EHT80；6G ch37/EHT320 SAE 默认关；Docker（Moby）预装默认关；NPU 延迟探测/PPE 修正等
- **恩山 tid-8465834（2026-03-07 起）**：硬件/FCC/拆机、行情、XR1710G vs W1700K 差异、驱动 bug 演进（2026-03→06）、YYH U-Boot 教程
- **iStoreOS 官方：未收录**（storeos_hardware.html 无 XR1710G/W1700K/AN7581/MT7996，2026-08-15 检查）
- 其他构建：naoki66/ImmortalWrt-for-Gemtek-XR1710G（2026-06-30 建仓，★86，每日/隔日 release，kernel 6.18.41，luci-app-airoha-npu/flowsense/fancontrol/recovery）；jjcszxh 镜像系；hx801217/iStoreOS-for-Gemtek-XR1710G（★21，每日定时编译）
- 聚合帖：**Forum #249319 Gemtek W1700K Community Builds**（2026-04-21 起，417 帖）

## 5. 厂商固件（Brightspeed / Quantum Fiber）

- W1700K 原厂 = **定制 OpenWrt v21.02.1**（Airoha SDK）；实例版本 WXK001-05.00.30.02
- XR1710G vs W1700K 差异：XR1710G 砍 Silabs BT/Zigbee + Airoha GPS；10G PHY RTL8261BE（W1700K=RTL8261N）；千兆 LED 改由 switch 驱动（"LED 状态相反"坑）
- **无公开官方固件下载直链**（截至 2026-08-15）；云端托管机制（TR-069/自研 app/遥测）**未能确认**；厂商固件价值 = eeprom/factory 校准数据 + BMT/BBT 布局参考
- **无公开"提取/降级漏洞"**（无 CVE/PoC）——社区实际利用的是引导链缺陷（U-Boot 可 bootm 非签名镜像），属"改引导而非破解固件"

## 6. 刷机 / 救砖路径

1. **串口刷机（官方路径）**：T10 拆机 → UART（TX-GND-VCC-N/A-RX）→ 中断 → 写 chainloader → 菜单
2. **UBI 安装器**：menu "4. Boot installer via TFTP" → 自动 UBI 2.0 迁移；已有布局会问覆盖（yes 格式化全盘）
3. **HTTP U-Boot 恢复**：YYH http-uboot → 192.168.255.1 网页刷机/恢复（主要救砖入口）
4. **snapshot recovery.itb**：U-Boot 菜单 "3. Boot recovery system from flash"
5. **已知案例**：W1701K 用户 TTL 进 chainloader 菜单后 tftpboot 网口驱动失败（ARP retry exceeded，2026-07-05，等待更新）；刷 W1700K 包导致 XR1710G LED 反（提示用专属包）；**警告：不要把系统 ITB 或裸 u-boot.bin 刷进 U-Boot 槽位**
6. **NAND 编程器救砖：未能确认**公开教程（W25N04KV；BMT/BBT 依赖，直写需复刻 chainloader 布局，风险自负）

## 7. 已知问题与安全

### CVE / 驱动安全
- **CVE-2025-68360**（2025-12-24，mt76）：WED 回调误用主 wed 设备，wed_hif2（6GHz 链路）+硬件卸载崩溃 → 6GHz offload 验收必须回归
- **CVE-2025-22061**（2025-04-16，net: airoha）：HTB offload 叶子删除 qid 上报错误（kernel warning，非远程利用）
- NVD "mt7996" 命中 24 条 CVE，多为 mt76 越界/空指针修复（2024-35909/38563/47681/47714、2025-38156/38281/38316/38343/38599、2023-53203 等）；rtl8261 0 条；**无面向本机固件本身的公开 CVE**
- 社区已知缺陷见 §2（均已逐步修复）

### 6GHz 法规（中国市场关键约束）
- **中国未向 WLAN 开放 6GHz**：6425–7125MHz 划归 IMT；**2026-05-08 工信部批复 6GHz 用于 6G 技术试验** → 中国大陆 XR1710G 合法只能跑 2.4/5GHz；**6GHz 802.11s 回程属无授权使用**（社区以 US 监管域 + 低功率固定信道自用）
- **恩山 iStoreOS 帖的 6GHz 回程优化手法**：①6GHz 专属 802.11s 单跳回程，不做 MLO；②两节点统一 Mesh ID + WPA3-SAE + 监管域 + PSC ch37 + EHT320；③客户端交 5GHz（US ch36 EHT80、29dBm）与 2.4G；三频请求功率 28/29/28dBm；④稳定化：max_inactivity=86400、disassoc_low_ack=0、performance governor、NPU 延迟探测（默认 WAN DNS）；⑤验收：tx failed=0、mesh ESTAB、无 UBI/I/O 错误、无 airtime_link_metric_get 报错、温度 52–57°C

## 8. 生态状态速览表（2026-08-15）

| 条目 | 状态 | 日期 |
|---|---|---|
| PR #22397 XR1710G 主线 | open（approved、实机验证过） | 2026-03-13 / 08-14 验证 |
| airoha target | 2022 建立；AN7581 2024-10；W1700K 2026-03-10 主线 | — |
| 当前内核 | main=6.18.44；25.12=6.12 | 2026-08-12 |
| snapshot | an7581/an7583 出镜像；**有 W1700K、无 XR1710G** | 2026-08-15 |
| mt76 AN7581 | NPU 层 2025-10；Enable NPU 2026-01；固件打包 2026-03 | — |
| mt76 能力 | AP/STA/mesh ✓；6G/EHT320 ✓；MLO 部分、默认关 | 2026-08 |
| U-Boot | 上游含 AN7581 EVB；uboot-airoha 2026.07 含 chainloader | 2026-07 |
| UBI 安装器 | XR1710G 自 2026.03.13-rev2；正式 2026.04.25 | — |
| 社区构建 | orangeyoo v1.2.0（6.18.41 08-14）；naoki66 ImmortalWrt 每日 | 2026-08 |
| iStoreOS 官方 | **未收录** | 2026-08-15 |
| 6GHz（中国） | 无法规支持；社区 US 域自用 | 2026-05-08 批复 |
| 厂商固件 | W1700K=定制 21.02.1；无公开下载 | — |
| 安全 | 无设备级 CVE；驱动 CVE-2025-68360/22061 | 2025-12 / 2025-04 |

### 一句话结论
XR1710G 处于**社区先行、主线收尾**的快速演进期：硬件被 W1700K 生态完全吃透，刷机/救砖体系（serial→chainloader→UBI→HTTP U-Boot）成熟，6GHz 802.11s 回程已被多个 6.18 社区构建跑稳；进主线只差 PR #22397 合并。注意：中国 6GHz 未开放、MLO 不成熟、厂商固件/云端资料无公开细节（未能确认）。
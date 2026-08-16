# 01 · XR1710G 硬件考据

> 调研日期：2026-08-15；所有事实标注来源与日期；无法核实处明确写"未能确认"，不编造。

## 0. 关键参数速查表

| 项目 | 结论 |
|---|---|
| 机型/品牌 | Gemtek XR1710G，运营商品牌 Brightspeed（美国）[来源: TechInfoDepot] |
| FCC ID | MXF-XR1710G（Gemtek Technology），首次获证 2024-04-19 [来源: fccid.io] |
| SoC | Airoha **AN7581GT**：四核 ARM Cortex-A53 @1.3GHz + 8 核 RISC-V NPU [来源: Airoha 官网 / OpenWrt target.mk / 恩山] |
| 内存 | 2GB DDR4-2666（2×1GB 颗粒；ESMT M16U8G16512A 或 Micron MT40A512M16TB，见存疑清单） |
| 闪存 | 512MB SPI NAND，Winbond W25N04KVZEIR [来源: PR #22397] |
| 网口 | 2× 10GBASE-T RJ45（WAN/LAN1+LAN2，Realtek RTL8261BE PHY）+ 2× 1G RJ45（SoC 内置 MT7530 交换） |
| Wi-Fi | MediaTek **MT7996AV** 三频 BE19000；配套 MT7976GN（2.4G 4×4）/ MT7977BN（5G 4×4）/ MT7977AN（6G 4×4+1） |
| USB / WPS / SFP+ | 均无（SoC 有 USB 控制器但板级未引出） |
| 电源 | 12V / 5A DC 圆头 |
| Bootloader | U-Boot 2014.04-rc1（2024-03-15）AXON 1.6；签名启动；串口可中断 | 
| 同平台 | Gemtek W1700K / W1701K、Nokia XG-040G-MD、Nokia Valyrian、AN7581 EVB（Eagle/Kite）等 |

## 1. SoC：Airoha AN7581

- **官方定位**：10G-PON SoC，"金三角"= CPU + NPU + 智能包加速器；单芯片承载 WAN/WLAN/LAN，最高 **30Gbps L7 处理**、最多 4×10G 或 5×2.5G 以太口；软件平台支持 OpenWrt/RDK-B/prplOS [来源: airoha.com 产品页]
- **CPU**：四核 Cortex-A53 r0p4（OpenWrt target.mk `CPU_TYPE:=cortex-a53`；实机 MIDR 0x410fd034），GT 型号 1.3GHz（第三方汇总，官方 datasheet 未公开——见存疑清单）
- **NPU**：8 核 RISC-V 网络处理器 + 硬件包加速；DTS 节点 `airoha,en7581-npu` @0x1E900000，保留内存 npu-binary 10MiB / npu-pkt 45MiB；启动日志 `NPU fw version: 0.1111`；NPU 固件按 Wi-Fi 前端区分（MT7996 用 `en7581_MT7996_npu_rv32.bin`，MT7992 用 `en7581_npu_rv32.bin`）[来源: OpenWrt dts / PR #22289]
- **PCIe**：3 个控制器；本机 PCIe0 以 x2 挂 MT7996（dts `airoha,x2-mode`）[来源: PR #22397 dts]
- **交换机**：内置千兆交换块 `airoha,en7581-switch`（内核日志 mt7530-mmio），含 2 个 GbE PHY
- **硬件 NAT/卸载能力**：NPU 转发实测 **10Gbps**（2026-04-03）；10G 以太↔Wi-Fi offload 下 iperf3 1.1–1.4Gbps、CPU 0–1%（2026-03-22）[来源: 论坛 #247242]；**PPPoE 硬件卸载：未能确认**（社区 FlowSense 声称支持，但无直接实测文档）
- **AN7581 变体**（玩家汇总，非官方）：ST 2.4G 双核 / CT 900M 四核 / DT 1.2G 四核+4核NPU / **GT 1.3G 四核+8核NPU（本机）** / PT 1.4G 四核+8核NPU [来源: yazawaniko 博客]

## 2. 射频方案（MT7996 Wi-Fi 7）

- **MT7996AV** = MediaTek "Filogic 680" 级 Wi-Fi 7 芯片：三频 2.4/5/6GHz、每频 4×4、**EHT320（6GHz 320MHz）**、4096-QAM
- 整机 **BE19000**：2.4G 4SS@40M 1376Mbps / 5G 4SS@160M ≈5765Mbps / 6G 4SS@320M ≈11530Mbps
- 外置 FEM 具体型号：未能确认（MT7976/7977 系列本身含射频前端）
- 天线：内置，MHF4/U.FL，三频合计约 13 根（4+4+5，6GHz 口径 4×4+1 为玩家说法，TechInfoDepot 记 4×4:4——存疑清单）

## 3. 接口与外壳

- 端口：**2×10GBASE-T RJ45**（wan=GDM2、lan2=GDM4，均 USXGMII）+ **2×1G RJ45**（lan3/lan4）；无 SFP+/USB/WPS；1 个复位键
- LED：正面 1 颗四色 RGBW 状态灯（GPIO 17/19/29/20）+ 两个千兆口绿/琥珀双色（switch LED 控制）；无 LED 矩阵
- 风扇：板载 Sunon 风扇（installer 里 `fan_id=sunon_XR1710G`），Nuvoton 监控/控制（NCT7802 vs NCT7511Y 存疑）
- 拆解：白/灰双层卡扣外壳，背贴下有 **Torx T10 螺丝**；FCC 内部照片可作官方拆机图 [fccid.io/MXF-XR1710G]

## 4. 存储 / 引导

- 出厂分区（TTL 实测）：`2MiB bootloader / 2MiB uenv / 2MiB dsd / 64MiB tclinux / 64MiB tclinux_slave / 312MiB system / 66MiB reserved_bmt`；UBI 化后：`vendor 6MiB / chainloader 1MiB / ubi（439–503MiB）/ reserved_bmt`
- **U-Boot 带签名校验**（"default bootcmd will only run a signed image"、`Secure key exist`），但**串口不锁**：任意键中断，`flash write/tftpboot/bootm` 可用；采用 BMT/BBT 坏块管理，原厂 U-Boot 不支持 UBI → 社区用 **U-Boot Chainloader**（新 U-Boot 放 kernel 槽，从 UBI 加载 FIT）
- 社区 **YYH2913/http-uboot-xr1710g**：替换 bootloader 槽的定制 U-Boot，带 Web 刷机/恢复（`http://192.168.255.1`）、DHCP、10G 口支持、长按 reset 进恢复

## 5. 认证

- FCC MXF-XR1710G：原设备 2024-04-19，C2PC 2024-05-30，越南制造；Wi-Fi 7 Router / 6GHz Low Power Indoor AP
- 同源：MXF-W1700K（2023-10-06）、MXF-W1701K（2025-04）
- **CMIIT：未能检索到**（美国运营商机型，无中国核准记录）；机身背贴只有 Wi-Fi 6 认证标识

## 6. 同平台设备（AN7581 生态）

| 设备 | 差异 | OpenWrt 状态 |
|---|---|---|
| **Gemtek W1700K**（Quantum Fiber） | 带 BT/Zigbee+GPS；10G PHY RTL8261N；AXON 2.0 | **已进主线**（gemtek_w1700k-ubi，快照镜像） |
| **Gemtek XR1710G**（本机） | 砍 BT/GPS；RTL8261BE；千兆 LED 走 switch；AXON 1.6 | PR #22397 未合并（2026-08-15 open） |
| Gemtek W1701K（Quantum Fiber 无线 Pod） | AN7581+MT7996AV；2×2.5G（EN8811H） | PR #20430 open |
| Nokia XG-040G-MD（ONU） | 配 EN8811H 2.5G PHY、USB3 | 官方快照已出 |
| Nokia Valyrian | SFP+、eMMC、USB3、MT7996 | 官方快照已出 |
| AN7581 EVB（Eagle/Kite） | Eagle=MT7996、Kite=MT7992，eMMC 启动 | 官方快照已出 |
| 同家族 SoC | AN7566/AN7551（同 cortex-a53）；**AN7583**（新 SoC，XG-040G-MF） | AN7583 2026-05 入主线 |
| 零售路由器 | **未能确认**任何消费级 AN7581 零售机型 | — |

> 注：OpenWrt ToH 明确 "XR1710G **is not a clone** of the W1700K"（硬件有差异），与"同源"不矛盾，但不能当完全同型号刷。

## 7. 价格与货源（2025–2026 行情）

- 2025-01：W1700K 曾有 $36 捡漏价；2026-06：XR1710G 入手约 400 元且"进价低得离谱"；2026-07：闲鱼全新 ¥350–388（约 USD58），据称新加坡数千台整批流出（Lumen 处置计划）；Quantum Fiber 2025 年被售给 AT&T 后大量流通
- 结论：**约 ¥388 市价属实**（2026 年中 ¥350–400 区间）

## 8. 串口 / 调试

- **5 针 UART**：顺序 `TX – GND – VCC – N/A – RX`（**勿接 VCC**，3.3V），主板左下角；**可不拆盖**用 spider 测试板够到
- **115200 8N1**，无流控，console=ttyS0
- 可刷机性：完全可——任意键中断 → TFTP + `flash write` 写 chainloader → U-Boot 菜单 → UBI 安装器；或免拆刷 YYH http-uboot（见 4）
- JTAG：OpenWrt 维基称存在通用 JTAG，本机针位照片缺失，未能确认

## 9. 未确认 / 有争议事实

1. AN7581 主频/CPU 型号无官方公开 datasheet（1.3GHz/A53 来自 target.mk、DTS、U-Boot 自报，可信度高）
2. 内存颗粒型号两说（ESMT vs Micron，可能批次差异）
3. 风扇温控芯片（NCT7802 vs NCT7511Y 共存关系未清）
4. 6GHz 天线数口径（4×4+1 vs 4×4:4）
5. AN7581 变体参数表仅玩家汇总为证
6. **PPPoE 硬件卸载无直接实测**（仅官方宣传 + 路由转发 10Gbps 实测）
7. Wi-Fi 7 Alliance 认证状态存疑（背贴仅 Wi-Fi 6）
8. XR1710G vs W1700K 出厂分区细节差异未完全厘清
9. XG2010G 是否 AN7581 平台仅恩山一条回帖
10. Nokia Valyrian 真实市场型号未确认
11. 恩山原始帖正文因反爬部分只能引 Wayback 存档
12. MT7976/7977 系列无公开 datasheet（PA 增益/TX power 表等）

## 附：主要来源

- Airoha 官方：https://www.airoha.com/products/p/NpfqGLnZiZuYUZ6N 、https://www.airoha.com/products/p/zRV6ssXbhlCIYyNl
- FCC：https://fccid.io/MXF-XR1710G 、https://fccid.io/MXF-W1700K 、https://fccid.io/MXF-W1701K
- OpenWrt：https://openwrt.org/toh/gemtek/mxf-w1700k 、snapshots/airoha/an7581 、PR #17869/#20430/#22397
- 论坛：https://forum.openwrt.org/t/quantum-fiber-w1700k-support/222776 、https://forum.openwrt.org/t/brightspeed-xr1710g-same-device-as-the-w1700k/247242 、https://forum.openwrt.org/t/quantum-fiber-w1701k-support/239692
- 拆机/实测：https://hungvu.tech/quantum-fiber-w1700k-teardown-board-view-and-uart-pins/ 、https://techinfodepot.shoutwiki.com/wiki/Brightspeed_XR1710G 、https://blog.yazawaniko.com/index.php/archives/336/ 、恩山 tid-8465834（Wayback 2026-05-08）
- 运营商：quantumfiber.com Wi-Fi 7 用户指南（Wayback 2024-11-27）、en.wikipedia.org/wiki/Brightspeed
- 刷机：https://github.com/hurrian/w1700k-ubi-installer 、https://github.com/YYH2913/http-uboot-xr1710g
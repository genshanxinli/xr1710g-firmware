# XR1710G 救砖标准操作流程（SOP）

> 文档状态：**草稿 v0.1**（M0 交付物，人类最小集配套文档；在 v0 基础上按交付结构重组并补全）。
> 撰写/修订：2026-08-16。
> 读者画像：**有 UART 电烙铁 + 网线 + 耐心**的人类最小集操作者——拆机、UART 飞线、编程器救砖、真机刷写按键只能人做；AI 只代劳决策辅助与命令序列准备（选路径、校 SHA256、逐条给指令、核对日志）（CONTEXT「人类最小集」「救砖」）。
> 引用记号：`[01§4]`＝报告 01 第 4 节；`[02§1.1]`＝报告 02 第 1.1 节；`[04§1]`＝报告 04 第 1 节；[YYH]＝YYH2913/http-uboot 仓库 README（链接见 §12，上一版草稿 2026-08-16 抓取核验，**本轮未联网复核**）；[HURR]＝hurrian/w1700k-ubi-installer README（同上）。
> 凡报告（01/02/04）未载、仅凭 [YYH]/[HURR] 或推算得出的内容，一律标 **待实机验证**；不编造。

---

## 0. 一句话总纲与判定顺序

**救砖 = 先把"还有哪个入口活着"看清楚，再从最轻的档开始救。**

| 档位 | 入口现状 | 主流程 |
|---|---|---|
| **① T1** | 系统能启动但异常（能进 LuCI/SSH） | Web/sysupgrade 回退（§3） |
| **② T2** | 起不来，但**串口有输出、任意键可中断**（厂商 U-Boot 或 chainloader 菜单） | 串口 115200 8N1 → tftpboot chainload-uboot.itb → flash write @0x600000 → bootcmd 指向 → 菜单 TFTP 加载 UBI 安装器（§5） |
| **③ T3** | 无串口条件，但**仅剩 YYH http-uboot 恢复页**（10G 口 LED 起闪 + 长按 reset 出恢复灯效） | 免拆机 `http://192.168.255.1` 恢复页（§6） |
| **④ T4** | 完全无引导（无串口、无恢复页、无灯效） | NAND 编程器（§7；公开教程**未能确认**，风险自负） |

判定顺序：**T1 → T2 → T3 → T4**（由轻到重）。实操快捷原则：同时具备串口与 YYH 恢复页时，**优先 YYH 恢复页（免拆机）**；档位编号仍以损坏程度为准。
每台机器遵循 **一机一路线**（YYH 或 upstream chainloader，互不叠加；互刷边界以 M0 实机实验为准，见 §9）[CONTEXT]。

**核心红线（先读这个，全文最显眼的禁令）**：任何情况下**不要把系统 ITB 或裸 `u-boot.bin` 写进 chainloader/U-Boot 槽位**（风险 R1 [04§1]）；**不要刷 W1700K 等非本机包**（LED 反 / 布局差异，风险 R2 [02§6 path5][04§1]）。破坏 U-Boot 槽 = 破坏恢复入口本身，只能掉到最慢最险的编程器路径（T4）。

---

## 1. 危险红区表（do-not-do，后果分级）

> 按后果从重到轻排序：🔴 致命（大概率只能编程器兜底或资产永久丢失）→ 🟠 高危（可救但费时费力 / 资产不可逆丢失）→ 🟡 中（可返工，不算变砖升级）。

| # | 禁止动作 | 后果分级 | 后果 | 依据 |
|---|---|---|---|---|
| RD-1 | 把**系统 ITB / 裸 `u-boot.bin`** 写进 chainloader/U-Boot 槽位 | 🔴 致命 | R1 高危变砖，且砸掉恢复入口本身 → 只剩编程器（T4） | [04§1][02§6 path5 警告] |
| RD-2 | 恢复页上传 `u-boot.bin` / `u-boot.img` / `xr1710g-ubi.img` | 🔴 致命 | 同上——无 Linux 头包装（shim+FIT 双入口），厂商 bootm 链不认 | [YYH] |
| RD-3 | 刷 **W1700K 等非本机包**（sysupgrade / installer / chainloader 镜像）到 XR1710G | 🟠 高危 | R2：LED 反（千兆 LED 走 switch 差异 [01§6]）、UBI 布局差异；OpenWrt ToH 明言 "is not a clone" [01§6] | [02§6 path5][04§1 R2][01§6] |
| RD-4 | 用 `sysupgrade` 写 U-Boot/chainloader 槽（sysupgrade 不是写引导槽的工具） | 🟠 高危 | 走错写入路径，落入 RD-1 后果 | [YYH] |
| RD-5 | 整槽覆盖 64MiB `tclinux`（刷链只允许动**头 1MiB**） | 🟠 高危 | 破坏槽位/布局；旧布局下 YYH 只占 tclinux 头 1MiB | [YYH] |
| RD-8 | 未备份就刷（任何槽位） | 🟠 高危 | 原厂固件无公开下载直链 [02§5]——备份即唯一原厂资产，丢备份=永久丢失 | [02§5][04§1 R1] |
| RD-9 | 安装器提示 `Existing UBI layout detected ... overwrite?` 时未确认备份就 yes | 🟠 高危 | yes = 格式化全盘（UBI 2.0 迁移），老系统/未备份分区被抹 | [02§6 path2][04§1 R2] |
| RD-6 | 恢复页布局选择器与镜像 FDT 的 `ubi` reg 不符就刷 | 🟡 中 | Linux 卡 `not enough PEBs` / `Waiting for root device /dev/fit0`；可重进恢复页返工，不算变砖升级 | [YYH] |
| RD-7 | 一台机器混装 YYH + upstream chainloader（两条路线叠加） | 🟡 中 | 违反一机一路线；互刷边界未定，回退顺序不可预期 | CONTEXT「一机一路线」 |

> 全部红区的共性源头：[04§1] R1（刷错槽位）与 R2（UBI 布局破坏）。动手前过一遍本表 + §11 命令核对表。

---

## 2. 通用前置：串口与备份【人类】

**任何**刷机/救砖动作前完成（这也是 M0 必做项 [04§2]）：

1. **串口就绪**（T2 必需，T1/T3 建议）：5 针 UART 顺序 `TX – GND – VCC – N/A – RX`，**勿接 VCC**（3.3V）；115200 8N1 无流控 [01§8]。不拆盖可用 spider 板够到 [01§8]。
2. **备份**（旧布局分区名；UBI 化后为 `vendor/chainloader/ubi/reserved_bmt` [01§4]）：

```sh
cat /proc/mtd                      # 以真机为准记分区号（分区表见 §10 核对表 #3）
# 逐个分区全量备份（512MB 全量约分钟级；备份即原厂唯一资产 [02§5]）
#   nanddump -f /tmp/mtd<N>_<name>.bin /dev/mtd<N>
# 最小必要 ①：新布局 chainloader 槽头 1MiB
nanddump -l 0x100000 -f /tmp/chainloader-slot-1m.bin /dev/mtd<chainloader分区号>
# 最小必要 ②：旧布局 tclinux 头 1MiB（上一版草稿记 /dev/mtd5，分区号待实机验证）
nanddump -l 0x100000 -f /tmp/tclinux-head-1m.bin /dev/mtd5
```

> 预期：`nanddump` 完成、备份文件 SHA256 记录在案。异常：出现读坏块报错 → 记录（BMT/BBT 管理下属正常现象 [01§4]），不中断。
> 备份文件同时是 YYH 自行构建的参考镜像（打包清单中的 `mtd5_tclinux.bin`）[YYH]——**先备份再动手**。

---

## 3. 档位 ① T1：系统可启动但异常 → Web/sysupgrade 回退

**判定**：能进 LuCI/SSH（任一口）、能重启、能执行 sysupgrade —— 属"可启动但异常"（如无线挂、LED 反、某功能不可用）。
**依据**：社区刷机= sysupgrade 或 YYH 恢复页传 ITB [02§4]；事件驱动构建留档可回滚 [04§1 R7]。

1. 【AI 可代劳】确认当前版本与**上一个正常留档版本**并存档镜像（构建留档可回滚 [04§1 R7]）；校验 SHA256 与来源。预期：有可回退镜像。异常：无留档 → 只能重刷（跳 T2/T3），记入实验报告。
2. 【人类】备份当前配置与日志（`/etc/config`、`dmesg`、`logread`）。
3. 【人类】执行 sysupgrade（不保留配置排障更干净；也可保留配置重试）：

```sh
sysupgrade -n openwrt-<target>-<device>-sysupgrade.itb
```

> 预期：进度条 → 自动重启 → 进新系统。异常：升级中掉电 → 按重启结果落 T2/T3；"无法执行 sysupgrade"（版本校验失败/缺组件）→ 改走 LuCI「刷写固件」或降级 T2。
> ⚠️ 本档只刷系统，**不碰 U-Boot/chainloader 槽**（RD-4）。

4. 【人类】验证：开机日志无 UBI/I/O 错误、`tx failed=0` 类指标干净（参考 [02§7]）、三频无线/双 10G/LED 符合预期。
> 预期：症状消失或缓解。异常：回退到上一个正常版本后症状依旧 → **停止反复刷写**，记录并升级为实验问题（不归本 SOP 兜底）。

---

## 4. 档位 ② T2：U-Boot 可中断 → 串口链路恢复

**判定**：无系统，但串口 115200 8N1 上电有输出、任意键可中断，出现 ECNT/AXON prompt（`ver=U-Boot 2014.04-rc1 ... AXON 1.6`）[01§0][01§4][02§0]。
**目标**：把 chainloader 槽镜像写进 **kernel 槽 @0x600000**（新布局 `chainloader` 分区 / 旧布局 `tclinux` 头 1MiB —— 同一物理偏移，见 §10 核对表 #5）[01§4][02§1.1]。
**完整流程**（核心序列 [02§1.1] + 命令形态 [HURR]/[YYH]，逐条待实机验证）：

```sh
# 0)【人类】T10 拆机 [01§3] → UART 接线 TX–GND–N/A–RX（勿接 VCC）[01§8] → 115200 8N1 [01§8]
#    预期：串口见 U-Boot 输出；异常：无输出 → 查接线/电平/是否误接 VCC
# 1)【人类】上电后立刻任意键中断
#    预期：ECNT/AXON prompt；异常：拦不住 → 回车连发尽早按，仍不行检查波特率

# 2)【AI 可代劳】网络与 TFTP（PC 静态 IP；镜像放 TFTP 根目录）
setenv serverip 192.168.1.10
setenv ipaddr 192.168.1.1
tftpboot 0x89000000 openwrt-airoha-an7581-gemtek_xr1710g-ubi-chainload-uboot.itb
#    预期：TFTP 进度条并完成；异常：ARP retry exceeded/超时 → 换口（10G↔1G）重试、
#          核对 serverip/掩码（W1701K 曾现网口驱动失败案例 [02§6 path5]）
#    镜像名：XR1710G 专属文件名以 PR #22397 产物为准；2026-08-15 快照尚无 XR1710G 镜像 [02§1.3]

# 3)【AI 可代劳】写 kernel 槽 @0x600000，长度 1MiB
#    （0x600000 = 6MiB：bootloader 0–2 / uenv 2–4 / dsd 4–6 / tclinux 6MiB 起 [01§4]；02§1.1 明文 flash write @0x600000）
flash erase 0x600000 0x100000
flash write 0x600000 0x100000 0x89000000
#    预期：erase/write 完成、无坏块中断；异常：bootm 时打印 Wrong Image Format →
#          槽没写对或偏移错（见 §10 核对表 #7 的 0x602100 说明）

# 4)【AI 可代劳】bootcmd 指向 chainloader（三选一，与槽镜像形态匹配 [YYH]；具体哪式适用见 §7.4）
setenv bootcmd 'flash read 0x600000 0x100000 $loadaddr; bootm'
# 或 setenv bootcmd 'flash read 0x602100 0x100000 $loadaddr; bootm 0x81800000'
# 或 setenv bootcmd 'flash read 0x600000 0x100000 $loadaddr; bootm 0x81802100'
saveenv

# 5)【人类】reset
#    预期：进 U-Boot Boot Menu（1 Run default / 2 Boot system via TFTP /
#          3 Boot recovery system from flash / 4 Boot installer via TFTP / 5 Reboot / 0 Exit）[02§6 path2][HURR]
#    异常：Wrong Image Format → 回步骤 3/4 核对偏移与 bootcmd

# 6)【AI 可代劳】菜单选 4 → TFTP 加载 UBI 安装器
#    XR1710G 支持自 2026.03.13-rev2，正式版 2026.04.25 [02§3]
#    提示 "Existing UBI layout detected. Proceed and overwrite? (yes/no)" → 确认备份过再 yes
#    （yes = 格式化全盘、UBI 2.0 迁移 [02§6 path2]；RD-9）
#    预期：自动 UBI 2.0 迁移 → 安装完成重启进 OpenWrt；异常：卡住/网口失败 → 记录、换口换镜像
```

**可选快捷路径**：菜单 **3. Boot recovery system from flash** —— 仅当 recovery 镜像已预先落盘（snapshot `*-initramfs-recovery.itb`；W1700K 已有此产物 [02§1.3]）。recovery 镜像的**落盘机制报告未载 → 待实机验证**，此路径排序靠后 [02§6 path4]。

**自检命令**（写后核对双入口魔数，[YYH] + 待实机验证）：

```sh
flash read 0x600000 0x100 0x81800000; md.b 0x81800000 0x20   # 应见 27 05 19 56（legacy 前缀 shim）
# 或：flash read 0x602100 0x4000000 $loadaddr; bootm           # 应见 d0 0d fe ed（chainloader FIT）
```

**刷什么文件（镜像选择，R1 红线）**：

| 目标 | 要写的文件 | 来源/状态 |
|---|---|---|
| 装 upstream chainloader | `gemtek_xr1710g-ubi-chainload-uboot.itb`（对应 W1700K 的 `gemtek_w1700k-ubi-chainload-uboot.itb` [02§1.3]） | PR #22397 合入出快照后才有；2026-08-15 **尚无** [02§1.3] |
| 装/回刷 YYH | `out/xr1710g-chainloader-slot.bin`（或归档 `*xr1710g-uboot-v2026.07-59060dde-flash-slot.bin`）[YYH] | YYH 仓库构建产物，**待复核**（§7.2） |
| ❌ 禁止 | 裸 `u-boot.bin`、`u-boot.img`、系统 ITB、`xr1710g-ubi.img` | [YYH][04§1 R1]——厂商 bootm 链不认裸 U-Boot，必须有 shim+FIT 包装 [YYH] |

---

## 5. 档位 ③ T3：仅剩 YYH http-uboot → 恢复页（免拆机）

**判定**：串口没条件（或未接），但 10G 口 LED 起闪、长按 reset 出恢复灯效、`http://192.168.255.1` 打得开。
**前提**：本机**已装 YYH http-uboot**；若从未装过 YYH 而恢复页打不开，属正常 → 落档位 T2 [01§4][02§3]。

1. 【人类】PC 网线接 **10G 口**；NIC 设 **DHCP**（YYH 内置 DHCP server 自动分配）[02§3][YYH]。
   > 预期：10G 口 LED 起闪。异常：不闪 → 多为未装 YYH 或链路问题 → 回 §0 重判档位。
   > 静态 IP 细节 README 未载【待实机验证】；如必须手动，建议网段 `192.168.255.x/24`（与恢复地址同网段），真机回填确认。
2. 【人类】上电后等 10G 口 LED 起闪 → **长按 reset** → 状态 LED 由**常红变为流动恢复灯效**后松手 [YYH]。
   > 预期：出现流动灯效。异常：灯效长期不现 → 多等几秒/重新长按（YYH 时序余量较大 [YYH]）；仍无 → 回判档位。
3. 【人类/可代劳】浏览器开 `http://192.168.255.1` [01§4][02§3]。
   > 预期：恢复页加载。异常：打不开 → 查 10G 口/DHCP/防火墙；确认 YYH 已装。
4. 【AI 可代劳】选 **`firmware`** 目标，上传 **`*-sysupgrade.itb`**（写 `ubi:fit`）→ 按下表选 **UBI 布局** [YYH]：

   | 镜像 FDT `ubi` reg | WebUI 选择 |
   |---|---|
   | `<0x00700000 0x1b700000>` | UBI 2.0（新构建默认） |
   | `<0x00700000 0x1d9c0000>` | UBI 1.5 |
   | `<0x00700000 0x1f700000>` | UBI 1.0（PR #22397 目前所载旧边界） |

   核法（PC 上，[YYH]）：
   ```sh
   u-boot/tools/dumpimage -T flat_dt -p 1 -o /tmp/xr1710g.dtb firmware.itb
   dtc -I dtb -O dts /tmp/xr1710g.dtb | grep -A2 'label = "ubi"'
   ```
   > 预期：写入完成提示。异常：Linux 卡 `not enough PEBs` / `Waiting for root device /dev/fit0` → **布局选错**，重进恢复页重选（不算变砖升级，RD-6）[YYH]。
   > 本路径只刷系统，**不碰 U-Boot 槽**——R1 红区 [04§1]。
5. 【人类】确认页面写完成、灯效恢复后**断电重启**。
   > 预期：进 OpenWrt。异常：仍无系统 → 用 `uboot` 目标刷 YYH 本体（§7.2）或落 T4。

**恢复页能力边界**：✅ `firmware`→sysupgrade ITB；✅ `uboot`→`xr1710g-chainloader-slot.bin`（更新 YYH 本体）；❌ **绝不**传 `u-boot.bin`/`u-boot.img`/`xr1710g-ubi.img`（RD-2 [YYH]）；❌ 不用于刷原厂固件（无公开下载 [02§5]）。

---

## 6. 档位 ④ T4：无引导 → NAND 编程器（最后手段）

**判定**：10G LED 不闪、状态灯无常红→流动、串口无任何输出、恢复页打不开——所有软件入口失效 [04§1]。

| 项 | 事实 |
|---|---|
| 闪存 | Winbond **W25N04KVZEIR**，512MB SPI NAND [01§0] |
| 公开教程 | **未能确认**（报告与网络核对均未找到 XR1710G/AN7581 编程器救砖教程）[02§6 path6] |
| 技术障碍 | 厂商引导链用 **BMT/BBT 坏块管理** [01§4]；直写需**复刻 chainloader 布局**（shim+FIT 双入口、BMT 表一致性）[YYH][02§6 path6] |
| 其他入口 | 板载 JTAG：**未能确认**（仅 OpenWrt 维基泛泛之说，本机针位照片缺失）[01§8] |
| 可参考输入 | §2/§7.1 备份的 `chainloader-slot-1m.bin` / `tclinux-head-1m.bin` 即编程器要恢复的目标镜像 |

执行前置（缺一不可）：备份资产在位 → 编程器支持 W25N04KV → **接受全砖风险**（风险自负 [04§1]）。
预期：能识别芯片、读写校验通过、上电有引导输出。异常：焊盘损伤、BMT/BBT 不一致导致写后仍不启动 → 记录现场，回填实验报告。
本档无 AI 可代劳部分（除核对文档）。

---

## 7. YYH 镜像备份与回刷命令序列

### 7.1 备份现有 YYH U-Boot 镜像

时机：**M0 必做 + 任何刷机前** [02§5]。备份即回刷/自行构建的输入（YYH 打包需要 `stock_slot=xr1710g-backup/mtd5_tclinux.bin` 作参考镜像）[YYH]。

```sh
# Linux 侧（新布局，已 UBI 化）
cat /proc/mtd                                   # 找 chainloader 分区号
nanddump -l 0x100000 -f /tmp/chainloader-slot-1m.bin /dev/mtd<chainloader分区号>
# 或旧布局
nanddump -l 0x100000 -f /tmp/tclinux-head-1m.bin /dev/mtd5   # 分区号以 /proc/mtd 为准（mtd5 待实机验证）
# 全量分区备份见 §2；每份文件记 SHA256
```

存储建议：**每台机器一个目录**（含序列号）；本地一份 + 归档一份；配 SHA256 清单文件；备份文件即 M0「原厂固件/分区备份归档」验收项 [04§2]。

### 7.2 从 YYH 恢复 / 重刷的标准序列

| 可用入口 | 命令/操作 | 预期 vs 异常 |
|---|---|---|
| 恢复页（T3） | `uboot` 目标上传 `xr1710g-chainloader-slot.bin` | 预期：写入完成。异常：页面拒绝 → 核对文件名/类型（RD-2） |
| 仅 Linux（免串口） | 见 7.3 nandwrite 流程 | 预期：erase→write→sync 完成。异常：写后重启无引导 → 回 §7.4 核对 bootcmd |
| 仅 ECNT 串口（T2） | §4 的 flash write 序列（写入对象换成 `xr1710g-chainloader-slot.bin`） | 预期：bootm 后进 YYH 二级。异常：Wrong Image Format → 偏移/镜像形态不符 |
| 从备份回滚 | `nandwrite -p /dev/mtd<chainloader|tclinux> /tmp/chainloader-slot-1m.bin` | 预期：SHA256 与备份一致。异常：坏块中断 → 记录（BMT 现象 [01§4]） |

> 参考镜像名/SHA256（上一版草稿 2026-08-16 核验 [YYH]，**批量动作前须复核**）：`*xr1710g-uboot-v2026.07-59060dde-flash-slot.bin`（908,778 字节）；RAM-only 验证用 `*...-chainloader.itb`（900,330 字节）。

### 7.3 Linux 侧 nandwrite 写 chainloader（免串口场景）【人类】

```sh
grep -E 'tclinux|chainloader' /proc/mtd
nanddump -l 0x100000 -f /tmp/tclinux-head-1m.bin /dev/mtd5     # 备份头 1MiB（分区号以实测为准）
flash_erase /dev/mtd5 0 8
nandwrite -p /dev/mtd5 /tmp/xr1710g-chainloader-slot.bin
sync && reboot
```

> ⚠️ 只用**头 1MiB**；不要 `sysupgrade`、不要整槽覆盖 64MiB tclinux（RD-5 [YYH]）。新布局则写 `chainloader` 分区本体 [YYH]。

### 7.4 回滚顺序（一机一路线：互不叠加）

1. 动任何引导槽前：`printenv` 存档、分区头 1MiB 备份、SHA256 记录（§2/§7.1）。
2. **回滚只回当前路线的出口**：YYH 机器 → 恢复页/串口回刷 YYH 本体；chainloader 机器 → 菜单/串口重装 chainloader。**不得在同一槽位叠加两套引导镜像**（一机一路线 [CONTEXT]）。
3. 换路线 = 先在单机上按 §9 实验模板验证边界，再固化；两台机器分别固化不同路线作对照（M0 购 2 台 [04§2]）。
4. 回刷后核对 ECNT 首级环境：`loadaddr=0x81800000`、`fdt_high=0xac000000`、bootcmd 三式（§4）——w1700k-ubi-installer 改过的 bootcmd 需修正后再期望自动启动 [YYH]。
   ⚠️ **不要整份 `printenv` 从别的机器复制**（ethaddr/bootargs/GPIO/序列号是板级私有）[YYH]。

---

## 8. 一机一路线互刷边界实验模板（M0 真机填表）

> 目的：回答 CONTEXT「一机一路线」的边界——YYH ↔ upstream chainloader **能否在同一台机器上互刷回退、边界在哪** [04§2 M0]。完整模板（动作字典 A1/A2/B1/B2/B3/C1、恢复入口速查、回退可达性矩阵）见 **`docs/sop/mutual-flash-experiment-template.md`**。
> ⚠️ 实验纪律：单机单实验、每步先备份、报错即停并回填「未能确认」项；所有写入动作【人类】执行。

**记录表**（每次实验一行，产出入「互刷边界实验报告」[04§2]）：

| # | 实验前状态（引导链+系统） | 刷入对象 | 结果（成功/失败现象） | 能否恢复 | 恢复路径 | 结论 |
|---|---|---|---|---|---|---|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |

动作速查（详见完整模板）：A1=YYH→upstream（ECNT 串口写链，§4 序列）；A2=upstream→YYH（§7.2 回刷）；B1=恢复顺序（恢复页重装→串口写槽→安装器重装 的依赖关系）；B2=HTTP 恢复页全流程（上电→10G LED 起闪→长按 reset→常红→流动→192.168.255.1→firmware→布局选择器三档各一次）；B3=恢复页 `uboot` 目标刷 YYH 本体（验证红区：非法镜像应被拒）。

---

## 9. 双系统切换检查表（原厂 ↔ 自建基线）

> 目标：M1 验收「两台机器均刷入自建基线并可回退原厂（含 UBI 安装器路径兼容验证）」[04§2 M1]。原厂 = Brightspeed 出厂固件（无公开下载 [02§5]）；**原厂可回退的唯一来源是本机备份**。

### 9.1 前置（两台机都要）

- [ ] 原厂全分区备份 + SHA256 清单归档（§2）——无备份则**原厂不可回退**（[02§5]）。
- [ ] `printenv` 全程存档（每切换一次存一次）。
- [ ] 一台留原厂作对照（建议：M0 购 2 台 [04§2]，1 台先不动）。

### 9.2 正向：原厂 → 自建基线

| 步骤 | 操作 | 预期 vs 异常 |
|---|---|---|
| P1 | （延续前置）核对原厂备份在位 | 预期：SHA256 一致。异常：缺备份 → 停（RD-8） |
| P2 | YYH 路线：恢复页 `firmware` 刷自建 sysupgrade ITB（UBI 2.0，§5）；或串口路线：chainloader + UBI 安装器（§4） | 预期：引导进自建基线。异常：按 §0 档位判断回退后续 |
| P3 | 验证：三频无线可配；**2×10G 识别**（RTL8261BE [01§6]）；**LED 正常**（防 LED 反 [02§6 path5]）；**MAC 读取正确**（wan_mac@0x5000 / lan_mac@0x6000 布局 [02§1.1]）；NPU 固件加载（`en7581_MT7996_npu_rv32.bin` [02§1.1/§2]）；温度/风扇正常 | 预期：逐项通过。异常：逐项记录，LED 反/10G 不识别多为包/镜像类型问题（对照 RD-3） |

### 9.3 反向：自建基线 → 原厂（回退）

| 步骤 | 操作 | 预期 vs 异常 |
|---|---|---|
| R1 | 前提：原厂分区镜像备份在位；回写命令 = §2 备份的**逆向**（`nandwrite` 回写原厂各分区 + 还原 bootcmd/ethaddr）——**报告未载全，完整序列待实机验证，此处只给框架不编造** | 预期：写回完成。异常：任一步失败记录现场，不得强行继续 |
| R2 | 回退确认项：原厂版本号出现；MAC/序列号与备份一致；无 UBI/I/O 错误；10G 协商正常；串口启动无异常；BMT/BBT 表正常 | 预期：逐项确认。异常：任一不符 → 判定回退失败，记录并暂停 |

> 结论性提示：UBI 化会覆盖原厂 tclinux 槽；**回退原厂只可能靠本机备份**（无公开下载 [02§5]）——这就是双机策略（一台留原厂）存在的理由 [04§2]。

---

## 10. 命令核对表（地址/偏移/串口参数 ↔ 报告交叉核对）

> 核对口径：`✅ 已核实`＝报告 01/02 明文或可由分区表直接推得；`⚠️ 待实机验证`＝报告未载、仅 [YYH]/[HURR] 或推算，动手前必须真机/日志确认。**这是动手前的最后一道检查。**

| # | 参数/取值 | 本 SOP 用途 | 报告 01 | 报告 02 | 核对结论 |
|---|---|---|---|---|---|
| C-1 | 串口 115200 8N1 无流控 | 全部串口路径 | §8 载 | — | ✅ 已核实（01§8） |
| C-2 | UART 引脚 TX–GND–VCC–N/A–RX，勿接 VCC（3.3V） | 接线 | §8 载 | — | ✅ 已核实（01§8） |
| C-3 | 出厂分区：bootloader 0–2 / uenv 2–4 / dsd 4–6 / tclinux 6–70 / tclinux_slave 70–134 / system 134–446 / reserved_bmt 446–512（MiB） | §2 备份、§4 偏移 | §4 载 | — | ✅ 已核实（01§4；分区尺寸合计 512MiB 自洽） |
| C-4 | UBI 化：vendor 0–6 / chainloader 6–7 / ubi 7MiB 起 / reserved_bmt（MiB） | §2、§4 | §4 载（chainloader 1MiB） | §3（UBI 2.0 布局统一） | ✅ 已核实（01§4）；offset 明细待实机验证 |
| C-5 | chainloader 槽起始 **0x600000（6MiB）** | §4 flash write | §4（tclinux 起点=0x600000） | §1.1 明文「flash write @0x600000」 | ✅ **交叉核实**（01§4 + 02§1.1） |
| C-6 | chainloader 槽写入长度 **0x100000（1MiB）** | §4 | §4（新布局 chainloader 1MiB） | — | ✅ 已核实（01§4）；旧布局「头 1MiB」限定 [YYH]，待实机验证 |
| C-7 | 深偏移 **0x602100**（FIT 起点，bootcmd 式 2/3） | §4 bootcmd | — | — | ⚠️ 待实机验证（[YYH] 记载，报告未载） |
| C-8 | TFTP 加载地址 **0x89000000** | §4 | — | — | ⚠️ 待实机验证（以本机 printenv 为准；YYH 期望 loadaddr=0x81800000 [YYH]） |
| C-9 | UBI 分区 reg **<0x00700000 0x1b700000>**（UBI 2.0，439MiB） | §5 布局选择 | §4「ubi（439–503MiB）」措辞**歧义**（7MiB 起 + 439MiB 大小 ≈ 446MiB 终点，与 reserved_bmt 446–512 自洽；「439–503」或为误写） | §3 | ⚠️ 部分已核实 / 措辞存疑 → 待实机验证 |
| C-10 | UBI 1.5 <0x00700000 0x1d9c0000> / UBI 1.0 <0x00700000 0x1f700000> | §5 布局选择 | — | — | ⚠️ 待实机验证（[YYH] 记载） |
| C-11 | 恢复页 **http://192.168.255.1** | §5 | §4 载 | §3 载 | ✅ **交叉核实**（01§4 + 02§3） |
| C-12 | **长按 reset** 进恢复 | §5 | §4 载 | §3 载 | ✅ **交叉核实**（01§4 + 02§3） |
| C-13 | 恢复页内置 DHCP、PC 接 **10G 口** | §5 | — | §3 载（内置 DHCP） | ✅ 已核实（02§3）；1G 口支持待实机验证 |
| C-14 | NAND：**W25N04KVZEIR** 512MB SPI NAND | §6 | §0 载 | §0 载 | ✅ 交叉核实（01§0 + 02§0） |
| C-15 | U-Boot 2014.04-rc1 AXON 1.6，签名启动、串口可中断 | §4 判定 | §0/§4 载 | §3 载 | ✅ 交叉核实（01§0/§4 + 02§3） |
| C-16 | chainloader 概念：新 U-Boot 放 kernel 槽、从 UBI 加载 FIT | §4/§7 | §4 载 | §3 载 | ✅ 交叉核实（01§4 + 02§3） |
| C-17 | 双入口魔数 27 05 19 56 / d0 0d fe ed | §4 自检 | — | — | ⚠️ 待实机验证（[YYH] 记载） |
| C-18 | 安装器菜单「4. Boot installer via TFTP」「3. Boot recovery from flash」 | §4 | — | §6 path2/path4 载 | ✅ 已核实（02§6） |
| C-19 | YYH 刷入位置措辞：01§4「替换 bootloader 槽」vs 现版 README/02§3「chainloader（kernel 槽）」 | §7 | §4 | §3 | ⚠️ 措辞差异待考证（以真机 /proc/mtd + 恢复页为准） |
| C-20 | 115200 8N1、console=ttyS0 | §2 | §8 载 | — | ✅ 已核实（01§8） |

---

## 11. 未能确认清单（留待 M0 真机 / 后续调研）

1. 恢复页**静态 IP** 配置细节（README 仅载内置 DHCP；`192.168.255.x/24` 为建议值未证实）[YYH]。
2. 恢复页是否支持 **1G 口**（README 仅记 10G 口）。
3. ECNT 首级 TFTP 走 10G 还是 1G 口（W1701K 曾现 ARP 失败 [02§6 path5]）。
4. XR1710G 专属 chainloader / installer / recovery 镜像**确切文件名**（PR #22397 未合、快照未出 [02§1.3]）。
5. recovery.itb 的**落盘机制**（菜单 3 前置未载）[02§6 path4]。
6. NAND 编程器公开教程、适配器型号、直写 BMT/BBT 流程（= [02§6 path6]，未能确认）。
7. 板载 JTAG 可用性（[01§8] 未确认）。
8. 刷 W1700K 包致 LED 反的具体机理与布局差异细节（[01§6][02§6 path5] 仅结论）。
9. YYH 历史版本是否曾直接替换 bootloader 槽（01§4 措辞 vs 现版 README 写 chainloader 槽——见核对表 C-19，以实机为准）。
10. 长按 reset 在**出厂 ECNT** 与 **upstream chainloader** 上的行为（见互刷实验模板速查表）。
11. 原厂固件**回退的完整命令序列**（§9.3 仅框架，报告未载全——待 M0 实机回填）。
12. 01§4「ubi（439–503MiB）」措辞歧义（见核对表 C-9）。
13. 本版草稿未再联网复核 [YYH]/[HURR]（上一版草稿 2026-08-16 的核验记录为唯一依据）。

---

## 12. 参考来源

- [01] `docs/research/01-hardware.md`（§0/§3/§4/§6/§8/§9 存储引导与串口）
- [02] `docs/research/02-firmware-ecosystem.md`（§1.1/§1.3/§2/§3/§4/§5/§6/§7）
- [04] `docs/research/04-roadmap-and-risk.md`（§1 R1/R2/R5/R7、§2 M0/M1）
- CONTEXT.md（人类最小集 / 救砖 / 一机一路线 / YYH 路线）
- [YYH] github.com/YYH2913/http-uboot README（仓库曾名 http-uboot-xr1710g；上一版草稿 2026-08-16 抓取核验）
- [HURR] github.com/hurrian/w1700k-ubi-installer README（同上）
- 配套：`docs/sop/mutual-flash-experiment-template.md`（互刷实验完整模板）、`docs/sop/scratch-pad-template.md`（现场记录模板）
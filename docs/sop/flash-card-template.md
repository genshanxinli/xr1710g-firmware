# 闪光卡 · XR1710G alpha 首刷（D6 人工放行模板）

> 本卡由 AI 在 D3 产物校验通过后填写完整，交付人工执行。**人工核对 sha256 后执行刷写**；
> 刷机属人类最小集（首刷放行），AI 只提供镜像与指引，不操作设备。
> 红线条目不可跳过：**永不碰 bootloader 槽**（一机一路线）、**刷前已备好回退镜像**。

## 0. 本次镜像信息

- 构建 run：`<run-id>`（GitHub Actions）
- 基线：OpenWrt main `<commit>` + device-layer v2（2026-08-17）
- 产物目录/下载：`build/artifacts/<run-id>/gemtek_xr1710g-ubi/`

## 1. 镜像三件套与 sha256

| 件 | 文件名 | sha256 |
|---|---|---|
| sysupgrade | `<...-sysupgrade.itb>` | `<sha>` |
| initramfs-recovery | `<...-initramfs-recovery.itb>` | `<sha>` |
| chainload-uboot（社区独有） | `<...-chainload-uboot.itb>` | `<sha>` |

> 刷前核对：`sha256sum <文件>` 必须等于上表值。

## 2. 人工执行步骤（SSH 到 192.168.123.1 执行）

1. 备份当前可用镜像（社区线固件本体已在手？确认原厂/社区镜像已归档到安全位置）。
2. 上传 sysupgrade 镜像：`scp <file> root@192.168.123.1:/tmp/`
3. 核对：`sha256sum /tmp/<file>`（与上表一致才继续）
4. 刷入：`sysupgrade -v /tmp/<file>`（保持电源稳定；完成后自动重启）
5. 重启后验证：
   - `cat /etc/openwrt_release` → 版本串应含 `r<构建号>` / `SNAPSHOT`
   - `ip -br addr` → br-lan 192.168.123.1/24 恢复
   - `uname -r` → 内核应有别于旧线（6.18.44 系期望）
6. SSH 断连 = 刷写失败/变砖路径：**按 reset 不放 3s+ → YYH http-uboot 恢复页
   (192.168.255.1) → HTTP 恢复**（SOP：`docs/sop/brick-recovery.md`）。

## 3. 完成后回报内容（给 AI）

- 刷写命令输出尾部 / 是否自动重启成功
- 上述 5 条验证输出
- 异常情况描述（若有）

## 4. 失败预案

- sysupgrade 拒绝（metadata/board 不匹配）：贴错误输出回报 AI，**不要强刷**（`-F` 禁用）。
- 刷后失联：走 §2.6 恢复页；若恢复页也失联 → 断电重启后再试；仍失联 → 人工介入串口/编程器（SOP）。

## 5. 回退路径

- 本卡 §0 的上一代可用镜像（社区线）已备份 → 同步骤 2 刷回；不成则走 YYH 恢复页。
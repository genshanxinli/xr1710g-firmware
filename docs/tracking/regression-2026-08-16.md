
## 冒烟（rc=0）
```
PASS | 1.SSH 可达 | 辅助通道 OK
PASS | 2.固件版本 | OpenWrt SNAPSHOT r2177-f5fafce4c7 | airoha/an7581 | 内核 6.18.41
PASS | 3.接口状态 | br-lan=br-lan up 口=3（eth0/wan/lan1）
PASS | 4.无线 band | phy0 Band 1:,Band 2:,Band 4:,（6GHz: radio2 disabled=1,信道未枚举=已知态）
PASS | 5.NPU 固件 | [    6.399276] airoha-npu 1e900000.npu: NPU fw version: 0.1111|
PASS | 6.告警扫描 | 无 OOM/panic/WED crash（dmesg 尾部快照）
PASS | 7.资源基线 | mem=1867576 total / 1633228 avail | load=0.11 0.04 0.01 | overlay=349.1M 剩余
PASS | 8.分区表存证 | mtd: "vendor" "chainloader" "ubi" "reserved_bmt" 
```

## 指标回填：跳过（路由器无 bash，D0-5 待装）


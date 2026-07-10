# Windows + WSL2 串口下载配置

本文档记录在 Windows 上使用 ISE/JTAG、在 WSL2 中构建 TecPlusRV firmware，并通过板载 CP2102 串口运行 `uart_loader.py` 的完整流程。

推荐分工：

```text
Windows：ISE、JTAG、usbipd-win
WSL2：firmware 构建、仿真、uart_loader.py
TEC-PLUS MINI USB：CP2102 UART
```

## 先区分两个 USB 设备

一台电脑上可能同时看到：

- `Silicon Labs CP210x USB to UART Bridge`，常见 VID:PID 为 `10c4:ea60`：这是板载串口，应当 attach 到 WSL。
- FTDI `USB Serial Converter`，例如 `0403:6014`：可能属于 JTAG 下载器。ISE 在 Windows 中使用它时，不要 attach 到 WSL。

以下命令中的 `BUSID`、`COM8` 和 `/dev/ttyUSB0` 都只是示例，必须以当前机器实际输出为准。

## 1. 在 WSL 构建 payload

先在仓库根目录完成构建和 dry-run：

```bash
FIRMWARE_MAIN="$PWD/firmware/tests/boot_payload.c" ./scripts/build_firmware.sh
python3 scripts/uart_loader.py --input firmware/build/firmware.bin --dry-run
```

dry-run 应显示：

- magic：`0xBADABB1E`
- wire bytes：`1e bb da ba`
- payload 大小
- CRC32

## 2. Windows 安装 usbipd-win

在管理员 PowerShell 中安装：

```powershell
winget install usbipd
```

安装后重新打开 PowerShell，确认：

```powershell
usbipd --version
usbipd list
```

## 3. 找到并共享 CP2102

插好 TEC-PLUS 的 MINI USB 串口线，在 Windows 执行：

```powershell
usbipd list
```

示例：

```text
BUSID  VID:PID    DEVICE                                              STATE
1-1    10c4:ea60  Silicon Labs CP210x USB to UART Bridge (COM8)       Not shared
```

首次使用需要在管理员 PowerShell 中 bind：

```powershell
usbipd bind --busid 1-1
```

bind 成功后状态是 `Shared`。`Shared` 只表示允许转发，还没有真正进入 WSL。

bind 是持久的，通常每个设备只需执行一次。

## 4. Attach 到 WSL2

先保持一个 WSL 终端处于打开状态，然后在普通 PowerShell/CMD 中执行：

```powershell
usbipd attach --wsl --busid 1-1
usbipd list
```

成功后状态应从：

```text
Shared
```

变成：

```text
Attached
```

设备处于 `Attached` 状态时由 WSL 独占，Windows 的 `COM8` 暂时不能使用。

拔插设备、重启 WSL 或执行 detach 后通常需要重新 attach；不需要重新 bind。

## 5. 在 WSL 确认 CP210x 驱动和设备节点

回到 WSL：

```bash
lsusb
sudo modprobe usbserial
sudo modprobe cp210x
lsmod | grep cp210x
find /dev -maxdepth 1 -name 'ttyUSB*' -ls
sudo dmesg | tail -30
```

`modprobe` 成功时默认不输出任何内容，这是正常现象。需要确认结果时查看：

```bash
echo $?
```

返回 `0` 表示模块加载成功。

正常情况下会看到 USB 设备 `10c4:ea60`，以及：

```text
/dev/ttyUSB0
```

这里使用 `find` 而不是直接写 `ls /dev/ttyUSB*`，是为了避免 zsh 在没有匹配项时直接报 `no matches found`。

## 6. 配置串口权限和 pyserial

把当前用户加入 `dialout`：

```bash
sudo usermod -aG dialout "$USER"
newgrp dialout
```

确认设备权限：

```bash
ls -l /dev/ttyUSB0
```

安装 `pyserial`。如果系统允许直接安装：

```bash
python3 -m pip install pyserial
```

如果 Ubuntu 提示系统 Python 受管理，使用 venv：

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install pyserial
```

## 7. 下载 firmware

确认 FPGA 中已经配置 bootloader bitstream，并且 ISE 参数 `BOOTLOADER_ENABLE=1`。

在 WSL 执行：

```bash
python3 scripts/uart_loader.py \
  --port /dev/ttyUSB0 \
  --baud 9600 \
  --input firmware/build/firmware.bin
```

脚本打开串口后会提示：

```text
请按下并松开 TEC-PLUS RESET
```

正确流程是：

```text
按下并松开 RESET
-> bootloader 清空 BRAM
-> host 收到 READY
-> 发送 payload
-> host 收到 ACK
-> CPU 开始运行
```

更换程序时只需重新构建 firmware、再次运行 host 工具并按 RESET，不需要重新下载 bitstream。

不要用 CONFIG 代替 RESET：CONFIG 会触发 FPGA 重新配置；RESET 才是让当前 bootloader 重新接管 UART/BRAM 的入口。

## 8. 用完后交还 Windows

在 Windows 执行：

```powershell
usbipd detach --busid 1-1
```

设备会重新成为 Windows 的 `COM8`。下次 WSL 使用时重新执行 attach 即可。

## 备用方案：直接从 Windows COM 口发送

如果不想配置 USB/IP，可以让 WSL 只负责构建，把 host 工具和产物复制到 Windows：

```bash
mkdir -p /mnt/c/Temp/TecPlusRV
cp scripts/uart_loader.py firmware/build/firmware.bin /mnt/c/Temp/TecPlusRV/
```

然后在 Windows PowerShell：

```powershell
cd C:\Temp\TecPlusRV
py -m pip install pyserial
py .\uart_loader.py --port COM8 --baud 9600 --input .\firmware.bin
```

这种方式不需要 usbipd，适合首次上板或排查 WSL USB 转发问题。

## 常见问题

### `usbipd list` 显示 `Shared`，但 `lsusb` 没有设备

还没有 attach。执行：

```powershell
usbipd attach --wsl --busid 1-1
```

目标状态必须是 `Attached`。

### `usbipd attach` 报设备正在使用

关闭 Windows 中占用对应 `COMx` 的串口终端、IDE 和调试软件，再重新 attach。

### `modprobe cp210x` 没有输出

这是正常的成功行为。用下面两条确认：

```bash
echo $?
lsmod | grep cp210x
```

### 已经 `Attached`，但没有 `/dev/ttyUSB0`

依次执行：

```bash
sudo modprobe usbserial
sudo modprobe cp210x
sudo dmesg | tail -50
```

仍然没有时，在 Windows detach 后重新 attach：

```powershell
usbipd detach --busid 1-1
usbipd attach --wsl --busid 1-1
```

### 打开 `/dev/ttyUSB0` 报 permission denied

执行：

```bash
sudo usermod -aG dialout "$USER"
newgrp dialout
```

临时验证也可以使用：

```bash
sudo chmod a+rw /dev/ttyUSB0
```

长期使用应当采用 `dialout`，不要依赖每次 chmod。

### WSL 能用后 Windows 找不到 COM 口

这是 USB/IP 独占设备的正常行为。用完执行：

```powershell
usbipd detach --busid 1-1
```

## 参考

- Microsoft WSL USB 连接说明：<https://learn.microsoft.com/windows/wsl/connect-usb>
- usbipd-win WSL support：<https://github.com/dorssel/usbipd-win/wiki/WSL-support>
- TecPlusRV 协议定义：`docs/BOOTLOADER_PROTOCOL.md`

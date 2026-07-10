# Windows + WSL2 串口下载

本文档记录 TecPlusRV 在 Windows + WSL2 环境下构建、下载并监视 firmware 输出的推荐流程。

## 推荐方案：WSL 一条命令构建并通过 Windows COM 口下载

推荐让两个系统保持以下分工：

```text
WSL2：源码、RISC-V 工具链、firmware 构建、Makefile
Windows：ISE、JTAG、CP2102 COM 口、pyserial
```

WSL 可以直接调用 Windows 的 `py.exe`。`make bootload` 会先在 WSL 构建 firmware，再把脚本和产物路径转换成 Windows 路径，由 Windows Python 打开 `COMx`；上传成功后继续使用同一个串口连接显示 payload 输出。

这种方法不需要复制文件，也不需要使用 usbipd 把 CP2102 attach 到 WSL。

### 1. 准备 bootloader bitstream

先确认 FPGA 中已经配置 bootloader bitstream，并且 ISE 参数 `BOOTLOADER_ENABLE=1`。

bootloader bitstream 只需在 FPGA 重新配置或掉电后重新下载。更换 payload 时不需要重新下载 bitstream，只需再次运行 `make bootload` 并按 RESET。

不要用 CONFIG 代替 RESET：CONFIG 会触发 FPGA 重新配置；RESET 才会让当前 bootloader 重新接管 UART 和 BRAM。

### 2. 在 Windows 安装 Python 和 pyserial

在 PowerShell 中确认 Windows Python launcher 可用：

```powershell
py --version
py -m pip install pyserial
```

回到 WSL，确认 Windows Interop 能找到它（如果找不到，可能是 Intrerop 被关掉了，可以检查配置文件 `/etc/wsl.conf`）：

```bash
command -v py.exe
```

如果 `py.exe` 没有进入 WSL 的 `PATH`，可以在运行目标时显式指定，例如：

```bash
make bootload PORT=COM8 WINDOWS_PYTHON=/mnt/c/Windows/py.exe
```

### 3. 确认 CP2102 归 Windows 使用

在 Windows 设备管理器或下面的命令中确认板载 CP2102 对应的串口号：

```powershell
usbipd list
```

示例：

```text
1-1  10c4:ea60  Silicon Labs CP210x USB to UART Bridge (COM8)  Shared
```

`Shared` 不影响 Windows 使用；`Attached` 表示设备已被 WSL 独占。若当前是 `Attached`，先在 Windows 执行：

```powershell
usbipd detach --busid 1-1
```

同时关闭 PuTTY、串口监视器、IDE 等可能占用 `COM8` 的程序。

### 4. 一条命令完成构建、上传和监视

在 WSL 的仓库根目录执行：

```bash
make bootload PORT=COM8
```

要下载指定 firmware 入口：

```bash
make bootload \
  PORT=COM8 \
  FIRMWARE_MAIN="$PWD/firmware/tests/boot_payload.c"
```

目标的完整流程是：

```text
WSL 构建 firmware.bin
-> WSL 通过 Windows Interop 调用 py.exe
-> Windows Python 打开 COM8
-> 提示按下并松开 TEC-PLUS RESET
-> bootloader 返回 READY
-> host 发送 payload 并收到 ACK
-> CPU 开始运行 payload
-> host 原地进入 serial monitor
```

loader 自身提示使用 cyan、错误使用 red；serial monitor 不修改 payload 的颜色或内容。按 `Enter` 或 `Ctrl+C` 均可退出；WSL 启动的 Windows 进程可能把 `Ctrl+C` 表现为 stdin EOF，loader 会将它同样视为退出请求。当前 monitor 只负责接收和显示，不把键盘输入发送给 payload。

上传按 64-byte chunk 进行。如果在 `收到 READY，按 64-byte chunk 发送 ...` 之后再次按 RESET，host 会在收到新 READY 后废弃当前 attempt，并从 magic 自动整包重传；默认最多重传 3 次，超过上限才会失败退出。

### 5. 重复下载新程序

退出 monitor、修改源码后，再次执行同一条命令：

```bash
make bootload PORT=COM8
```

看到提示后再按 RESET。RESET 会让 bootloader 重新接管 BRAM，因此可以反复下载不同 payload，不需要重新烧录 bitstream。

不要瞎按 CONFIG，它是用来重置 FPGA 的，按了就需要重新在 ISE 里面烧录了。

## 额外参考：分步运行 Windows host 工具

需要单独排查构建或 host 工具时，可以在 WSL 构建：

```bash
make firmware
```

然后在 Windows PowerShell 直接读取 WSL 文件。先用 `wsl -l -q` 确认发行版名称，再设置仓库路径：

```powershell
$repo = "\\wsl.localhost\Ubuntu\home\rikka\NexysRV-Insight"
py "$repo\scripts\uart_loader.py" `
  --port COM8 `
  --baud 9600 `
  --input "$repo\firmware\build\firmware.bin" `
  --monitor
```

只检查封包、不访问串口：

```bash
python3 scripts/uart_loader.py \
  --input firmware/build/firmware.bin \
  --dry-run
```

dry-run 应显示 magic `0xBADABB1E`、wire bytes `1e bb da ba`、payload 大小和 CRC32。

## 额外参考：用 usbipd 把串口交给 WSL

只有在必须让 Linux 程序直接访问 `/dev/ttyUSB0` 时，才需要 USB/IP。

先在管理员 PowerShell 中安装并首次共享 CP2102：

```powershell
winget install usbipd
usbipd list
usbipd bind --busid 1-1
```

保持一个 WSL 终端打开，在普通 PowerShell 中 attach：

```powershell
usbipd attach --wsl --busid 1-1
```

回到 WSL：

```bash
sudo modprobe usbserial
sudo modprobe cp210x
find /dev -maxdepth 1 -name 'ttyUSB*' -ls
```

`modprobe` 成功时默认没有输出。正常情况下会出现 `/dev/ttyUSB0`。

配置权限和 pyserial：

```bash
sudo usermod -aG dialout "$USER"
newgrp dialout
python3 -m pip install pyserial
```

分步构建并下载：

```bash
make firmware
python3 scripts/uart_loader.py \
  --port /dev/ttyUSB0 \
  --baud 9600 \
  --input firmware/build/firmware.bin \
  --monitor
```

设备处于 `Attached` 状态时由 WSL 独占，Windows 的 `COM8` 会暂时消失。用完后在 Windows 归还设备：

```powershell
usbipd detach --busid 1-1
```

## 常见问题

### `make bootload` 提示找不到 Windows Python

先在 Windows PowerShell 安装 Python，再确认 WSL 能执行：

```bash
py.exe --version
```

也可以通过 `WINDOWS_PYTHON` 指定 `py.exe` 的 WSL 路径。

### Windows Python 提示缺少 pyserial

依赖必须安装到 Windows Python，而不是 WSL Python：

```powershell
py -m pip install pyserial
```

### 打开 COM 口时报 access denied

关闭占用该端口的 Windows 串口程序。如果设备被 attach 到 WSL，先执行：

```powershell
usbipd detach --busid 1-1
```

### WSL 能访问串口后，Windows 看不到 COM 口

这是 USB/IP 独占设备的正常行为。执行 `usbipd detach` 后，COM 口会重新交还 Windows。

### uploader 一直等待 READY

确认 bitstream 使用 `BOOTLOADER_ENABLE=1`，然后在 uploader 打开串口并给出提示后，按下并松开 TEC-PLUS RESET。

### `modprobe cp210x` 没有输出

这是正常的成功行为，可以用下面命令确认：

```bash
echo $?
lsmod | grep cp210x
```

## 参考

- Microsoft WSL USB 连接说明：<https://learn.microsoft.com/windows/wsl/connect-usb>
- usbipd-win WSL support：<https://github.com/dorssel/usbipd-win/wiki/WSL-support>
- TecPlusRV 协议定义：`docs/BOOTLOADER_PROTOCOL.md`

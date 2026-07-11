# Issue #23 DarkRISCV GDB Stub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 DarkRISCV bare-metal firmware 中实现 cooperative GDB Remote Serial Protocol stub，使 `gdb-multiarch` 能经 UART 停住 target、读写 x0～x31/PC、读写 BRAM/SDRAM，并继续执行。

**Architecture:** 新增独立 `gdb_stub` firmware profile，复用现有 `trap_entry`、canonical `trap_frame` 和阻塞式 UART driver。`gdb_packet.c` 只处理无副作用的 framing/hex codec，`gdb_stub.c` 负责 packet dispatch、register mapping、memory 白名单与 `continue`；CPU+UART 端到端行为由 `tb_gdb_stub.v` 验证。

**Tech Stack:** RV32I/Zicsr、freestanding C11、RISC-V assembly、Verilog-2001、Icarus Verilog、Python 3、GDB Remote Serial Protocol、现有 `scripts/test_runner.py` catalog。

## Global Constraints

- 只支持 `CPU_IMPL=1` 的 DarkRISCV；PicoRV32 行为不得改变。
- 首版只实现 cooperative `ebreak`/同步 fault stop，不实现 async Ctrl-C、single-step、`Z0/z0`、thread/task enumeration、XML target description 或 no-ack mode。
- 必须复用 `firmware/runtime/trap_entry.S`、`struct trap_frame` 和 `trap_dispatch()`；不得新增第二个 `mtvec` 入口。
- register layout 固定为 x0～x31 后接 PC，共 33 个 32-bit little-endian register；x0 写入必须忽略。
- packet buffer 固定为 512 bytes，`qSupported` 返回 `PacketSize=200`。
- `m/M` 只允许 BRAM `0x00000000..0x0000ffff` 与 SDRAM `0x80000000..0x81ffffff`，拒绝 MMIO、越界、加法溢出与非法 hex。
- memory byte access 复用现有 MiniSoC subword path，不在 stub 内实现 aligned read-modify-write。
- GDB session 独占 UART，不允许应用日志混入 RSP 字节流。
- 所有新增注释、文档、测试输出和 commit message 使用中文，保留 GDB、packet、trap、UART 等常用术语。
- 每个功能按 RED→GREEN 实施并形成独立 commit；共享 `sim/build` 的 suite 必须串行运行。

---

## File Structure

### 新增文件

- `firmware/gdb/gdb_packet.h`：512-byte parser 状态、事件枚举与 hex/u32 codec 接口。
- `firmware/gdb/gdb_packet.c`：`$payload#checksum` 状态机、checksum、hex 编解码。
- `firmware/gdb/gdb_stub.c`：trap dispatcher、RSP command dispatch、register/memory/continue 语义。
- `firmware/tests/gdb_stub_smoke.c`：初始化 trap、执行 cooperative `ebreak`、验证 continue 后 context。
- `tests/test_gdb_packet.c`：host-native parser/codec 单元测试。
- `sim/tb_gdb_stub.v`：CPU+UART RX/TX 端到端 RSP testbench。
- `scripts/gdb_stub_probe.py`：物理串口 raw packet probe。

### 修改文件

- `scripts/build_firmware.sh`：新增 `gdb_stub` profile，链接 trap 与 stub source。
- `sim/run_sim.sh`：新增 `gdb_packet` host test 与 `gdb_stub` SoC simulation target。
- `scripts/test_catalog.json`：新增两个 case，并加入 `platform`/`soc`/`local` suite。
- `docs/DEV_FLOW.md`：记录 build、simulation、raw probe 与 GDB 使用命令。

---

### Task 1: 建立 packet parser 与 codec

**Files:**
- Create: `tests/test_gdb_packet.c`
- Create: `firmware/gdb/gdb_packet.h`
- Create: `firmware/gdb/gdb_packet.c`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Produces: `enum gdb_packet_event gdb_packet_feed(struct gdb_packet_parser *, unsigned char)`。
- Produces: `gdb_packet_parser_init()`、`gdb_hex_nibble()`、`gdb_parse_hex_u32()`、`gdb_encode_u32_le()`、`gdb_decode_u32_le()`。
- Invariant: `parser.payload` 只在 `GDB_PACKET_READY` 时包含 NUL-terminated payload。

- [ ] **Step 1: 写 host-native 失败测试**

`tests/test_gdb_packet.c` 直接喂入字节，覆盖：合法 `?`、错误 checksum、NACK、171-byte payload、512-byte overflow 后 `$` 重同步、u32 little-endian codec。测试入口使用普通 `assert()`：

```c
int main(void)
{
    struct gdb_packet_parser parser;
    gdb_packet_parser_init(&parser);
    assert(feed_text(&parser, "$?#3f") == GDB_PACKET_READY);
    assert(strcmp(parser.payload, "?") == 0);

    gdb_packet_parser_init(&parser);
    assert(feed_text(&parser, "$g#00") == GDB_PACKET_CHECKSUM_ERROR);
    assert(gdb_packet_feed(&parser, '-') == GDB_PACKET_RETRY);

    char encoded[9];
    gdb_encode_u32_le(encoded, 0x12345678u);
    assert(strcmp(encoded, "78563412") == 0);
    puts("PASS: GDB packet parser 与 codec");
    return 0;
}
```

同文件先定义只用于测试的 helper，确保每个 case 返回最后一个非 `NONE` event：

```c
static enum gdb_packet_event feed_text(struct gdb_packet_parser *parser,
                                       const char *text)
{
    enum gdb_packet_event event = GDB_PACKET_NONE;
    while (*text != '\0') {
        enum gdb_packet_event next = gdb_packet_feed(parser, (unsigned char)*text++);
        if (next != GDB_PACKET_NONE)
            event = next;
    }
    return event;
}
```

- [ ] **Step 2: 接入 `gdb_packet` test target 并验证 RED**

`sim/run_sim.sh gdb_packet` 使用 host compiler：

```bash
${HOST_CC:-cc} -std=c11 -Wall -Wextra -Werror \
  -Ifirmware -o sim/build/test_gdb_packet \
  tests/test_gdb_packet.c firmware/gdb/gdb_packet.c
sim/build/test_gdb_packet
```

Run: `./sim/run_sim.sh gdb_packet`

Expected: FAIL，因为 `firmware/gdb/gdb_packet.h`/实现尚不存在。

- [ ] **Step 3: 实现最小 parser 与 codec**

Header 固定以下 API：

```c
#define GDB_PACKET_CAPACITY 512u

enum gdb_packet_event {
    GDB_PACKET_NONE,
    GDB_PACKET_READY,
    GDB_PACKET_CHECKSUM_ERROR,
    GDB_PACKET_OVERFLOW,
    GDB_PACKET_RETRY
};

struct gdb_packet_parser {
    char payload[GDB_PACKET_CAPACITY + 1u];
    unsigned int length;
    unsigned int checksum;
    unsigned int received_checksum;
    unsigned int state;
    unsigned int overflow;
};
```

状态机只识别 `$`、payload、`#`、两个 checksum hex digit 与顶层 `-`；任意状态收到新 `$` 都重新开始。overflow 后丢弃到下一个 `$`，不得产生 `READY`。

- [ ] **Step 4: 验证 GREEN**

Run: `./sim/run_sim.sh gdb_packet`

Expected: `PASS: GDB packet parser 与 codec`。

- [ ] **Step 5: Commit**

```bash
git add firmware/gdb/gdb_packet.c firmware/gdb/gdb_packet.h tests/test_gdb_packet.c sim/run_sim.sh scripts/test_catalog.json
git commit -m "feat: 实现 GDB packet parser"
```

---

### Task 2: 接入 GDB profile、stop reason 与 register packet

**Files:**
- Create: `firmware/gdb/gdb_stub.c`
- Create: `firmware/tests/gdb_stub_smoke.c`
- Create: `sim/tb_gdb_stub.v`
- Modify: `scripts/build_firmware.sh`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Consumes: Task 1 packet parser/codec、`uart_getc()`/`uart_putc()`、canonical `trap_frame`。
- Produces: strong `struct trap_frame *trap_dispatch(struct trap_frame *frame)`。
- Produces: `FIRMWARE_PROFILE=gdb_stub` 与 `./sim/run_sim.sh gdb_stub`。

- [ ] **Step 1: 写端到端失败 testbench**

`tb_gdb_stub.v` 复用现有 MiniSoC UART bit timing，等待 firmware 执行 `ebreak` 后依次发送：

```text
$qSupported:multiprocess+;xmlRegisters=i386#<checksum>
$vMustReplyEmpty#3a
$Hg0#df
$?#3f
$g#67
```

断言 target 分别回 ACK 与：`PacketSize=200`、empty、`OK`、`S05`、264 个 register hex 字符。`g` 中 x0 必须为 0，PC 必须等于 ELF symbol `gdb_stop_site`。

- [ ] **Step 2: 接入 build/simulation target 并验证 RED**

Run: `./sim/run_sim.sh gdb_stub`

Expected: FAIL，`scripts/build_firmware.sh` 报告未知 `gdb_stub` profile 或 testbench 收不到 RSP reply。

- [ ] **Step 3: 增加 `gdb_stub` profile 与 smoke firmware**

Profile sources：

```text
firmware/runtime/trap_entry.S
firmware/runtime/trap.c
firmware/gdb/gdb_packet.c
firmware/gdb/gdb_stub.c
```

`gdb_stub_smoke.c`：

```c
volatile unsigned int gdb_continue_seen;

int main(void)
{
    trap_init();
    __asm__ volatile (".globl gdb_stop_site\ngdb_stop_site:\nebreak");
    gdb_continue_seen = 1u;
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {}
}
```

- [ ] **Step 4: 实现协商、stop reason、`g/G`**

`trap_dispatch()` 对 breakpoint/illegal/misaligned/access fault 进入 blocking loop；timer IRQ 原样返回。命令行为：

```text
qSupported      -> PacketSize=200
vMustReplyEmpty -> empty
Hc0/Hg0/Hc-1/Hg-1 -> OK
qAttached       -> 1
unknown         -> empty
?               -> S05/S04/S0b
g               -> x0..x31 + mepc
G               -> 写 x1..x31 + mepc，忽略 x0
```

reply 必须保存最后一包，收到顶层 `-` 时重发；checksum error 只发送 `-`，合法 packet 先发送 `+` 再执行。

- [ ] **Step 5: 验证 GREEN 与既有 trap 回归**

Run:

```bash
./sim/run_sim.sh gdb_stub
./sim/run_sim.sh darkriscv_machine_trap
./sim/run_sim.sh minisoc_timer_irq_dark
```

Expected: 三项 PASS。

- [ ] **Step 6: Commit**

```bash
git add firmware/gdb/gdb_stub.c firmware/tests/gdb_stub_smoke.c scripts/build_firmware.sh sim/tb_gdb_stub.v sim/run_sim.sh scripts/test_catalog.json
git commit -m "feat: 接入 DarkRISCV GDB register stub"
```

---

### Task 3: 实现 memory policy 与 continue

**Files:**
- Modify: `firmware/gdb/gdb_stub.c`
- Modify: `firmware/tests/gdb_stub_smoke.c`
- Modify: `sim/tb_gdb_stub.v`

**Interfaces:**
- Consumes: Task 2 stop loop。
- Produces: `mADDR,LEN`、`MADDR,LEN:DATA`、`c`、`cADDR`。

- [ ] **Step 1: 扩展失败 testbench**

依次验证：

```text
m00000100,4                 -> 8 hex chars
M00000100,4:78563412        -> OK，随后 m 返回 78563412
M80000001,5:1122334455      -> OK，跨 word SDRAM byte write/read 一致
m10000010,1                 -> E01（拒绝 UART MMIO）
m0000ffff,2                 -> E01（跨 BRAM 边界）
mfffffffe,4                 -> E01（address+length overflow）
c                           -> 无 reply，mepc 从 cooperative ebreak 推进 4
```

继续执行后 `gdb_continue_seen == 1` 且 `test_exit == 1`。

- [ ] **Step 2: 验证 RED**

Run: `./sim/run_sim.sh gdb_stub`

Expected: FAIL，首个 `m/M` 返回 empty 或 `c` 未正确恢复。

- [ ] **Step 3: 实现严格地址验证与 byte access**

范围检查必须使用减法形式避免 overflow：

```c
static int range_inside(unsigned int addr, unsigned int len,
                        unsigned int base, unsigned int size)
{
    return addr >= base && len <= size && addr - base <= size - len;
}
```

`m/M` 的 `len` 还必须受 reply/request buffer 限制；使用 `volatile unsigned char *` 逐 byte 访问。任何 parse、长度或范围错误统一返回 `E01`，不得触碰 memory。

- [ ] **Step 4: 实现 continue 语义**

```text
c      + breakpoint -> mepc += 4 后返回 frame
c      + fault      -> mepc 不变后返回 frame
cADDR                -> mepc = ADDR 后返回 frame
```

只允许 4-byte aligned continue address；非法地址返回 `E01` 并留在 stop loop。

- [ ] **Step 5: 验证 GREEN 与 SDRAM subword 回归**

Run:

```bash
./sim/run_sim.sh gdb_stub
./sim/run_sim.sh minisoc_sdram_subword_dark
```

Expected: 两项 PASS。

- [ ] **Step 6: Commit**

```bash
git add firmware/gdb/gdb_stub.c firmware/tests/gdb_stub_smoke.c sim/tb_gdb_stub.v
git commit -m "feat: 支持 GDB memory 与 continue"
```

---

### Task 4: 增加 host raw probe 与真实 GDB 兼容检查

**Files:**
- Create: `scripts/gdb_stub_probe.py`
- Create: `tests/test_gdb_stub_probe.py`
- Modify: `scripts/test_catalog.json`
- Modify: `docs/DEV_FLOW.md`

**Interfaces:**
- Produces: `python3 scripts/gdb_stub_probe.py --port /dev/ttyUSB0 --baud 9600`。
- Produces: 可注入 stream 的 `RspClient`，host unit test 不依赖物理串口。

- [ ] **Step 1: 写失败的 Python unit test**

使用 `io.BytesIO` 等价 fake stream 验证 checksum、ACK、NACK retry、empty reply、`S05` 与 264-char `g` reply；不引入 pyserial dependency 到 unit test。

- [ ] **Step 2: 验证 RED**

Run: `python3 -m unittest tests/test_gdb_stub_probe.py -v`

Expected: FAIL，因为 `RspClient` 尚不存在。

- [ ] **Step 3: 实现最小 raw probe**

CLI 只发送 `qSupported`、`?`、`g`、一组安全 BRAM `m`，打印 payload 并以非零 exit code 报 checksum/timeout/长度错误。物理串口通过标准库无法配置 raw baud，因此 CLI 使用已经存在的系统 `stty` 配置 fd，不新增 Python dependency。

- [ ] **Step 4: 验证 GREEN 与 SoC RSP 回归**

Run:

```bash
python3 -m unittest tests/test_gdb_stub_probe.py -v
./sim/run_sim.sh gdb_stub
```

Expected: unit tests 与 CPU+UART RSP 回归均 PASS。真实 `gdb-multiarch` session 保留到 Task 5 的物理串口验收，不用第二份假 target 重复模拟。

- [ ] **Step 5: 更新开发文档并 Commit**

```bash
git add scripts/gdb_stub_probe.py tests/test_gdb_stub_probe.py scripts/test_catalog.json docs/DEV_FLOW.md
git commit -m "test: 增加 GDB host 兼容探测"
```

---

### Task 5: 完成回归、综合与上板验收

**Files:**
- Modify: `docs/DEV_FLOW.md`
- Modify: `docs/PROBES.md`（仅在实际上板步骤需要记录时）

**Interfaces:**
- Consumes: Tasks 1～4 全部 artifact。
- Produces: 可构建、可仿真、可由 GDB 连接的 issue #23 MVP。

- [ ] **Step 1: 串行运行完整相关回归**

Run：

```bash
python3 scripts/test_runner.py run-suite platform --keep-going
python3 scripts/test_runner.py run-suite soc --keep-going
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
python3 scripts/test_runner.py run-suite rv32i_safe --keep-going
```

Expected: platform 及 SoC 全部 PASS，RV32MI 10/10，RV32I safe PASS。禁止并行运行这些共享 `sim/build` 的 suite。

- [ ] **Step 2: 构建独立 firmware artifact**

Run:

```bash
FIRMWARE_MAIN=firmware/tests/gdb_stub_smoke.c \
FIRMWARE_PROFILE=gdb_stub \
FIRMWARE_OUT=firmware/build/gdb_stub/firmware \
./scripts/build_firmware.sh
```

Expected: `.elf/.bin/.mem/.lst` 全部生成，BRAM image 低于 64 KiB。

- [ ] **Step 3: ISE Map/PAR 验证**

使用现有 full MiniSoC export/build 路径，确认 Map 无 `OVERMAPPED`、资源未超容量、50 MHz post-route timing slack 为正，且 GDB firmware 不要求新增 RTL。

- [ ] **Step 4: 物理串口验收**

```text
1. loader 上传 gdb_stub firmware.bin，收到 ACK 后退出并关闭串口。
2. raw probe 连接同一串口，验证 ? / g / m。
3. gdb-multiarch 加载 firmware.elf。
4. set serial baud 9600；target remote /dev/ttyUSB*。
5. info registers；x/8wx 0x80000000；set $a0=...；continue。
6. 确认 continue 后 firmware 写 test_exit=1，UART 无应用日志污染。
```

- [ ] **Step 5: 记录不确定项并 Commit**

若本轮无法访问物理板或 ISE，必须在文档里明确保留未验证项，不得把仿真结果写成上板通过。完成可用证据后：

```bash
git add docs/DEV_FLOW.md docs/PROBES.md
git commit -m "docs: 记录 GDB stub 验收流程"
```

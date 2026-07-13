// 来源：riscv-software-src/riscv-tests 的 benchmarks/median。
// 本文件只替换 platform 层：计数器、输出和 test_exit；kernel 与 dataset 原样引用。
#include "tests/testlib.h"
#include "drivers/perf.h"
#include "runtime/rt_alloc.h"
#include "runtime/rt_string.h"

#include "../../../../tests/riscv_tests/riscv-tests/benchmarks/median/median.c"
#include "../../../../tests/riscv_tests/riscv-tests/benchmarks/median/dataset1.h"

static int bram_input[DATA_SIZE];
static int bram_result[DATA_SIZE];

static void report_result(const char *memory, const perf_snapshot_t *snap)
{
    uart_puts("RESULT: benchmark=riscv_tests_median memory=");
    uart_puts(memory);
    uart_puts(" elements=");
    uart_put_dec(DATA_SIZE);
    uart_puts(" cycles=");
    uart_put_dec(snap->cycle);
    uart_puts(" instret=");
    uart_put_dec(snap->instret);
    uart_puts(" mem_wait=");
    uart_put_dec(snap->mem_wait);
    uart_puts("\n");
}

static void verify_result(const int *result, unsigned int error_base)
{
    unsigned int i;

    for (i = 0u; i < DATA_SIZE; i++) {
        test_expect(result[i] == verify_data[i], error_base + i);
    }
}

int main(void)
{
    perf_snapshot_t snap;
    int *sdram_input;
    int *sdram_result;

    test_banner("riscv_tests_median");
    rt_memcpy(bram_input, input_data, sizeof(input_data));
    perf_begin(&snap);
    median(DATA_SIZE, bram_input, bram_result);
    perf_end(&snap);
    verify_result(bram_result, 0xdead5000u);
    report_result("bram", &snap);

    heap_init();
    sdram_input = (int *)bump_alloc(sizeof(input_data), 4u);
    sdram_result = (int *)bump_alloc(sizeof(bram_result), 4u);
    test_expect(sdram_input != 0 && sdram_result != 0, 0xdead5100u);
    rt_memcpy(sdram_input, input_data, sizeof(input_data));
    perf_begin(&snap);
    median(DATA_SIZE, sdram_input, sdram_result);
    perf_end(&snap);
    verify_result(sdram_result, 0xdead5200u);
    report_result("sdram", &snap);

    test_pass();
    return 0;
}

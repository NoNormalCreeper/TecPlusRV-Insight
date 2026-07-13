// 来源：riscv-software-src/riscv-tests 的 benchmarks/memcpy。
// 保留 upstream dataset，分别测量 BRAM->BRAM 与 SDRAM->SDRAM 的标准 memcpy。
#include "tests/testlib.h"
#include "drivers/perf.h"
#include "runtime/rt_alloc.h"
#include "runtime/rt_string.h"

#include "../../../../tests/riscv_tests/riscv-tests/benchmarks/memcpy/dataset1.h"

static int bram_result[DATA_SIZE];

static void report_result(const char *path, const perf_snapshot_t *snap)
{
    uart_puts("RESULT: benchmark=riscv_tests_memcpy path=");
    uart_puts(path);
    uart_puts(" bytes=");
    uart_put_dec(sizeof(input_data));
    uart_puts(" cycles=");
    uart_put_dec(snap->cycle);
    uart_puts(" instret=");
    uart_put_dec(snap->instret);
    uart_puts(" mem_wait=");
    uart_put_dec(snap->mem_wait);
    uart_puts("\n");
}

static void verify_copy(const int *result, unsigned int error_base)
{
    unsigned int i;

    for (i = 0u; i < DATA_SIZE; i++) {
        test_expect(result[i] == input_data[i], error_base + i);
    }
}

int main(void)
{
    perf_snapshot_t snap;
    int *sdram_input;
    int *sdram_result;

    test_banner("riscv_tests_memcpy");
    perf_begin(&snap);
    memcpy(bram_result, input_data, sizeof(input_data));
    perf_end(&snap);
    verify_copy(bram_result, 0xdead6000u);
    report_result("bram_to_bram", &snap);

    heap_init();
    sdram_input = (int *)bump_alloc(sizeof(input_data), 4u);
    sdram_result = (int *)bump_alloc(sizeof(input_data), 4u);
    test_expect(sdram_input != 0 && sdram_result != 0, 0xdead6100u);
    rt_memcpy(sdram_input, input_data, sizeof(input_data));
    perf_begin(&snap);
    memcpy(sdram_result, sdram_input, sizeof(input_data));
    perf_end(&snap);
    verify_copy(sdram_result, 0xdead6200u);
    report_result("sdram_to_sdram", &snap);

    test_pass();
    return 0;
}

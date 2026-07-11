// FreeRTOS profile 的最小编译契约；不启动 scheduler。
#include "FreeRTOS.h"
#include "event_groups.h"
#include "task.h"
#include "timers.h"

#include "drivers/mmio.h"

_Static_assert(configSUPPORT_STATIC_ALLOCATION == 1,
    "FreeRTOS profile 必须支持静态分配");
_Static_assert(configSUPPORT_DYNAMIC_ALLOCATION == 1,
    "FreeRTOS profile 必须支持动态分配");
_Static_assert(configUSE_PREEMPTION == 1,
    "FreeRTOS profile 必须启用抢占");

static volatile unsigned int keep_dynamic_modules;

static void contract_timer_callback(TimerHandle_t timer)
{
    (void)timer;
}

int main(void)
{
    // 只保留链接引用；build contract 不会实际进入这个分支。
    if (keep_dynamic_modules != 0u) {
        HeapRegion_t regions[1] = {{0, 0u}};

        vPortDefineHeapRegions(regions);
        (void)xTimerCreate("contract", 1u, pdFALSE, 0,
            contract_timer_callback);
        (void)xEventGroupCreate();
    }

    mmio_write(TINYBUS_TEST_EXIT, 1u);

    for (;;) {
    }
}

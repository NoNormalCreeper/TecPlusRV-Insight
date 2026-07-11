// FreeRTOS profile 的最小编译契约；不启动 scheduler。
#include "FreeRTOS.h"
#include "task.h"

#include "drivers/mmio.h"

_Static_assert(configSUPPORT_STATIC_ALLOCATION == 1,
    "FreeRTOS 首轮必须支持静态分配");
_Static_assert(configSUPPORT_DYNAMIC_ALLOCATION == 0,
    "FreeRTOS 首轮不得启用动态分配");
_Static_assert(configUSE_PREEMPTION == 1,
    "FreeRTOS 首轮必须启用抢占");

int main(void)
{
    mmio_write(TINYBUS_TEST_EXIT, 1u);

    for (;;) {
    }
}

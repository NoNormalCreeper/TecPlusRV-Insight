// FreeRTOS heap_5 的 linker region 适配；bare-metal bump allocator 不经过这里。
#include "FreeRTOS.h"

#include "freertos_heap.h"

extern unsigned char _heap_start[];
extern unsigned char _heap_end[];

static unsigned int heap_initialized;

void freertos_heap_init(void)
{
    HeapRegion_t regions[2];

    configASSERT(heap_initialized == 0u);
    regions[0].pucStartAddress = _heap_start;
    regions[0].xSizeInBytes = (size_t)(_heap_end - _heap_start);
    regions[1].pucStartAddress = 0;
    regions[1].xSizeInBytes = 0u;
    vPortDefineHeapRegions(regions);
    heap_initialized = 1u;
}

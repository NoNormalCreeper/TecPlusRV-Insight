#include "mmio.h"
#include "traffic_light.h"

#define TRAFFIC_LIGHT_MASK 0x0fffu

void traffic_light_write(unsigned int pattern)
{
    mmio_write(TINYBUS_TRAFFIC_DATA, pattern & TRAFFIC_LIGHT_MASK);
}

unsigned int traffic_light_read(void)
{
    return mmio_read(TINYBUS_TRAFFIC_DATA) & TRAFFIC_LIGHT_MASK;
}

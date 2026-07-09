// Raw 12-bit traffic-light GPIO driver.
#ifndef TRAFFIC_LIGHT_H
#define TRAFFIC_LIGHT_H

void traffic_light_write(unsigned int pattern);
unsigned int traffic_light_read(void);

#endif

// Programmable square-wave buzzer driver.
#ifndef BUZZER_H
#define BUZZER_H

void buzzer_set_half_period(unsigned int clock_ticks);
unsigned int buzzer_get_half_period(void);
void buzzer_start(unsigned int half_period_ticks);
void buzzer_start_hz(unsigned int clock_hz, unsigned int tone_hz);
void buzzer_stop(void);
unsigned int buzzer_is_enabled(void);

#endif

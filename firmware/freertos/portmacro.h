// FreeRTOS kernel 与 TecPlusRV RV32I machine-mode port 的最小类型和宏契约。
#ifndef PORTMACRO_H
#define PORTMACRO_H

#include <stddef.h>
#include <stdint.h>

#define portSTACK_TYPE uint32_t
#define portBASE_TYPE int32_t
#define portUBASE_TYPE uint32_t
#define portMAX_DELAY ((TickType_t)0xffffffffUL)
#define portPOINTER_SIZE_TYPE uint32_t

typedef portSTACK_TYPE StackType_t;
typedef portBASE_TYPE BaseType_t;
typedef portUBASE_TYPE UBaseType_t;
typedef uint32_t TickType_t;

#define portSTACK_GROWTH (-1)
#define portTICK_PERIOD_MS ((TickType_t)1000 / configTICK_RATE_HZ)
#define portBYTE_ALIGNMENT 16
#define portTICK_TYPE_IS_ATOMIC 1
#define portCRITICAL_NESTING_IN_TCB 1

void vTaskEnterCritical(void);
void vTaskExitCritical(void);
int freertos_port_in_trap(void);
void freertos_port_enable_interrupts(void);
void freertos_port_request_yield(void);

static inline UBaseType_t freertos_port_set_interrupt_mask(void)
{
    UBaseType_t old_status;
    UBaseType_t mask = 8u;

    __asm__ volatile ("csrrc %0, mstatus, %1"
        : "=r"(old_status) : "r"(mask) : "memory");
    return old_status & mask;
}

static inline void freertos_port_clear_interrupt_mask(UBaseType_t old_mask)
{
    if (old_mask != 0u) {
        __asm__ volatile ("csrs mstatus, %0" :: "r"(8u) : "memory");
    }
}

#define portYIELD() __asm__ volatile ("ecall" ::: "memory")
#define portYIELD_WITHIN_API() \
    portYIELD()
#define portDISABLE_INTERRUPTS() \
    __asm__ volatile ("csrc mstatus, %0" :: "r"(8u) : "memory")
#define portENABLE_INTERRUPTS() \
    freertos_port_enable_interrupts()
#define portENTER_CRITICAL() vTaskEnterCritical()
#define portEXIT_CRITICAL() vTaskExitCritical()
#define portASSERT_IF_IN_ISR() configASSERT(freertos_port_in_trap() == 0)
#define portSET_INTERRUPT_MASK_FROM_ISR() freertos_port_set_interrupt_mask()
#define portCLEAR_INTERRUPT_MASK_FROM_ISR(mask) \
    freertos_port_clear_interrupt_mask(mask)
#define portYIELD_FROM_ISR(need_switch) \
    do { (void)(need_switch); } while (0)

#define portTASK_FUNCTION_PROTO(function, argument) \
    void function(void *argument)
#define portTASK_FUNCTION(function, argument) \
    void function(void *argument)
#define portNOP() __asm__ volatile ("nop")
#define portINLINE inline
#define portFORCE_INLINE inline __attribute__((always_inline))
#define portMEMORY_BARRIER() __asm__ volatile ("" ::: "memory")

#endif

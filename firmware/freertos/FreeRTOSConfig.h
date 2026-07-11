// TecPlusRV 的最小单核 FreeRTOS 配置。
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#ifndef FREERTOS_CPU_CLOCK_HZ
#define FREERTOS_CPU_CLOCK_HZ 50000000UL
#endif

#define configCPU_CLOCK_HZ FREERTOS_CPU_CLOCK_HZ
#define configTICK_RATE_HZ 1000U
#define configUSE_PREEMPTION 1
#define configUSE_TIME_SLICING 1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0
#define configUSE_TICKLESS_IDLE 0
#define configMAX_PRIORITIES 4U
#define configMINIMAL_STACK_SIZE 128U
#define configMAX_TASK_NAME_LEN 16U
#define configTICK_TYPE_WIDTH_IN_BITS TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD 1
#define configUSE_IDLE_HOOK 0
#define configUSE_TICK_HOOK 0
#define configUSE_CO_ROUTINES 0

#define configUSE_TASK_NOTIFICATIONS 1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES 1
#define configQUEUE_REGISTRY_SIZE 0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS 0
#define configUSE_NEWLIB_REENTRANT 0
#define configUSE_C_RUNTIME_TLS_SUPPORT 0
#define configUSE_POSIX_ERRNO 0

#define configUSE_TIMERS 1
#define configTIMER_TASK_PRIORITY (configMAX_PRIORITIES - 1U)
#define configTIMER_QUEUE_LENGTH 8U
#define configTIMER_TASK_STACK_DEPTH 256U
#define configUSE_EVENT_GROUPS 1
#define configUSE_STREAM_BUFFERS 0
#define configSUPPORT_STATIC_ALLOCATION 1
#define configSUPPORT_DYNAMIC_ALLOCATION 1
#define configKERNEL_PROVIDED_STATIC_MEMORY 1
#define configCHECK_FOR_STACK_OVERFLOW 2
#define configUSE_MALLOC_FAILED_HOOK 1

#define configUSE_MUTEXES 1
#define configUSE_RECURSIVE_MUTEXES 0
#define configUSE_COUNTING_SEMAPHORES 1
#define configUSE_QUEUE_SETS 0
#define configUSE_TRACE_FACILITY 0
#define configGENERATE_RUN_TIME_STATS 0
#define configUSE_APPLICATION_TASK_TAG 0
#define configUSE_TASK_PREEMPTION_DISABLE 0
#define configRECORD_STACK_HIGH_ADDRESS 0

#define configENABLE_FPU 0
#define configENABLE_VPU 0

#define INCLUDE_vTaskDelay 1
#define INCLUDE_xTaskDelayUntil 1
#define INCLUDE_vTaskSuspend 0
#define INCLUDE_vTaskDelete 1
#define INCLUDE_uxTaskPriorityGet 1
#define INCLUDE_uxTaskGetStackHighWaterMark 1
#define INCLUDE_uxTaskGetStackHighWaterMark2 0

void freertos_assert_fail(const char *file, unsigned int line);

#define configASSERT(condition) \
    do { \
        if (!(condition)) { \
            freertos_assert_fail(__FILE__, __LINE__); \
        } \
    } while (0)

#endif

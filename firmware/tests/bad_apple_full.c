// 全时长 Bad Apple：FreeRTOS 同步播放 SDRAM 中的 BAM2 bitmap/MIDI asset。
#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#include "drivers/buzzer.h"
#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "drivers/uart.h"
#include "drivers/vga.h"
#include "drivers/traffic_light.h"

#define ASSET_BASE 0x81000000u
#define ASSET_MAGIC 0x324d4142u
#define ASSET_VERSION 2u
#define ASSET_HEADER_WORDS 12u
#define MAX_ASSET_BYTES (16u * 1024u * 1024u)
#define VIDEO_PERIOD_TICKS 6u
#define AUDIO_QUEUE_LENGTH 16u
#define PLAYBACK_STACK_WORDS 768u
#define AUDIO_STACK_WORDS 256u
#define AUX_STACK_WORDS 256u
#define BUTTON_STACK_WORDS 256u
#define REPLAY_DELAY_MS 10000u
#define AUDIO_BEAT_FLAG 0x80000000u
#define ASSET_FLAG_AUDIO_BEATS 0x00000001u
#define MEDIA_PAUSED_BIT 0x01u
#define MEDIA_ACTIVE_BIT 0x02u
#define KEY1_MASK 0x01u
#define TRAFFIC_RED 0x249u
#define TRAFFIC_YELLOW 0x492u
#define TRAFFIC_GREEN 0x924u

struct bam2_info {
    unsigned int total_words;
    unsigned int duration_ticks;
    unsigned int frame_count;
    unsigned int video_word;
    unsigned int video_end_word;
    unsigned int audio_count;
    unsigned int audio_word;
    unsigned int flags;
};

static volatile const unsigned int *const asset =
    (volatile const unsigned int *)ASSET_BASE;

static StaticTask_t playback_tcb;
static StackType_t playback_stack[PLAYBACK_STACK_WORDS]
    __attribute__((aligned(16)));
static StaticTask_t audio_tcb;
static StackType_t audio_stack[AUDIO_STACK_WORDS]
    __attribute__((aligned(16)));
static StaticQueue_t audio_queue_control;
static unsigned char audio_queue_storage[AUDIO_QUEUE_LENGTH * sizeof(unsigned int)]
    __attribute__((aligned(4)));
static QueueHandle_t audio_queue;
static volatile unsigned int media_state_bits;
static StaticTask_t led_tcb;
static StackType_t led_stack[AUX_STACK_WORDS] __attribute__((aligned(16)));
static TaskHandle_t led_handle;
static TaskHandle_t audio_handle;
static TaskHandle_t playback_handle;
static StaticTask_t traffic_tcb;
static StackType_t traffic_stack[AUX_STACK_WORDS] __attribute__((aligned(16)));
static TaskHandle_t traffic_handle;
static StaticTask_t button_tcb;
static StackType_t button_stack[BUTTON_STACK_WORDS] __attribute__((aligned(16)));
static TaskHandle_t button_handle;
static volatile unsigned int playback_elapsed_ticks;

static unsigned int media_state(void)
{
    return media_state_bits;
}

static void media_state_update(unsigned int clear_bits, unsigned int set_bits)
{
    taskENTER_CRITICAL();
    media_state_bits = (media_state_bits & ~clear_bits) | set_bits;
    taskEXIT_CRITICAL();
}

static void fail(unsigned int code, const char *message)
{
    taskENTER_CRITICAL();
    buzzer_stop();
    gpio_write_led(code & 0xfu);
    uart_puts("bad apple full fail: ");
    uart_puts(message);
    uart_puts("\n");
    uart_flush();
    mmio_write(TINYBUS_TEST_EXIT, code);
    for (;;) {
    }
}

static void runtime_fail(unsigned int code, const char *message,
    unsigned int elapsed_ticks, unsigned int frame,
    unsigned int cursor_word, unsigned int value)
{
    taskENTER_CRITICAL();
    buzzer_stop();
    gpio_write_led(code & 0xfu);
    uart_puts("bad apple runtime fail: ");
    uart_puts(message);
    uart_puts("\ncode=");
    uart_put_hex(code);
    uart_puts("\nt=");
    uart_put_dec((elapsed_ticks * 21u) / 1250u);
    uart_puts("s\nf=");
    uart_put_dec(frame);
    uart_puts("\ncursor=");
    uart_put_hex(cursor_word * 4u);
    uart_puts("\nvalue=");
    uart_put_hex(value);
    uart_puts("\n");
    uart_flush();
    mmio_write(TINYBUS_TEST_EXIT, code);
    for (;;) {
    }
}

static unsigned int elapsed_vga_ticks(unsigned int start)
{
    return (vga_frame_count() - start) & 0xffffu;
}

static unsigned int seconds_to_vga_ticks(unsigned int seconds)
{
    // round(seconds * 1250 / 21)，与 640x480 hardware frame rate 一致。
    return (seconds * 1250u + 10u) / 21u;
}

static void print_progress(unsigned int seconds)
{
    // 默认 9600 baud 下保持短行，避免阻塞超过一个约 16.8 ms 的 VGA tick。
    uart_puts("t=");
    uart_put_dec(seconds);
    uart_puts("s\n");
}

static void print_stack_watermarks(void)
{
    uart_puts("stack free words: video=");
    uart_put_dec(uxTaskGetStackHighWaterMark(playback_handle));
    uart_puts(" audio=");
    uart_put_dec(uxTaskGetStackHighWaterMark(audio_handle));
    uart_puts(" led=");
    uart_put_dec(uxTaskGetStackHighWaterMark(led_handle));
    uart_puts(" button=");
    uart_put_dec(uxTaskGetStackHighWaterMark(button_handle));
    uart_puts(" traffic=");
    uart_put_dec(uxTaskGetStackHighWaterMark(traffic_handle));
    uart_puts("\n");
}

static struct bam2_info validate_asset(void)
{
    struct bam2_info info;
    unsigned int total_bytes;
    unsigned int cursor;
    unsigned int frame;
    unsigned int event;
    unsigned int previous_tick = 0u;

    if (asset[0] != ASSET_MAGIC || asset[1] != ASSET_VERSION) {
        fail(0xba01u, "header magic/version");
    }
    total_bytes = asset[2];
    if (total_bytes < ASSET_HEADER_WORDS * 4u ||
        total_bytes > MAX_ASSET_BYTES || (total_bytes & 3u) != 0u) {
        fail(0xba02u, "total bytes");
    }
    info.total_words = total_bytes / 4u;
    info.duration_ticks = asset[3];
    info.frame_count = asset[4];
    info.video_word = asset[5] / 4u;
    info.audio_count = asset[7];
    info.audio_word = asset[8] / 4u;
    info.video_end_word = info.audio_word;
    info.flags = asset[10];
    if (info.duration_ticks == 0u || info.duration_ticks >= 0x8000u ||
        info.frame_count == 0u || asset[5] != ASSET_HEADER_WORDS * 4u ||
        asset[6] != VIDEO_PERIOD_TICKS || (asset[8] & 3u) != 0u ||
        info.audio_word <= info.video_word || info.audio_word > info.total_words ||
        info.audio_count > (info.total_words - info.audio_word) / 2u ||
        info.audio_word + info.audio_count * 2u != info.total_words ||
        asset[9] != VGA_BITMAP_WORDS ||
        (info.flags & ~ASSET_FLAG_AUDIO_BEATS) != 0u || asset[11] != 0u) {
        fail(0xba03u, "header bounds");
    }

    cursor = info.video_word;
    for (frame = 0u; frame < info.frame_count; frame++) {
        unsigned int changes;
        unsigned int change;
        if (cursor >= info.video_end_word) {
            fail(0xba04u, "video truncated");
        }
        changes = asset[cursor++];
        if ((frame == 0u && changes != VGA_BITMAP_WORDS) ||
            changes > VGA_BITMAP_WORDS ||
            changes > (info.video_end_word - cursor) / 2u) {
            fail(0xba05u, "frame diff count");
        }
        for (change = 0u; change < changes; change++) {
            if (asset[cursor] >= VGA_BITMAP_WORDS) {
                fail(0xba06u, "bitmap word index");
            }
            cursor += 2u;
        }
    }
    if (cursor != info.video_end_word) {
        fail(0xba07u, "video trailing words");
    }
    for (event = 0u; event < info.audio_count; event++) {
        unsigned int tick = asset[info.audio_word + event * 2u];
        if (tick >= info.duration_ticks || (event != 0u && tick <= previous_tick)) {
            fail(0xba08u, "audio tick order");
        }
        previous_tick = tick;
    }
    return info;
}

static void audio_task(void *argument)
{
    unsigned int hz;
    (void)argument;
    for (;;) {
        if (xQueueReceive(audio_queue, &hz, portMAX_DELAY) != pdPASS) {
            fail(0xba09u, "audio queue receive");
        }
        if (hz == 0u) {
            buzzer_stop();
        } else {
            buzzer_start_hz(configCPU_CLOCK_HZ, hz);
        }
    }
}

static void traffic_task(void *argument)
{
    static const unsigned int patterns[] = {
        TRAFFIC_GREEN, TRAFFIC_YELLOW, TRAFFIC_RED,
    };
    unsigned int index = 0u;
    (void)argument;

    for (;;) {
        // 颜色位序来自已验证的 traffic/audio demo；若教学大板映射不同，只校准常量。
        traffic_light_write(patterns[index]);
        index = (index + 1u) % 3u;
        vTaskDelay(pdMS_TO_TICKS(500u));
    }
}

static void led_task(void *argument)
{
    unsigned int beat = 0u;
    unsigned int runner = 0u;
    (void)argument;

    for (;;) {
        unsigned int bits = media_state();
        if ((bits & MEDIA_ACTIVE_BIT) != 0u &&
            (bits & MEDIA_PAUSED_BIT) == 0u) {
            unsigned int count = ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(50u));
            while (count != 0u) {
                gpio_write_led(1u << beat);
                beat = (beat + 1u) & 3u;
                count--;
            }
        } else {
            (void)ulTaskNotifyTake(pdTRUE, 0u);
            gpio_write_led(1u << runner);
            runner = (runner + 1u) & 3u;
            vTaskDelay(pdMS_TO_TICKS(100u));
        }
    }
}

static void print_pause_state(unsigned int paused)
{
    taskENTER_CRITICAL();
    uart_puts(paused ? "paused at t=" : "resumed at t=");
    uart_put_dec((playback_elapsed_ticks * 21u) / 1250u);
    uart_puts("s\n");
    uart_flush();
    taskEXIT_CRITICAL();
}

static void button_task(void *argument)
{
    unsigned int sampled_pressed = 0u;
    unsigned int stable_pressed = 0u;
    unsigned int stable_count = 0u;
    (void)argument;

    for (;;) {
        unsigned int pressed = (gpio_read_key() & KEY1_MASK) == 0u;
        if (pressed == sampled_pressed) {
            if (stable_count < 3u) {
                stable_count++;
            }
        } else {
            sampled_pressed = pressed;
            stable_count = 1u;
        }
        if (stable_count == 3u && stable_pressed != sampled_pressed) {
            stable_pressed = sampled_pressed;
            if (stable_pressed) {
                unsigned int bits = media_state();
                if ((bits & MEDIA_PAUSED_BIT) != 0u) {
                    media_state_update(MEDIA_PAUSED_BIT, 0u);
                    print_pause_state(0u);
                } else {
                    media_state_update(0u, MEDIA_PAUSED_BIT);
                    print_pause_state(1u);
                }
            }
        }
        vTaskDelay(pdMS_TO_TICKS(10u));
    }
}

static void playback_task(void *argument)
{
    struct bam2_info info = validate_asset();
    unsigned int completed_once = 0u;
    (void)argument;

    while (!vga_is_ready()) {
        taskYIELD();
    }
    uart_puts("bad apple full start\n");
    for (;;) {
        unsigned int video_cursor = info.video_word;
        unsigned int audio_index = 0u;
        unsigned int frame = 0u;
        unsigned int start = vga_frame_count();
        unsigned int next_progress_second = 1u;
        unsigned int previous_audio_tick = 0u;
        unsigned int current_hz = 0u;

        media_state_update(MEDIA_PAUSED_BIT, MEDIA_ACTIVE_BIT);
        playback_elapsed_ticks = 0u;

        while (elapsed_vga_ticks(start) < info.duration_ticks) {
            unsigned int elapsed = elapsed_vga_ticks(start);
            if ((media_state() & MEDIA_PAUSED_BIT) != 0u) {
                unsigned int pause_start = vga_frame_count();
                unsigned int silence = 0u;
                if (xQueueSendToFront(audio_queue, &silence, portMAX_DELAY) != pdPASS) {
                    fail(0xba10u, "audio pause queue");
                }
                while ((media_state() & MEDIA_PAUSED_BIT) != 0u) {
                    vTaskDelay(pdMS_TO_TICKS(10u));
                }
                start += elapsed_vga_ticks(pause_start);
                if (xQueueSendToFront(audio_queue, &current_hz, portMAX_DELAY) != pdPASS) {
                    fail(0xba11u, "audio resume queue");
                }
                elapsed = elapsed_vga_ticks(start);
            }
            playback_elapsed_ticks = elapsed;
            while (frame < info.frame_count &&
                   frame * VIDEO_PERIOD_TICKS <= elapsed) {
                unsigned int changes;
                unsigned int change;
                if (video_cursor >= info.video_end_word) {
                    runtime_fail(0xba13u, "video cursor", elapsed, frame,
                        video_cursor, info.video_end_word);
                }
                changes = asset[video_cursor++];
                if (changes > VGA_BITMAP_WORDS ||
                    changes > (info.video_end_word - video_cursor) / 2u) {
                    runtime_fail(0xba14u, "frame diff count", elapsed, frame,
                        video_cursor - 1u, changes);
                }
                for (change = 0u; change < changes; change++) {
                    unsigned int index = asset[video_cursor++];
                    unsigned int value = asset[video_cursor++];
                    if (index >= VGA_BITMAP_WORDS) {
                        runtime_fail(0xba15u, "bitmap word index", elapsed,
                            frame, video_cursor - 2u, index);
                    }
                    vga_bitmap_write_word(index, value);
                }
                frame++;
            }
            while (audio_index < info.audio_count) {
                unsigned int event_word = info.audio_word + audio_index * 2u;
                unsigned int event_tick = asset[event_word];
                unsigned int value;
                unsigned int hz;
                if (event_tick >= info.duration_ticks ||
                    (audio_index != 0u && event_tick <= previous_audio_tick)) {
                    runtime_fail(0xba16u, "audio tick", elapsed, frame,
                        event_word, event_tick);
                }
                if (event_tick > elapsed) {
                    break;
                }
                value = asset[event_word + 1u];
                hz = value & ~AUDIO_BEAT_FLAG;
                if (hz > 5000u) {
                    runtime_fail(0xba17u, "audio frequency", elapsed, frame,
                        event_word + 1u, hz);
                }
                if ((value & AUDIO_BEAT_FLAG) != 0u) {
                    xTaskNotifyGive(led_handle);
                }
                if (hz != current_hz) {
                    if (xQueueSend(audio_queue, &hz, 0u) != pdPASS) {
                        fail(0xba0au, "audio queue full");
                    }
                    current_hz = hz;
                }
                previous_audio_tick = event_tick;
                audio_index++;
            }
            if (elapsed >= seconds_to_vga_ticks(next_progress_second)) {
                print_progress(next_progress_second);
                if (next_progress_second == 1u) {
                    print_stack_watermarks();
                }
                next_progress_second++;
            }
            // 1 ms 周期远小于约 16.8 ms VGA tick；阻塞让低优先级可见任务获得 CPU，
            // 同时避免 tight-loop ecall 制造无意义的 context switch 压力。
            vTaskDelay(1u);
        }
        if (frame != info.frame_count || video_cursor != info.video_end_word ||
            audio_index != info.audio_count) {
            fail(0xba0bu, "stream did not finish");
        }
        {
            unsigned int silence = 0u;
            if (xQueueSend(audio_queue, &silence, portMAX_DELAY) != pdPASS) {
                fail(0xba0cu, "audio stop queue");
            }
        }
        uart_puts("\nbad apple full pass\n");
        uart_flush();
        gpio_write_led(5u);
        media_state_update(MEDIA_ACTIVE_BIT, 0u);
        if (!completed_once) {
            mmio_write(TINYBUS_TEST_EXIT, 1u);
            completed_once = 1u;
        }
        vTaskDelay(pdMS_TO_TICKS(REPLAY_DELAY_MS));
    }
}

int main(void)
{
    gpio_write_led(1u);
    uart_puts("bad apple full boot\n");
    audio_queue = xQueueCreateStatic(AUDIO_QUEUE_LENGTH, sizeof(unsigned int),
        audio_queue_storage, &audio_queue_control);
    media_state_bits = 0u;
    if (audio_queue == 0) {
        fail(0xba0du, "queue create");
    }
    led_handle = xTaskCreateStatic(led_task, "bad-led", AUX_STACK_WORDS, 0, 1u,
        led_stack, &led_tcb);
    audio_handle = xTaskCreateStatic(audio_task, "bad-audio", AUDIO_STACK_WORDS,
        0, 3u, audio_stack, &audio_tcb);
    playback_handle = xTaskCreateStatic(playback_task, "bad-video",
        PLAYBACK_STACK_WORDS, 0, 2u, playback_stack, &playback_tcb);
    button_handle = xTaskCreateStatic(button_task, "bad-button",
        BUTTON_STACK_WORDS, 0, 3u, button_stack, &button_tcb);
    traffic_handle = xTaskCreateStatic(traffic_task, "bad-traffic",
        AUX_STACK_WORDS, 0, 1u, traffic_stack, &traffic_tcb);
    if (led_handle == 0 || audio_handle == 0 || playback_handle == 0 ||
        button_handle == 0 || traffic_handle == 0) {
        fail(0xba0eu, "task create");
    }
    vTaskStartScheduler();
    fail(0xba0fu, "scheduler returned");
    return 0;
}

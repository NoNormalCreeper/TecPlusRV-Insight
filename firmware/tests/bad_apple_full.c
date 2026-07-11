// 全时长 Bad Apple：FreeRTOS 同步播放 SDRAM 中的 BAM2 bitmap/MIDI asset。
#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#include "drivers/buzzer.h"
#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "drivers/uart.h"
#include "drivers/vga.h"

#define ASSET_BASE 0x81000000u
#define ASSET_MAGIC 0x324d4142u
#define ASSET_VERSION 2u
#define ASSET_HEADER_WORDS 12u
#define MAX_ASSET_BYTES (16u * 1024u * 1024u)
#define VIDEO_PERIOD_TICKS 6u
#define AUDIO_QUEUE_LENGTH 16u
#define PLAYBACK_STACK_WORDS 768u
#define AUDIO_STACK_WORDS 256u

struct bam2_info {
    unsigned int total_words;
    unsigned int duration_ticks;
    unsigned int frame_count;
    unsigned int video_word;
    unsigned int video_end_word;
    unsigned int audio_count;
    unsigned int audio_word;
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
    if (info.duration_ticks == 0u || info.duration_ticks >= 0x8000u ||
        info.frame_count == 0u || asset[5] != ASSET_HEADER_WORDS * 4u ||
        asset[6] != VIDEO_PERIOD_TICKS || (asset[8] & 3u) != 0u ||
        info.audio_word <= info.video_word || info.audio_word > info.total_words ||
        info.audio_count > (info.total_words - info.audio_word) / 2u ||
        info.audio_word + info.audio_count * 2u != info.total_words ||
        asset[9] != VGA_BITMAP_WORDS || asset[10] != 0u || asset[11] != 0u) {
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

        while (elapsed_vga_ticks(start) < info.duration_ticks) {
            unsigned int elapsed = elapsed_vga_ticks(start);
            while (frame < info.frame_count &&
                   frame * VIDEO_PERIOD_TICKS <= elapsed) {
                unsigned int changes = asset[video_cursor++];
                unsigned int change;
                for (change = 0u; change < changes; change++) {
                    unsigned int index = asset[video_cursor++];
                    unsigned int value = asset[video_cursor++];
                    vga_bitmap_write_word(index, value);
                }
                frame++;
            }
            while (audio_index < info.audio_count &&
                   asset[info.audio_word + audio_index * 2u] <= elapsed) {
                unsigned int hz = asset[info.audio_word + audio_index * 2u + 1u];
                if (xQueueSend(audio_queue, &hz, 0u) != pdPASS) {
                    fail(0xba0au, "audio queue full");
                }
                audio_index++;
            }
            if (elapsed >= seconds_to_vga_ticks(next_progress_second)) {
                print_progress(next_progress_second);
                next_progress_second++;
            }
            taskYIELD();
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
        if (!completed_once) {
            mmio_write(TINYBUS_TEST_EXIT, 1u);
            completed_once = 1u;
        }
        vTaskDelay(500u);
    }
}

int main(void)
{
    gpio_write_led(1u);
    uart_puts("bad apple full boot\n");
    audio_queue = xQueueCreateStatic(AUDIO_QUEUE_LENGTH, sizeof(unsigned int),
        audio_queue_storage, &audio_queue_control);
    if (audio_queue == 0) {
        fail(0xba0du, "queue create");
    }
    if (xTaskCreateStatic(audio_task, "bad-audio", AUDIO_STACK_WORDS, 0, 3u,
            audio_stack, &audio_tcb) == 0 ||
        xTaskCreateStatic(playback_task, "bad-video", PLAYBACK_STACK_WORDS, 0, 2u,
            playback_stack, &playback_tcb) == 0) {
        fail(0xba0eu, "task create");
    }
    vTaskStartScheduler();
    fail(0xba0fu, "scheduler returned");
    return 0;
}

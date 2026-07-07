#include "testlib.h"

int main(void)
{
    // 故意不走 UART，用来区分“通用 regression bench”与“board-top smoke bench”。
    test_pass();
    return 0;
}

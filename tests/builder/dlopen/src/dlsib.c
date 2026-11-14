/* Links libsib.so.1, which dlopen()s libself.so.1 from the directory it lives in. */
#include <stdio.h>

int sib_value(void);

int main(void) {
        int v = sib_value();
        printf("sib %d\n", v);
        return v == 42 ? 0 : 1;
}

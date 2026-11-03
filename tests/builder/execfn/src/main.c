/* Linked to libz: its NEEDED is $ORIGIN-relative, so ld.so must know the executable's directory */
#include <stdio.h>
#include <zlib.h>

int main(void) {
        printf("zlib %s\n", zlibVersion());
        return 0;
}

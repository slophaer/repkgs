/* Prints the argv[0] the launcher passed on */
#include <stdio.h>

int main(int argc, char **argv) {
        (void)argc;
        printf("hello %s\n", argv[0]);
        return 0;
}

/* exec-as FILE ARGV0 [ARG...]: execv FILE with ARGV0 as argv[0], as gnupg starts its agent */
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
        if (argc < 3) {
                fprintf(stderr, "usage: exec-as FILE ARGV0 [ARG...]\n");
                return 2;
        }
        execv(argv[1], argv + 2);
        perror(argv[1]);
        return 127;
}

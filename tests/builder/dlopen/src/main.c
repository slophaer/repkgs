/* A binary that loads libz only by dlopen(3), and says so the way systemd does (ELF_NOTE_DLOPEN):
 * a .note.dlopen note of owner "FDO", type 0x407c0c0a, with a JSON array that names the soname. */
#include <dlfcn.h>
#include <stdio.h>

#define NOTE_JSON "[{\"feature\":\"zlib\",\"description\":\"test\",\"priority\":\"required\",\"soname\":[\"libz.so.1\"]}]"

struct note {
        unsigned int namesz, descsz, type;
        char name[4];
        char desc[(sizeof(NOTE_JSON) + 3) & ~3];
};

__attribute__((used, section(".note.dlopen"), aligned(4)))
static const struct note dlopen_note = {
        .namesz = 4,
        .descsz = sizeof(NOTE_JSON),
        .type = 0x407c0c0a,
        .name = "FDO",
        .desc = NOTE_JSON,
};

int main(void) {
        void *h = dlopen("libz.so.1", RTLD_NOW);
        if (!h) {
                fprintf(stderr, "dlopen: %s\n", dlerror());
                return 1;
        }
        const char *(*version)(void) = (const char *(*)(void)) dlsym(h, "zlibVersion");
        if (!version) {
                fprintf(stderr, "dlsym: %s\n", dlerror());
                return 1;
        }
        printf("zlib %s\n", version());
        return 0;
}

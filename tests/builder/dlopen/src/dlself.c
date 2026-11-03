/* A binary that dlopen()s a library the package ships itself, named only in .note.dlopen. The
 * RUNPATH is $ORIGIN-relative, so the library is found from the store and from a moved copy. */
#include <dlfcn.h>
#include <stdio.h>

#define NOTE_JSON "[{\"feature\":\"self\",\"description\":\"test\",\"priority\":\"required\",\"soname\":[\"libself.so.1\"]}]"

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
        void *h = dlopen("libself.so.1", RTLD_NOW);
        if (!h) {
                fprintf(stderr, "dlopen: %s\n", dlerror());
                return 1;
        }
        int (*value)(void) = (int (*)(void)) dlsym(h, "self_value");
        if (!value) {
                fprintf(stderr, "dlsym: %s\n", dlerror());
                return 1;
        }
        printf("self %d\n", value());
        return 0;
}

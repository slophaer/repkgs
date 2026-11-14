/* A library that dlopen()s a sibling library of its package by soname, with no .note.dlopen
 * (libtss2-tctildr and its TCTIs, libpcsclite and libpcsclite_real): its own directory must be
 * on its RUNPATH. */
#include <dlfcn.h>
#include <stdio.h>

int sib_value(void) {
        void *h = dlopen("libself.so.1", RTLD_NOW);
        if (!h) {
                fprintf(stderr, "dlopen: %s\n", dlerror());
                return -1;
        }
        int (*value)(void) = (int (*)(void)) dlsym(h, "self_value");
        return value ? value() : -1;
}

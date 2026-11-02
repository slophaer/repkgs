/* C++ twin of p.c: no includes, the raw compiler has no sysroot */
extern "C" void sink(char *);
extern "C" int fortified;
#ifdef _FORTIFY_SOURCE
int fortified = _FORTIFY_SOURCE;
#else
int fortified = 0;
#endif
extern "C" void f(void) {
  char buf[64];
  sink(buf);
}

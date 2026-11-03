/* no includes: the raw compiler has no sysroot */
extern void sink(char *);
#ifdef _FORTIFY_SOURCE
int fortified = _FORTIFY_SOURCE;
#endif
void f(void) {
  char buf[64];
  sink(buf);
}

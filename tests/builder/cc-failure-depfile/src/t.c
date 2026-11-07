// fails under -Werror on purpose, after the preprocessor has written the depfile (the kernel's
// lib/test_fortify compiles expect exactly that)
#include "t.h"
int f(void) {
  int unused;
  return T_VALUE;
}

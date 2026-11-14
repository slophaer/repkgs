/* clang's __DATE__ and __TIME__: SOURCE_DATE_EPOCH's, not the build's clock */
#include <stdio.h>

int main(void) {
  printf("%s %s\n", __DATE__, __TIME__);
  return 0;
}

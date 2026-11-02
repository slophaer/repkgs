/* one argument per line, then INNER and OUTER when set */
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  for (int i = 1; i < argc; i++)
    puts(argv[i]);
  const char *names[] = {"INNER", "OUTER"};
  for (int i = 0; i < 2; i++)
    if (getenv(names[i]))
      printf("%s=%s\n", names[i], getenv(names[i]));
  return 0;
}

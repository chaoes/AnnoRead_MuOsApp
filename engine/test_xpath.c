#include "legado_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static char *read_file(const char *p) {
  FILE *f = fopen(p, "rb");
  if (!f)
    return NULL;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  rewind(f);
  char *s = malloc(n + 1);
  if (!s) {
    fclose(f);
    return NULL;
  }
  if (fread(s, 1, n, f) != (size_t)n) {
    free(s);
    fclose(f);
    return NULL;
  }
  s[n] = 0;
  fclose(f);
  return s;
}
int main(void) {
  if (!legado_init())
    return 2;
  char *script = read_file("native-regression.js");
  if (!script) {
    perror("native-regression.js");
    return 2;
  }
  char *out = legado_eval(script);
  free(script);
  if (!out || !strstr(out, "\"passed\":12") ||
      !strstr(out, "\"parent axis retains document\"")) {
    fprintf(stderr, "native XPath semantic regression failed: %s\n",
            out ? out : "(null)");
    return 1;
  }
  legado_free_string(out);
  legado_free();
  puts("12 exact native XPath semantics passed");
  return 0;
}

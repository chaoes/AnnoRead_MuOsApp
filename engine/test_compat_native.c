#include "legado_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  const char *path = argc > 1 ? argv[1] : "engine/test_compat.js";
  FILE *f = fopen(path, "rb");
  if (!f) { perror(path); return 2; }
  if (fseek(f, 0, SEEK_END) != 0) return 2;
  long len = ftell(f);
  if (len < 0 || fseek(f, 0, SEEK_SET) != 0) return 2;
  char *script = malloc((size_t)len + 1);
  if (!script) return 2;
  if (fread(script, 1, (size_t)len, f) != (size_t)len) return 2;
  script[len] = '\0';
  fclose(f);

  if (!legado_init()) return 2;
  char *result = legado_eval(script);
  if (!result || strcmp(result, "true") != 0) {
    char *err = legado_eval("(() => { try { return globalThis.__lastCompatError || 'none'; } catch (e) { return String(e); } })()");
    fprintf(stderr, "compatibility regression failed: %s (err: %s)\n", result ? result : "(null)", err ? err : "(null)");
    legado_free_string(err);
    legado_free_string(result);
    free(script);
    return 1;
  }
  puts("native Legado compatibility regressions passed");
  legado_free_string(result);
  free(script);
  return 0;
}

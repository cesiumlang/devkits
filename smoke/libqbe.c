/* Smoke test of libqbe.a: run QBE in-process, as a compiler would.
 * usage: libqbe <target> <in.ssa> <out.s>
 * qbe_main does not return (see qbe.h).
 */
#include "qbe.h"

#include <stdio.h>

int main(int argc, char *argv[]) {
  char *args[7];
  if (argc != 4) {
    fprintf(stderr, "usage: libqbe <target> <in.ssa> <out.s>\n");
    return 2;
  }
  args[0] = "qbe";
  args[1] = "-t";
  args[2] = argv[1];
  args[3] = "-o";
  args[4] = argv[3];
  args[5] = argv[2];
  args[6] = 0;
  return qbe_main(6, args);
}

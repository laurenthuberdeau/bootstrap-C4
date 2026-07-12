// extract.c - recover the embedded source lines from an assembly file
//
// Prints the text following each "#:" line prefix, i.e. the equivalent
// of: sed -n 's/^#://p'
//
// Written in the C4 subset of C so that it can be run by c4 itself:
//   ./c4 extract.c c4.s > c4-extracted.c

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#define int long long

int main(int argc, char **argv)
{
  int fd, i, n, poolsz;
  char *p;

  --argc; ++argv;
  if (argc < 1) { printf("usage: extract file\n"); return -1; }

  poolsz = 256*1024; // arbitrary size, same as c4
  if (!(p = malloc(poolsz)))            { printf("could not malloc(%d)\n", poolsz); return -1; }
  if ((fd = open(*argv, 0)) < 0)        { printf("could not open(%s)\n", *argv); return -1; }
  if ((n = read(fd, p, poolsz-1)) <= 0) { printf("read() returned %d\n", n); return -1; }
  p[n] = 0;
  close(fd);

  i = 0;
  while (i < n) {
    if (p[i] == '#' && p[i+1] == ':') {
      i = i + 2;
      while (i < n && p[i] != '\n') { printf("%c", p[i]); i = i + 1; }
      printf("\n");
    }
    else {
      while (i < n && p[i] != '\n') i = i + 1;
    }
    i = i + 1;
  }
  return 0;
}

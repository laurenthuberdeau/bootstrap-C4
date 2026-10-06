# c4 for bootstrapping pnut-exe

Extended version of the original c4 with features that must be supported to
bootstrap [`pnut-exe`](https://github.com/udem-dlteam/pnut). These features are:

1. Support for forward declarations and mutually recursive functions.
2. Support for `continue` and `break` statements in loops.
3. Support for the `write` libc function.
4. Support the `mode` parameter for the `open` libc function.
5. Support `\0` character escape.
6. Support local and global variable initializers.

These additions are all that's required to bootstrap `pnut-exe` from c4. Of
course, c4 can't read pnut's source code directly, because pnut's source code
uses the C preprocessor to mask out and replace incompatible constructs, which
c4 doesn't support. As a result, a c4-compatible C preprocessor must first be
implemented.

## [`cpp.c`](./cpp.c)

A c4-compatible C preprocessor, taken from pnut's source code. The preprocessor
is a simplified version of pnut's preprocessor, supporting the following
constructs:

- Object macros such as `#define FOO 123`
- Function-like macros such as `#define BAR(X) X + FOO`
- Macro undefinition: `#undef`
- Conditional groups: `#if`, `#ifdef`, `#ifndef`, `#else`, `#elif` and `#endif`
- Diagnostic macros: `#warning` and `#error`
- Predefined macros: `__FILE__` and `__LINE__`
- System and user includes: `#include <stdio.h>` and `#include "foo.h"`

Missing features some people may expect from a C preprocessor:

- Self-referential macros
- Token pasting
- Stringizing

Porting part of pnut's source code to c4 also demonstrated that the code is
already pretty close to the C subset supported by c4. This demonstrates the
viability of porting the entire `pnut-exe` to c4.

To execute:
```shell
$ gcc -o c4 c4.c       # Compile c4
$ ./c4 cpp.c cpp.c    # Execute cpp.c with c4, and preprocess cpp.c
```

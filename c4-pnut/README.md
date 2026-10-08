# c4 for bootstrapping pnut-exe

Extended version of the original c4 with features that must be supported to
bootstrap [`pnut-exe`](https://github.com/udem-dlteam/pnut). These features are:

1. Support for forward declarations and mutually recursive functions.
2. Support for `continue` and `break` statements in loops.
3. Support for the `write` libc function.
4. Support for the `mode` parameter of the `open` libc function.
5. Support for `\0` character escape.
6. Support for local variable initializers.
7. Support for global variable initializers (integer literals only).

These represent a modest size increase to the original c4 of only 67 lines:

```shell
$ wc c4.c c4-pnut/c4.c
  528  3817 20498 c4.c
  595  4424 24234 c4-pnut/c4.c
```

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

The following command line options are supported:

- `-D <macro>`: Define `<macro>` as a macro with no value.
- `-I <path>`: Add `<path>` to the include search path.
- `--no-escape-chars` to disable escape character processing in string and
  character literals. This option is used to work around the lack of support for
  escape characters in c4, except for `\n`, `\0`, `\\`, `\"` and `\'`, and emits
  raw bytes for all other escape sequences since c4 supports raw bytes in string
  and character literals.

## Bootstrapping pnut-exe from c4

The rough steps to bootstrap pnut-exe from c4 are as follows:

```shell
# Compile c4
$ gcc -o c4 c4.c
# Preprocess pnut-exe.c with cpp.c, with the right options for c4 compatibility.
$ ./c4 cpp.c pnut.c $PNUT_OPTIONS $C4_COMPAT > pnut-exe.c
# Execute pnut-exe.c with c4 to obtain the pnut-exe executable.
$ ./c4 pnut-exe.c $PNUT_OPTIONS -o pnut-exe
```

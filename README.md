# Collection of bootstrapping tools based on c4

## [Original c4 - C in four functions](https://github.com/rswier/c4/tree/master)

> An exercise in minimalism.

Try the following:

```shell
gcc -o c4 c4.c
./c4 hello.c
./c4 -s hello.c

./c4 c4.c hello.c
./c4 c4.c c4.c hello.c
```

## [c4 as a bytecode virtual machine](vm/README.md)

`vm/c4.c` is an extension to `c4.c` to make it output its internal bytecode.
This bytecode can then be saved to disk and executed by a virtual machine
implemented in `vm/c4.sh`, or by `vm/c4.c` itself with the `-r` option. The
bytecode is relocatable, with the jump instructions using offsets from the
beginning of the bytecode, and the `REF` instruction using offsets from the
beginning of the global variables.

## [c4 assembly implementation](asm/README.md)

`asm/c4.s` is an implementation of the original `c4.c` in assembly, for use
in reproducible builds rooted in [`stage0`](https://github.com/oriansj/stage0).

## [c4 for pnut-exe](c4-pnut/README.md)

`c4-pnut/c4.c` is a modified `c4.c` with minimal extensions needed to host
[`pnut-exe`](https://github.com/udem-dlteam/pnut). A c4-compatible C
preprocessor is also included in `c4-pnut/cpp.c`, intended to make pnut's source
code compatible with it. Work is ongoing to port `pnut-exe` to c4.


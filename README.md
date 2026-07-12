# Collection of bootstrapping tools based on c4

## Original c4 - C in four functions

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

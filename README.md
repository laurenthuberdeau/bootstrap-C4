c4 - C in four functions
========================

An exercise in minimalism.

Try the following:

    gcc -o c4 c4.c
    ./c4 hello.c
    ./c4 -s hello.c

    ./c4 c4.c hello.c
    ./c4 c4.c c4.c hello.c

Modifications
=============

This is a fork of [rswier/c4](https://github.com/rswier/c4/tree/master) with the
following modifications:

1. Added an option `-b` to dump the bytecode in a textual format.
2. Added an option `-p` to make char, int and pointers the same size in the bytecode (1 word).
3. Made the bytecode format relocatable so that it can be loaded at any address.
4. Added an option `-r` to load precompiled bytecode and run it instead of compiling the source code.

The `c4.sh` POSIX shell script implements a virtual machine to run the C4
bytecode, just like `c4 -r` does. `c4.sh` represents all types (char, int,
pointer) as 1 word, so it can run the portable bytecode generated with `-p`.

Try the following:

    ./c4 -b -p fib.c > fib.op
    ./c4.sh fib.op

You'll notice that it's not very fast!

Still, the virtual machine is performant enough to bootstrap C4:

    ./c4 -b -p c4.c > c4.op                         # Generate portable C4 bytecode for c4.c
    ./c4.sh --no-exit c4.op -b -p c4.c > c4-2.op    # Compile c4.c using c4.op with c4.sh VM
    ./c4.sh --no-exit c4-2.op -b -p c4.c > c4-3.op  # Compile c4.c using c4-2.op with c4.sh VM
    diff c4-2.op c4-3.op                            # Should be empty

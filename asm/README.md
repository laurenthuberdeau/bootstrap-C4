# c4 in assembly

Reimplementation of [rswier/c4](https://github.com/rswier/c4/tree/master) in
x86, x86-64, ARM and RISC-V GAS assembly.

> [!NOTE]
> Note that this is still in an exploratory stage, with some parts of the
> implementation being mostly LLM-generated. That said, `c4.s` is functional and
> can be used to bootstrap `c4.c`, which is a good indication that the
> implementation is correct.
> Regardless of whether the implementation is LLM-generated or not, the spirit
> of reproducible builds is to "trust but verify" so don't take anyone's word
> for it, verify the implementation yourself!

`c4.s` is a freestanding implementation, written using virtual instructions
(macros) that are bound to architecture-specific instructions at assembly time.
The runtime functions (`printf`, `memset` and `memcpy`) are also implemented
using these virtual instructions (see `runtime.s`). This makes it possible to
port `c4.s` to any architecture by simply providing an implementation for the
virtual instructions. See `arch/` for the x86, x86-64, ARM and RISC-V
implementations of the virtual instructions.

The long term goal of this experiment is to port `c4.s` to M1 macro assembly,
and have it bootstrap from [`stage0`](https://github.com/oriansj/stage0). Then,
if all goes well, c4 may eventually be able to bootstrap
[`pnut-exe`](https://github.com/udem-dlteam/pnut) and then `TCC`, producing a
new bootstrapping path from `stage0` to `TCC`, one with fewer steps than the
current `stage0 -> cc_* -> M2-Planet -> Mes/MesCC -> TCC` path.

Since the principal use case for `c4.s` are reproducible builds, the assembly
implementation is designed to be as simple and easily auditable as possible.
Because the core `c4.s` implementation is architecture-agnostic, only a single
implementation of `c4.s` must be audited once, with a small
architecture-specific layer that is easy to review.

Additionally, the original `c4.c` source code is embedded in `c4.s`, with
_every_ line of `c4.c` appearing once (and in order) in `c4.s` directly beside
the corresponding assembly instructions. These lines are prefixed with `#:` to
indicate their origin. This also makes it possible to recover the original
`c4.c` source code from `c4.s`, making the whole thing self-contained. Try it
with `sed -n 's/^#://p' c4.s > c4.c` or `./c4 extract.c c4.s`.

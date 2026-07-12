#!/bin/sh
# Build the freestanding c4 from c4.s for every architecture available on
# this machine and verify each build's behavior.
#
# The x86-64 build is verified against a gcc build of c4.c; the other
# architectures are then verified against the x86-64 build (identical
# output, cycle counts and -s listings; the i386 listing additionally has
# the word-size immediates masked, since sizeof(int) is 4 there — the one
# documented semantic deviation).
#
# Per-architecture checks:
#   1. hello.c, c4.c hello.c, c4.c c4.c hello.c run identically to the
#      reference (cycle counts 9 / 26015 / 10060183 on every arch).
#   2. The -s listing of c4.c matches the reference modulo heap addresses.
#   3. extract.c run under the built c4 recovers c4.c from c4.s.
# Plus, once: the #: extraction test, a lint that the body contains no
# raw instructions (only v-macros, labels, directives, equates, comments),
# and a check that both x86-64 entry points (c4.s and arch/x86_64.s)
# produce the same binary.
set -e
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

echo "== extraction =="
./test-extract.sh

echo "== lint: c4.s body and runtime.s are architecture-neutral =="
if grep -vE "^\s*(#|$)|^\s*\.|:\s*(/\*.*\*/\s*)?$|^\s*v[A-Z]|^[A-Za-z_.$][A-Za-z0-9_.$]*\s*=|^[A-Za-z_][A-Za-z0-9_]*:\s+\.(space|ascii|asciz)" c4.s runtime.s; then
    fail "raw instruction lines found (listed above)"
fi
echo "OK: no raw instructions in c4.s or runtime.s"

MASK='s/-?\d{6,}/ADDR/g'

run_suite() { # $1 = name, $2 = c4 (with runner), $3 = reference (with
    # runner), $4 = extra perl mask for the -s listing (optional).
    # $2 and $3 are word-split on purpose: "qemu-aarch64 /path/c4" works.
    name=$1; bin=$2; ref=$3; extra=${4:-}
    echo "-- $name: hello.c"
    $ref hello.c > "$tmp/r.out"
    $bin hello.c > "$tmp/b.out"
    cmp "$tmp/r.out" "$tmp/b.out" || fail "$name hello.c differs"
    echo "-- $name: self-compilation chain"
    $ref c4.c c4.c hello.c > "$tmp/r.out"
    $bin c4.c c4.c hello.c > "$tmp/b.out"
    cmp "$tmp/r.out" "$tmp/b.out" || fail "$name self-compilation differs"
    cat "$tmp/b.out"
    echo "-- $name: -s listing (heap addresses masked)"
    $ref -s c4.c | perl -pe "$MASK$extra" > "$tmp/r.out"
    $bin -s c4.c | perl -pe "$MASK$extra" > "$tmp/b.out"
    cmp "$tmp/r.out" "$tmp/b.out" || fail "$name -s listing differs"
    echo "-- $name: extract.c under c4"
    $bin extract.c c4.s | sed '$d' | cmp - c4.c || fail "$name extract.c differs"
    echo "OK: $name"
}

echo "== x86-64 =="
gcc -nostdlib -static -no-pie -I. arch/x86_64.s -o "$tmp/c4-x86_64"
gcc -nostdlib -static -no-pie c4.s -o "$tmp/c4-direct"
# stripped copies: the symtabs differ by one FILE entry (the as temp name)
strip -o "$tmp/c4-x86_64.strip" "$tmp/c4-x86_64"
strip -o "$tmp/c4-direct.strip" "$tmp/c4-direct"
cmp "$tmp/c4-x86_64.strip" "$tmp/c4-direct.strip" || fail "c4.s and arch/x86_64.s builds differ"
echo "OK: both x86-64 entry points produce the same binary"
gcc -O1 -w c4.c -o "$tmp/ref-x86_64"
run_suite x86-64 "$tmp/c4-x86_64" "$tmp/ref-x86_64"

echo "== i386 =="
if gcc -m32 -nostdlib -static -no-pie -I. arch/i386.s -o "$tmp/c4-i386" 2>"$tmp/i386.err"; then
    run_suite i386 "$tmp/c4-i386" "$tmp/c4-x86_64" '; s/^(\s*IMM\s+)[48]$/${1}W/'
else
    cat "$tmp/i386.err" >&2
    echo "SKIP: no 32-bit x86 toolchain (gcc/binutils -m32 support missing)"
fi

# Cross toolchains go by different triplets per distribution (Debian:
# aarch64-linux-gnu-gcc, nix: aarch64-unknown-linux-gnu-gcc).
findcross() {
    for c in "$1-linux-gnu-gcc" "$1-unknown-linux-gnu-gcc"; do
        if command -v "$c" > /dev/null; then echo "$c"; return; fi
    done
}

for arch in aarch64 riscv64; do
    echo "== $arch =="
    cross=$(findcross "$arch")
    if [ -z "$cross" ]; then
        echo "SKIP: no $arch cross gcc installed"
    elif ! command -v "qemu-$arch" > /dev/null; then
        echo "SKIP: qemu-$arch not installed"
    else
        "$cross" -nostdlib -static -I. "arch/$arch.s" -o "$tmp/c4-$arch"
        run_suite "$arch" "qemu-$arch $tmp/c4-$arch" "$tmp/c4-x86_64"
    fi
done

echo "== all available architectures pass =="

#!/bin/sh
# Verify that the C source embedded in c4.s (the "#:" comment lines)
# matches c4.c byte for byte, first with sed, then with extract.c
# running under c4 itself (built from c4.s).
set -e
cd "$(dirname "$0")"

# 1) extraction with sed
sed -n 's/^#://p' c4.s > c4-extracted.c
if diff c4-extracted.c c4.c; then
    echo "OK: c4.c can be recovered from c4.s with sed"
    rm c4-extracted.c
else
    echo "FAIL: sed-extracted source differs from c4.c (see c4-extracted.c)" >&2
    exit 1
fi

# 2) the same extraction done by extract.c running under c4
#    (c4 appends an "exit(0) cycle = N" line, which sed '$d' strips)
if command -v gcc > /dev/null; then
    gcc -nostdlib -static -no-pie c4.s -o c4-test-bin
    ./c4-test-bin extract.c c4.s | sed '$d' > c4-extracted.c
    if diff c4-extracted.c c4.c; then
        echo "OK: c4.c can be recovered from c4.s by c4 running extract.c"
        rm c4-extracted.c c4-test-bin
    else
        echo "FAIL: c4-extracted source differs from c4.c (see c4-extracted.c)" >&2
        exit 1
    fi
else
    echo "SKIP: gcc not found, extract.c under c4 not tested"
fi

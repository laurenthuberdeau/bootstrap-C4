# arch/aarch64.s - AArch64 (ARM64) implementation of the c4.s virtual ISA
#
# Defines WORDSZ and every v-prefixed macro used by the architecture-neutral
# body of c4.s, then includes it.
#
# Virtual registers: A = x0 (accumulator), B = x1, C = x2 (scratch).
# x16 and x17 (the AAPCS intra-procedure-call scratch registers) are the
# macro-internal temporaries: address materialization (adrp + :lo12:) and
# immediate operands go through them, so no macro ever disturbs A, B or
# the staged arguments.  Locals are addressed as [x29 - n*WORDSZ], n =
# word index from the equates in the body (frames are at most 14 words,
# well inside the +-256 byte ldur/stur range).
#
# Argument staging: AAPCS64 passes arguments in x0-x7, but x0/x1 are A/B
# and must stay live while later arguments are computed, so the vARG*
# macros stage argument n in x8+n (x9-x14, aliased argr1-argr6 below)
# and vCALL/vCALLV copy the six staging registers into x0-x5 just before
# the bl.  Unused slots carry garbage, which the callee never reads.
# Variadic calls need nothing extra on this target (anonymous arguments
# travel in the same registers on Linux).
#
# Build (from the repo root; freestanding, no cross libc needed):
#     aarch64-unknown-linux-gnu-gcc -nostdlib -static -I. arch/aarch64.s -o c4-aarch64
# Run with qemu-user:  qemu-aarch64 ./c4-aarch64 hello.c

WORDSZ = 8

argr1 .req x9
argr2 .req x10
argr3 .req x11
argr4 .req x12
argr5 .req x13
argr6 .req x14

# ---- function structure ----
.macro vENTER k                  // prologue, \k local words
        stp x29, x30, [sp, -16]!
        mov x29, sp
        sub sp, sp, (\k*8 + 15) & -16
.endm
.macro vRET                      // epilogue; returns A
        mov sp, x29
        ldp x29, x30, [sp], 16
        ret
.endm
.macro vRETI k                   // return immediate \k
        mov x0, \k
        mov sp, x29
        ldp x29, x30, [sp], 16
        ret
.endm
.macro vSTARG n, m               // local \m = incoming argument \n
.if \n == 1
        stur x0, [x29, -\m*8]
.elseif \n == 2
        stur x1, [x29, -\m*8]
.elseif \n == 3
        stur x2, [x29, -\m*8]
.elseif \n == 4
        stur x3, [x29, -\m*8]
.elseif \n == 5
        stur x4, [x29, -\m*8]
.elseif \n == 6
        stur x5, [x29, -\m*8]
.endif
.endm
.macro vCALL fn                  // call, fixed argument list
        mov x0, x9
        mov x1, x10
        mov x2, x11
        mov x3, x12
        mov x4, x13
        mov x5, x14
        bl \fn
.endm
.macro vCALLV fn                 // call, variadic (same registers here)
        mov x0, x9
        mov x1, x10
        mov x2, x11
        mov x3, x12
        mov x4, x13
        mov x5, x14
        bl \fn
.endm
.macro vRES                      // A = call result
.endm                            // (result is already in x0)
.macro vRES32                    // A = sign-extended 32-bit call result
        sxtw x0, w0
.endm

# ---- loads and stores ----
.macro vLDAG g               // A = word[g]
        adrp x16, \g
        ldr x0, [x16, :lo12:\g]
.endm
.macro vLDBG g               // B = word[g]
        adrp x16, \g
        ldr x1, [x16, :lo12:\g]
.endm
.macro vSTAG g               // word[g] = A
        adrp x16, \g
        str x0, [x16, :lo12:\g]
.endm
.macro vSTBG g               // word[g] = B
        adrp x16, \g
        str x1, [x16, :lo12:\g]
.endm
.macro vLDAL m               // A = local m
        ldur x0, [x29, -\m*8]
.endm
.macro vLDBL m               // B = local m
        ldur x1, [x29, -\m*8]
.endm
.macro vSTAL m               // local m = A
        stur x0, [x29, -\m*8]
.endm
.macro vSTBL m               // local m = B
        stur x1, [x29, -\m*8]
.endm
.macro vSTCL m               // local m = C
        stur x2, [x29, -\m*8]
.endm
.macro vLDAI k               // A = k
        mov x0, \k
.endm
.macro vLDBI k               // B = k
        mov x1, \k
.endm
.macro vLDAS s               // A = &s
        adrp x0, \s
        add x0, x0, :lo12:\s
.endm
.macro vSTIG g, k            // word[g] = k
        adrp x16, \g
        mov x17, \k
        str x17, [x16, :lo12:\g]
.endm
.macro vSTIL m, k            // local m = k
        mov x17, \k
        stur x17, [x29, -\m*8]
.endm
.macro vSTSG g, s            // word[g] = &s
        adrp x17, \s
        add x17, x17, :lo12:\s
        adrp x16, \g
        str x17, [x16, :lo12:\g]
.endm
.macro vDEREFA               // A = word[A]
        ldr x0, [x0]
.endm
.macro vDEREFAB              // B = word[A]
        ldr x1, [x0]
.endm
.macro vDEREFBA              // A = word[B]
        ldr x0, [x1]
.endm
.macro vDEREFAC              // C = word[A]
        ldr x2, [x0]
.endm
.macro vSTWA_B               // word[A] = B
        str x1, [x0]
.endm
.macro vSTWB_A               // word[B] = A
        str x0, [x1]
.endm
.macro vSTWA_I k             // word[A] = k
        mov x17, \k
        str x17, [x0]
.endm
.macro vLDSBA                // A = signed byte[A]
        ldrsb x0, [x0]
.endm
.macro vLDSBB                // B = signed byte[B]
        ldrsb x1, [x1]
.endm
.macro vLDSBAB k             // B = signed byte[A + k]
        ldrsb x1, [x0, \k]
.endm
.macro vSTBA_B               // byte[A] = low byte of B
        strb w1, [x0]
.endm
.macro vSTBB_A               // byte[B] = low byte of A
        strb w0, [x1]
.endm
.macro vSTBAB_Z              // byte[A + B] = 0
        strb wzr, [x0, x1]
.endm
.macro vSEXTBYTEA            // A = sign-extended low byte of A
        sxtb x0, w0
.endm
.macro vLDAF f               // A = word[A + f words]
        ldr x0, [x0, (\f)*8]
.endm
.macro vLDBF f               // B = word[A + f words]
        ldr x1, [x0, (\f)*8]
.endm
.macro vLDA_BF f             // A = word[B + f words]
        ldr x0, [x1, (\f)*8]
.endm
.macro vLDB_BF f             // B = word[B + f words]
        ldr x1, [x1, (\f)*8]
.endm
.macro vSTF_B f              // word[A + f words] = B
        str x1, [x0, (\f)*8]
.endm
.macro vSTF_I f, k           // word[A + f words] = k
        mov x17, \k
        str x17, [x0, (\f)*8]
.endm

# ---- ALU ----
.macro vADDAB                // A += B
        add x0, x0, x1
.endm
.macro vADDBA                // B += A
        add x1, x1, x0
.endm
.macro vADDAI k              // A += k
        mov x17, \k
        add x0, x0, x17
.endm
.macro vADDAW k              // A += k words
        mov x17, (\k)*8
        add x0, x0, x17
.endm
.macro vADDBI k              // B += k
        mov x17, \k
        add x1, x1, x17
.endm
.macro vADDAL m              // A += local m
        ldur x16, [x29, -\m*8]
        add x0, x0, x16
.endm
.macro vADDAS s              // A += &s
        adrp x16, \s
        add x16, x16, :lo12:\s
        add x0, x0, x16
.endm
.macro vSUBAI k              // A -= k
        mov x17, \k
        sub x0, x0, x17
.endm
.macro vSUBBI k              // B -= k
        mov x17, \k
        sub x1, x1, x17
.endm
.macro vSUBAG g              // A -= word[g]
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        sub x0, x0, x16
.endm
.macro vSUBA_BF f            // A -= word[B + f words]
        ldr x16, [x1, (\f)*8]
        sub x0, x0, x16
.endm
.macro vMULAI k              // A *= k
        mov x17, \k
        mul x0, x0, x17
.endm
.macro vMULBI k              // B *= k
        mov x17, \k
        mul x1, x1, x17
.endm
.macro vMULAW                // A *= WORDSZ (int* scaling)
        lsl x0, x0, 3
.endm
.macro vSHLAI k              // A <<= k
        lsl x0, x0, \k
.endm
.macro vANDBI k              // B &= k
        and x1, x1, \k
.endm
.macro vALIGNA               // A &= -WORDSZ (align down)
        and x0, x0, -8
.endm
.macro vNEGB                 // B = -B
        neg x1, x1
.endm
.macro vORBL m               // B |= local m
        ldur x16, [x29, -\m*8]
        orr x1, x1, x16
.endm
.macro vXORBL m              // B ^= local m
        ldur x16, [x29, -\m*8]
        eor x1, x1, x16
.endm
.macro vANDBL m              // B &= local m
        ldur x16, [x29, -\m*8]
        and x1, x1, x16
.endm
.macro vADDBL m              // B += local m
        ldur x16, [x29, -\m*8]
        add x1, x1, x16
.endm
.macro vSUBBL m              // B -= local m
        ldur x16, [x29, -\m*8]
        sub x1, x1, x16
.endm
.macro vMULBL m              // B *= local m
        ldur x16, [x29, -\m*8]
        mul x1, x1, x16
.endm
.macro vSHLCB                // C <<= B
        lsl x2, x2, x1
.endm
.macro vSARCB                // C >>= B (arithmetic)
        asr x2, x2, x1
.endm

# ---- read-modify-write on memory ----
.macro vINCGI g, k           // word[g] += k
        adrp x16, \g
        ldr x17, [x16, :lo12:\g]
        add x17, x17, \k
        str x17, [x16, :lo12:\g]
.endm
.macro vDECGI g, k           // word[g] -= k
        adrp x16, \g
        ldr x17, [x16, :lo12:\g]
        sub x17, x17, \k
        str x17, [x16, :lo12:\g]
.endm
.macro vINCGW g, k           // word[g] += k words
        adrp x16, \g
        ldr x17, [x16, :lo12:\g]
        add x17, x17, (\k)*8
        str x17, [x16, :lo12:\g]
.endm
.macro vDECGW g, k           // word[g] -= k words
        adrp x16, \g
        ldr x17, [x16, :lo12:\g]
        sub x17, x17, (\k)*8
        str x17, [x16, :lo12:\g]
.endm
.macro vINCLI m, k           // local m += k
        ldur x16, [x29, -\m*8]
        add x16, x16, \k
        stur x16, [x29, -\m*8]
.endm
.macro vDECLI m, k           // local m -= k
        ldur x16, [x29, -\m*8]
        sub x16, x16, \k
        stur x16, [x29, -\m*8]
.endm
.macro vINCLW m, k           // local m += k words
        ldur x16, [x29, -\m*8]
        add x16, x16, (\k)*8
        stur x16, [x29, -\m*8]
.endm
.macro vDECLW m, k           // local m -= k words
        ldur x16, [x29, -\m*8]
        sub x16, x16, (\k)*8
        stur x16, [x29, -\m*8]
.endm
.macro vADDLA m              // local m += A
        ldur x16, [x29, -\m*8]
        add x16, x16, x0
        stur x16, [x29, -\m*8]
.endm
.macro vSUBLA m              // local m -= A
        ldur x16, [x29, -\m*8]
        sub x16, x16, x0
        stur x16, [x29, -\m*8]
.endm

# ---- division (dividend in A) ----
.macro vDIVL m                   // A = A / local m
        ldur x16, [x29, -\m*8]
        sdiv x0, x0, x16
.endm
.macro vMODL m                   // C = A % local m
        ldur x16, [x29, -\m*8]
        sdiv x17, x0, x16
        msub x2, x17, x16, x0
.endm

# ---- comparisons producing 0/1 in B ----
.macro vSETEQ m                  // B = (B == local m)
        ldur x16, [x29, -\m*8]
        cmp x1, x16
        cset x1, eq
.endm
.macro vSETNE m                  // B = (B != local m)
        ldur x16, [x29, -\m*8]
        cmp x1, x16
        cset x1, ne
.endm
.macro vSETLT m                  // B = (B < local m)
        ldur x16, [x29, -\m*8]
        cmp x1, x16
        cset x1, lt
.endm
.macro vSETGT m                  // B = (B > local m)
        ldur x16, [x29, -\m*8]
        cmp x1, x16
        cset x1, gt
.endm
.macro vSETLE m                  // B = (B <= local m)
        ldur x16, [x29, -\m*8]
        cmp x1, x16
        cset x1, le
.endm
.macro vSETGE m                  // B = (B >= local m)
        ldur x16, [x29, -\m*8]
        cmp x1, x16
        cset x1, ge
.endm

# ---- branches ----
.macro vJMP l
        b \l
.endm
.macro vJZA l                    // branch if A == 0
        cbz x0, \l
.endm
.macro vJNZA l                   // branch if A != 0
        cbnz x0, \l
.endm
.macro vJNZRES l                 // branch if 32-bit call result != 0
        cbnz w0, \l
.endm
.macro vJNE_A_BF f, l            // branch if A != word[B + f words]
        ldr x16, [x1, (\f)*8]
        cmp x0, x16
        b.ne \l
.endm
# fused compare-and-branch: vJcc_XY, cc = EQ NE LT GT LE GE (signed),
# X vs Y: GI word[g] vs imm, LI local vs imm, AI A vs imm, BI B vs imm,
# AG A vs word[g], AL A vs local, FI word[A + f words] vs imm.
.macro vJEQ_GI g, k, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        mov x17, \k
        cmp x16, x17
        b.eq \l
.endm
.macro vJEQ_LI m, k, l
        ldur x16, [x29, -\m*8]
        mov x17, \k
        cmp x16, x17
        b.eq \l
.endm
.macro vJEQ_AI k, l
        mov x17, \k
        cmp x0, x17
        b.eq \l
.endm
.macro vJEQ_BI k, l
        mov x17, \k
        cmp x1, x17
        b.eq \l
.endm
.macro vJEQ_AG g, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        cmp x0, x16
        b.eq \l
.endm
.macro vJEQ_AL m, l
        ldur x16, [x29, -\m*8]
        cmp x0, x16
        b.eq \l
.endm
.macro vJEQ_FI f, k, l
        ldr x16, [x0, (\f)*8]
        mov x17, \k
        cmp x16, x17
        b.eq \l
.endm
.macro vJNE_GI g, k, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        mov x17, \k
        cmp x16, x17
        b.ne \l
.endm
.macro vJNE_LI m, k, l
        ldur x16, [x29, -\m*8]
        mov x17, \k
        cmp x16, x17
        b.ne \l
.endm
.macro vJNE_AI k, l
        mov x17, \k
        cmp x0, x17
        b.ne \l
.endm
.macro vJNE_BI k, l
        mov x17, \k
        cmp x1, x17
        b.ne \l
.endm
.macro vJNE_AG g, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        cmp x0, x16
        b.ne \l
.endm
.macro vJNE_AL m, l
        ldur x16, [x29, -\m*8]
        cmp x0, x16
        b.ne \l
.endm
.macro vJNE_FI f, k, l
        ldr x16, [x0, (\f)*8]
        mov x17, \k
        cmp x16, x17
        b.ne \l
.endm
.macro vJLT_GI g, k, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        mov x17, \k
        cmp x16, x17
        b.lt \l
.endm
.macro vJLT_LI m, k, l
        ldur x16, [x29, -\m*8]
        mov x17, \k
        cmp x16, x17
        b.lt \l
.endm
.macro vJLT_AI k, l
        mov x17, \k
        cmp x0, x17
        b.lt \l
.endm
.macro vJLT_BI k, l
        mov x17, \k
        cmp x1, x17
        b.lt \l
.endm
.macro vJLT_AG g, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        cmp x0, x16
        b.lt \l
.endm
.macro vJLT_AL m, l
        ldur x16, [x29, -\m*8]
        cmp x0, x16
        b.lt \l
.endm
.macro vJLT_FI f, k, l
        ldr x16, [x0, (\f)*8]
        mov x17, \k
        cmp x16, x17
        b.lt \l
.endm
.macro vJGT_GI g, k, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        mov x17, \k
        cmp x16, x17
        b.gt \l
.endm
.macro vJGT_LI m, k, l
        ldur x16, [x29, -\m*8]
        mov x17, \k
        cmp x16, x17
        b.gt \l
.endm
.macro vJGT_AI k, l
        mov x17, \k
        cmp x0, x17
        b.gt \l
.endm
.macro vJGT_BI k, l
        mov x17, \k
        cmp x1, x17
        b.gt \l
.endm
.macro vJGT_AG g, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        cmp x0, x16
        b.gt \l
.endm
.macro vJGT_AL m, l
        ldur x16, [x29, -\m*8]
        cmp x0, x16
        b.gt \l
.endm
.macro vJGT_FI f, k, l
        ldr x16, [x0, (\f)*8]
        mov x17, \k
        cmp x16, x17
        b.gt \l
.endm
.macro vJLE_GI g, k, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        mov x17, \k
        cmp x16, x17
        b.le \l
.endm
.macro vJLE_LI m, k, l
        ldur x16, [x29, -\m*8]
        mov x17, \k
        cmp x16, x17
        b.le \l
.endm
.macro vJLE_AI k, l
        mov x17, \k
        cmp x0, x17
        b.le \l
.endm
.macro vJLE_BI k, l
        mov x17, \k
        cmp x1, x17
        b.le \l
.endm
.macro vJLE_AG g, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        cmp x0, x16
        b.le \l
.endm
.macro vJLE_AL m, l
        ldur x16, [x29, -\m*8]
        cmp x0, x16
        b.le \l
.endm
.macro vJLE_FI f, k, l
        ldr x16, [x0, (\f)*8]
        mov x17, \k
        cmp x16, x17
        b.le \l
.endm
.macro vJGE_GI g, k, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        mov x17, \k
        cmp x16, x17
        b.ge \l
.endm
.macro vJGE_LI m, k, l
        ldur x16, [x29, -\m*8]
        mov x17, \k
        cmp x16, x17
        b.ge \l
.endm
.macro vJGE_AI k, l
        mov x17, \k
        cmp x0, x17
        b.ge \l
.endm
.macro vJGE_BI k, l
        mov x17, \k
        cmp x1, x17
        b.ge \l
.endm
.macro vJGE_AG g, l
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        cmp x0, x16
        b.ge \l
.endm
.macro vJGE_AL m, l
        ldur x16, [x29, -\m*8]
        cmp x0, x16
        b.ge \l
.endm
.macro vJGE_FI f, k, l
        ldr x16, [x0, (\f)*8]
        mov x17, \k
        cmp x16, x17
        b.ge \l
.endm

# ---- argument staging (slot n = 1..6 in argr1-argr6 = x9-x14) ----
.macro vARGA n
        mov argr\n, x0
.endm
.macro vARGI n, k
        mov argr\n, \k
.endm
.macro vARGZ n
        mov argr\n, 0
.endm
.macro vARGS n, s
        adrp x16, \s
        add x16, x16, :lo12:\s
        mov argr\n, x16
.endm
.macro vARGG n, g
        adrp x16, \g
        ldr argr\n, [x16, :lo12:\g]
.endm
.macro vARGL n, m
        ldur argr\n, [x29, -\m*8]
.endm
.macro vARGMA n, k
        ldr argr\n, [x0, (\k)*8]
.endm
.macro vARG_BF n, f
        ldr argr\n, [x1, (\f)*8]
.endm
.macro vARGSUBG n, g
        adrp x16, \g
        ldr x16, [x16, :lo12:\g]
        sub argr\n, argr\n, x16
.endm
.macro vARGSUBL n, m
        ldur x16, [x29, -\m*8]
        sub argr\n, argr\n, x16
.endm
.macro vARGSUBI n, k
        mov x17, \k
        sub argr\n, argr\n, x17
.endm
.macro vARGMULI n, k
        mov x17, \k
        mul argr\n, argr\n, x17
.endm
.macro vARGADDS n, s
        adrp x16, \s
        add x16, x16, :lo12:\s
        add argr\n, argr\n, x16
.endm

# ----------------------------------------------------------------------
# Freestanding runtime, AArch64 syscall glue.
#
# Together with the architecture-neutral runtime.s (printf, memset,
# memcmp, free -- included below) this replaces libc and the C runtime:
# _start replaces crt0, and the OS-facing functions (open, read, close,
# write, malloc, exit) are implemented with direct Linux AArch64
# syscalls (svc 0: number in x8, arguments in x0-x5).  The call sites
# in the body and in runtime.s are unchanged: these functions keep the
# same names and the AAPCS64 calling convention.  AArch64 Linux has no
# plain open; the wrapper uses openat(AT_FDCWD, path, flags, 0).
# ----------------------------------------------------------------------

.text

# ---- process entry and exit -----------------------------------------

.globl _start
_start:                              // exit(main(argc, argv))
        ldr x0, [sp]                 // argc
        add x1, sp, 8                // argv
        bl main
                                     // status in x0; fall through
.globl exit
exit:                                // exit(status)
        mov x8, 93                   // SYS_exit
        svc 0

# ---- file I/O --------------------------------------------------------

.globl open
open:                                // open(path, flags) -> fd or < 0
        mov x2, x1                   // flags
        mov x1, x0                   // path
        mov x0, -100                 // AT_FDCWD
        mov x3, 0                    // mode (unused: c4 never creates)
        mov x8, 56                   // SYS_openat
        svc 0
        ret

.globl read
read:                                // read(fd, buf, count) -> n or < 0
        mov x8, 63                   // SYS_read
        svc 0
        ret

.globl write
write:                               // write(fd, buf, count) -> n or < 0
        mov x8, 64                   // SYS_write
        svc 0
        ret

.globl close
close:                               // close(fd) -> 0 or < 0
        mov x8, 57                   // SYS_close
        svc 0
        ret

# ---- memory ----------------------------------------------------------

.globl malloc
malloc:                              // malloc(size) -> ptr or 0
        mov x1, x0                   // length
        mov x0, 0                    // addr = 0 (kernel chooses)
        mov x2, 3                    // PROT_READ|PROT_WRITE
        mov x3, 0x22                 // MAP_PRIVATE|MAP_ANONYMOUS
        mov x4, -1                   // fd = -1
        mov x5, 0                    // offset = 0
        mov x8, 222                  // SYS_mmap
        svc 0
        cmp x0, 0                    // errors are small negative values
        b.ge .Lrt_malloc_ok
        mov x0, 0                    // failure -> 0, like malloc
.Lrt_malloc_ok:
        ret

.include "runtime.s"

.include "c4.s"

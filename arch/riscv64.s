# arch/riscv64.s - RISC-V (RV64) implementation of the c4.s virtual ISA
#
# Defines WORDSZ and every v-prefixed macro used by the architecture-neutral
# body of c4.s, then includes it.
#
# Virtual registers: A = a0 (accumulator), B = a1, C = a2 (scratch).
# t0 and t1 are the macro-internal temporaries: address materialization
# (la / the ld-from-symbol pseudo) and immediate operands go through
# them, so no macro ever disturbs A, B or the staged arguments.  Locals
# are addressed as -n*WORDSZ(s0), n = word index from the equates in
# the body.
#
# Argument staging: the RISC-V ABI passes arguments in a0-a7, but a0/a1
# are A/B and must stay live while later arguments are computed, so the
# vARG* macros stage argument n = 1..6 in t2, t3, t4, t5, t6, a6 and
# vCALL/vCALLV copy the six staging registers into a0-a5 just before
# the call.  Unused slots carry garbage, which the callee never reads.
# (GAS for RISC-V has no .req register aliases, hence the .if chains.)
# Variadic calls need nothing extra on this target.
#
# RISC-V has no condition flags: the fused compare-and-branch macros
# map directly onto beq/bne/blt/bge (bgt/ble are standard pseudos) and
# the vSETcc macros onto slt/seqz/snez/xori sequences.
#
# Build (from the repo root; freestanding, no cross libc needed):
#     riscv64-unknown-linux-gnu-gcc -nostdlib -static -I. arch/riscv64.s -o c4-riscv64
# Run with qemu-user:  qemu-riscv64 ./c4-riscv64 hello.c

WORDSZ = 8

# ---- function structure ----
.macro vENTER k                  # prologue, \k local words
        addi sp, sp, -16
        sd ra, 8(sp)
        sd s0, 0(sp)
        mv s0, sp
        addi sp, sp, -((\k*8 + 15) & -16)
.endm
.macro vRET                      # epilogue; returns A
        mv sp, s0
        ld ra, 8(sp)
        ld s0, 0(sp)
        addi sp, sp, 16
        ret
.endm
.macro vRETI k                   # return immediate \k
        li a0, \k
        mv sp, s0
        ld ra, 8(sp)
        ld s0, 0(sp)
        addi sp, sp, 16
        ret
.endm
.macro vSTARG n, m               # local \m = incoming argument \n
.if \n == 1
        sd a0, -\m*8(s0)
.elseif \n == 2
        sd a1, -\m*8(s0)
.elseif \n == 3
        sd a2, -\m*8(s0)
.elseif \n == 4
        sd a3, -\m*8(s0)
.elseif \n == 5
        sd a4, -\m*8(s0)
.elseif \n == 6
        sd a5, -\m*8(s0)
.endif
.endm
.macro vCALL fn                  # call, fixed argument list
        mv a0, t2
        mv a1, t3
        mv a2, t4
        mv a3, t5
        mv a4, t6
        mv a5, a6
        call \fn
.endm
.macro vCALLV fn                 # call, variadic (same registers here)
        mv a0, t2
        mv a1, t3
        mv a2, t4
        mv a3, t5
        mv a4, t6
        mv a5, a6
        call \fn
.endm
.macro vRES                      # A = call result
.endm                            # (result is already in a0)
.macro vRES32                    # A = sign-extended 32-bit call result
        sext.w a0, a0
.endm

# ---- loads and stores ----
.macro vLDAG g               # A = word[g]
        ld a0, \g
.endm
.macro vLDBG g               # B = word[g]
        ld a1, \g
.endm
.macro vSTAG g               # word[g] = A
        sd a0, \g, t0
.endm
.macro vSTBG g               # word[g] = B
        sd a1, \g, t0
.endm
.macro vLDAL m               # A = local m
        ld a0, -\m*8(s0)
.endm
.macro vLDBL m               # B = local m
        ld a1, -\m*8(s0)
.endm
.macro vSTAL m               # local m = A
        sd a0, -\m*8(s0)
.endm
.macro vSTBL m               # local m = B
        sd a1, -\m*8(s0)
.endm
.macro vSTCL m               # local m = C
        sd a2, -\m*8(s0)
.endm
.macro vLDAI k               # A = k
        li a0, \k
.endm
.macro vLDBI k               # B = k
        li a1, \k
.endm
.macro vLDAS s               # A = &s
        la a0, \s
.endm
.macro vSTIG g, k            # word[g] = k
        li t1, \k
        sd t1, \g, t0
.endm
.macro vSTIL m, k            # local m = k
        li t1, \k
        sd t1, -\m*8(s0)
.endm
.macro vSTSG g, s            # word[g] = &s
        la t1, \s
        sd t1, \g, t0
.endm
.macro vDEREFA               # A = word[A]
        ld a0, 0(a0)
.endm
.macro vDEREFAB              # B = word[A]
        ld a1, 0(a0)
.endm
.macro vDEREFBA              # A = word[B]
        ld a0, 0(a1)
.endm
.macro vDEREFAC              # C = word[A]
        ld a2, 0(a0)
.endm
.macro vSTWA_B               # word[A] = B
        sd a1, 0(a0)
.endm
.macro vSTWB_A               # word[B] = A
        sd a0, 0(a1)
.endm
.macro vSTWA_I k             # word[A] = k
        li t1, \k
        sd t1, 0(a0)
.endm
.macro vLDSBA                # A = signed byte[A]
        lb a0, 0(a0)
.endm
.macro vLDSBB                # B = signed byte[B]
        lb a1, 0(a1)
.endm
.macro vLDSBAB k             # B = signed byte[A + k]
        lb a1, \k(a0)
.endm
.macro vSTBA_B               # byte[A] = low byte of B
        sb a1, 0(a0)
.endm
.macro vSTBB_A               # byte[B] = low byte of A
        sb a0, 0(a1)
.endm
.macro vSTBAB_Z              # byte[A + B] = 0
        add t0, a0, a1
        sb zero, 0(t0)
.endm
.macro vSEXTBYTEA            # A = sign-extended low byte of A
        slli a0, a0, 56
        srai a0, a0, 56
.endm
.macro vLDAF f               # A = word[A + f words]
        ld a0, (\f)*8(a0)
.endm
.macro vLDBF f               # B = word[A + f words]
        ld a1, (\f)*8(a0)
.endm
.macro vLDA_BF f             # A = word[B + f words]
        ld a0, (\f)*8(a1)
.endm
.macro vLDB_BF f             # B = word[B + f words]
        ld a1, (\f)*8(a1)
.endm
.macro vSTF_B f              # word[A + f words] = B
        sd a1, (\f)*8(a0)
.endm
.macro vSTF_I f, k           # word[A + f words] = k
        li t1, \k
        sd t1, (\f)*8(a0)
.endm

# ---- ALU ----
.macro vADDAB                # A += B
        add a0, a0, a1
.endm
.macro vADDBA                # B += A
        add a1, a1, a0
.endm
.macro vADDAI k              # A += k
        li t1, \k
        add a0, a0, t1
.endm
.macro vADDAW k              # A += k words
        li t1, (\k)*8
        add a0, a0, t1
.endm
.macro vADDBI k              # B += k
        li t1, \k
        add a1, a1, t1
.endm
.macro vADDAL m              # A += local m
        ld t0, -\m*8(s0)
        add a0, a0, t0
.endm
.macro vADDAS s              # A += &s
        la t0, \s
        add a0, a0, t0
.endm
.macro vSUBAI k              # A -= k
        li t1, \k
        sub a0, a0, t1
.endm
.macro vSUBBI k              # B -= k
        li t1, \k
        sub a1, a1, t1
.endm
.macro vSUBAG g              # A -= word[g]
        ld t0, \g
        sub a0, a0, t0
.endm
.macro vSUBA_BF f            # A -= word[B + f words]
        ld t0, (\f)*8(a1)
        sub a0, a0, t0
.endm
.macro vMULAI k              # A *= k
        li t1, \k
        mul a0, a0, t1
.endm
.macro vMULBI k              # B *= k
        li t1, \k
        mul a1, a1, t1
.endm
.macro vMULAW                # A *= WORDSZ (int* scaling)
        slli a0, a0, 3
.endm
.macro vSHLAI k              # A <<= k
        slli a0, a0, \k
.endm
.macro vANDBI k              # B &= k
        andi a1, a1, \k
.endm
.macro vALIGNA               # A &= -WORDSZ (align down)
        andi a0, a0, -8
.endm
.macro vNEGB                 # B = -B
        neg a1, a1
.endm
.macro vORBL m               # B |= local m
        ld t0, -\m*8(s0)
        or a1, a1, t0
.endm
.macro vXORBL m              # B ^= local m
        ld t0, -\m*8(s0)
        xor a1, a1, t0
.endm
.macro vANDBL m              # B &= local m
        ld t0, -\m*8(s0)
        and a1, a1, t0
.endm
.macro vADDBL m              # B += local m
        ld t0, -\m*8(s0)
        add a1, a1, t0
.endm
.macro vSUBBL m              # B -= local m
        ld t0, -\m*8(s0)
        sub a1, a1, t0
.endm
.macro vMULBL m              # B *= local m
        ld t0, -\m*8(s0)
        mul a1, a1, t0
.endm
.macro vSHLCB                # C <<= B
        sll a2, a2, a1
.endm
.macro vSARCB                # C >>= B (arithmetic)
        sra a2, a2, a1
.endm

# ---- read-modify-write on memory ----
.macro vINCGI g, k           # word[g] += k
        la t0, \g
        ld t1, 0(t0)
        addi t1, t1, \k
        sd t1, 0(t0)
.endm
.macro vDECGI g, k           # word[g] -= k
        la t0, \g
        ld t1, 0(t0)
        addi t1, t1, -(\k)
        sd t1, 0(t0)
.endm
.macro vINCGW g, k           # word[g] += k words
        la t0, \g
        ld t1, 0(t0)
        addi t1, t1, (\k)*8
        sd t1, 0(t0)
.endm
.macro vDECGW g, k           # word[g] -= k words
        la t0, \g
        ld t1, 0(t0)
        addi t1, t1, -(\k)*8
        sd t1, 0(t0)
.endm
.macro vINCLI m, k           # local m += k
        ld t0, -\m*8(s0)
        addi t0, t0, \k
        sd t0, -\m*8(s0)
.endm
.macro vDECLI m, k           # local m -= k
        ld t0, -\m*8(s0)
        addi t0, t0, -(\k)
        sd t0, -\m*8(s0)
.endm
.macro vINCLW m, k           # local m += k words
        ld t0, -\m*8(s0)
        addi t0, t0, (\k)*8
        sd t0, -\m*8(s0)
.endm
.macro vDECLW m, k           # local m -= k words
        ld t0, -\m*8(s0)
        addi t0, t0, -(\k)*8
        sd t0, -\m*8(s0)
.endm
.macro vADDLA m              # local m += A
        ld t0, -\m*8(s0)
        add t0, t0, a0
        sd t0, -\m*8(s0)
.endm
.macro vSUBLA m              # local m -= A
        ld t0, -\m*8(s0)
        sub t0, t0, a0
        sd t0, -\m*8(s0)
.endm

# ---- division (dividend in A) ----
.macro vDIVL m                   # A = A / local m
        ld t0, -\m*8(s0)
        div a0, a0, t0
.endm
.macro vMODL m                   # C = A % local m
        ld t0, -\m*8(s0)
        rem a2, a0, t0
.endm

# ---- comparisons producing 0/1 in B ----
.macro vSETEQ m                  # B = (B == local m)
        ld t0, -\m*8(s0)
        sub t1, a1, t0
        seqz a1, t1
.endm
.macro vSETNE m                  # B = (B != local m)
        ld t0, -\m*8(s0)
        sub t1, a1, t0
        snez a1, t1
.endm
.macro vSETLT m                  # B = (B < local m)
        ld t0, -\m*8(s0)
        slt a1, a1, t0
.endm
.macro vSETGT m                  # B = (B > local m)
        ld t0, -\m*8(s0)
        slt a1, t0, a1
.endm
.macro vSETLE m                  # B = (B <= local m) = !(local m < B)
        ld t0, -\m*8(s0)
        slt t1, t0, a1
        xori a1, t1, 1
.endm
.macro vSETGE m                  # B = (B >= local m) = !(B < local m)
        ld t0, -\m*8(s0)
        slt t1, a1, t0
        xori a1, t1, 1
.endm

# ---- branches ----
.macro vJMP l
        j \l
.endm
.macro vJZA l                    # branch if A == 0
        beqz a0, \l
.endm
.macro vJNZA l                   # branch if A != 0
        bnez a0, \l
.endm
.macro vJNZRES l                 # branch if 32-bit call result != 0
        sext.w t0, a0
        bnez t0, \l
.endm
.macro vJNE_A_BF f, l            # branch if A != word[B + f words]
        ld t0, (\f)*8(a1)
        bne a0, t0, \l
.endm
# fused compare-and-branch: vJcc_XY, cc = EQ NE LT GT LE GE (signed),
# X vs Y: GI word[g] vs imm, LI local vs imm, AI A vs imm, BI B vs imm,
# AG A vs word[g], AL A vs local, FI word[A + f words] vs imm.
.macro vJEQ_GI g, k, l
        ld t0, \g
        li t1, \k
        beq t0, t1, \l
.endm
.macro vJEQ_LI m, k, l
        ld t0, -\m*8(s0)
        li t1, \k
        beq t0, t1, \l
.endm
.macro vJEQ_AI k, l
        li t1, \k
        beq a0, t1, \l
.endm
.macro vJEQ_BI k, l
        li t1, \k
        beq a1, t1, \l
.endm
.macro vJEQ_AG g, l
        ld t0, \g
        beq a0, t0, \l
.endm
.macro vJEQ_AL m, l
        ld t0, -\m*8(s0)
        beq a0, t0, \l
.endm
.macro vJEQ_FI f, k, l
        ld t0, (\f)*8(a0)
        li t1, \k
        beq t0, t1, \l
.endm
.macro vJNE_GI g, k, l
        ld t0, \g
        li t1, \k
        bne t0, t1, \l
.endm
.macro vJNE_LI m, k, l
        ld t0, -\m*8(s0)
        li t1, \k
        bne t0, t1, \l
.endm
.macro vJNE_AI k, l
        li t1, \k
        bne a0, t1, \l
.endm
.macro vJNE_BI k, l
        li t1, \k
        bne a1, t1, \l
.endm
.macro vJNE_AG g, l
        ld t0, \g
        bne a0, t0, \l
.endm
.macro vJNE_AL m, l
        ld t0, -\m*8(s0)
        bne a0, t0, \l
.endm
.macro vJNE_FI f, k, l
        ld t0, (\f)*8(a0)
        li t1, \k
        bne t0, t1, \l
.endm
.macro vJLT_GI g, k, l
        ld t0, \g
        li t1, \k
        blt t0, t1, \l
.endm
.macro vJLT_LI m, k, l
        ld t0, -\m*8(s0)
        li t1, \k
        blt t0, t1, \l
.endm
.macro vJLT_AI k, l
        li t1, \k
        blt a0, t1, \l
.endm
.macro vJLT_BI k, l
        li t1, \k
        blt a1, t1, \l
.endm
.macro vJLT_AG g, l
        ld t0, \g
        blt a0, t0, \l
.endm
.macro vJLT_AL m, l
        ld t0, -\m*8(s0)
        blt a0, t0, \l
.endm
.macro vJLT_FI f, k, l
        ld t0, (\f)*8(a0)
        li t1, \k
        blt t0, t1, \l
.endm
.macro vJGT_GI g, k, l
        ld t0, \g
        li t1, \k
        bgt t0, t1, \l
.endm
.macro vJGT_LI m, k, l
        ld t0, -\m*8(s0)
        li t1, \k
        bgt t0, t1, \l
.endm
.macro vJGT_AI k, l
        li t1, \k
        bgt a0, t1, \l
.endm
.macro vJGT_BI k, l
        li t1, \k
        bgt a1, t1, \l
.endm
.macro vJGT_AG g, l
        ld t0, \g
        bgt a0, t0, \l
.endm
.macro vJGT_AL m, l
        ld t0, -\m*8(s0)
        bgt a0, t0, \l
.endm
.macro vJGT_FI f, k, l
        ld t0, (\f)*8(a0)
        li t1, \k
        bgt t0, t1, \l
.endm
.macro vJLE_GI g, k, l
        ld t0, \g
        li t1, \k
        ble t0, t1, \l
.endm
.macro vJLE_LI m, k, l
        ld t0, -\m*8(s0)
        li t1, \k
        ble t0, t1, \l
.endm
.macro vJLE_AI k, l
        li t1, \k
        ble a0, t1, \l
.endm
.macro vJLE_BI k, l
        li t1, \k
        ble a1, t1, \l
.endm
.macro vJLE_AG g, l
        ld t0, \g
        ble a0, t0, \l
.endm
.macro vJLE_AL m, l
        ld t0, -\m*8(s0)
        ble a0, t0, \l
.endm
.macro vJLE_FI f, k, l
        ld t0, (\f)*8(a0)
        li t1, \k
        ble t0, t1, \l
.endm
.macro vJGE_GI g, k, l
        ld t0, \g
        li t1, \k
        bge t0, t1, \l
.endm
.macro vJGE_LI m, k, l
        ld t0, -\m*8(s0)
        li t1, \k
        bge t0, t1, \l
.endm
.macro vJGE_AI k, l
        li t1, \k
        bge a0, t1, \l
.endm
.macro vJGE_BI k, l
        li t1, \k
        bge a1, t1, \l
.endm
.macro vJGE_AG g, l
        ld t0, \g
        bge a0, t0, \l
.endm
.macro vJGE_AL m, l
        ld t0, -\m*8(s0)
        bge a0, t0, \l
.endm
.macro vJGE_FI f, k, l
        ld t0, (\f)*8(a0)
        li t1, \k
        bge t0, t1, \l
.endm

# ---- argument staging (slot n = 1..6 in t2, t3, t4, t5, t6, a6) ----
.macro vARGA n
.if \n == 1
        mv t2, a0
.elseif \n == 2
        mv t3, a0
.elseif \n == 3
        mv t4, a0
.elseif \n == 4
        mv t5, a0
.elseif \n == 5
        mv t6, a0
.elseif \n == 6
        mv a6, a0
.endif
.endm
.macro vARGI n, k
.if \n == 1
        li t2, \k
.elseif \n == 2
        li t3, \k
.elseif \n == 3
        li t4, \k
.elseif \n == 4
        li t5, \k
.elseif \n == 5
        li t6, \k
.elseif \n == 6
        li a6, \k
.endif
.endm
.macro vARGZ n
.if \n == 1
        li t2, 0
.elseif \n == 2
        li t3, 0
.elseif \n == 3
        li t4, 0
.elseif \n == 4
        li t5, 0
.elseif \n == 5
        li t6, 0
.elseif \n == 6
        li a6, 0
.endif
.endm
.macro vARGS n, s
.if \n == 1
        la t2, \s
.elseif \n == 2
        la t3, \s
.elseif \n == 3
        la t4, \s
.elseif \n == 4
        la t5, \s
.elseif \n == 5
        la t6, \s
.elseif \n == 6
        la a6, \s
.endif
.endm
.macro vARGG n, g
.if \n == 1
        ld t2, \g
.elseif \n == 2
        ld t3, \g
.elseif \n == 3
        ld t4, \g
.elseif \n == 4
        ld t5, \g
.elseif \n == 5
        ld t6, \g
.elseif \n == 6
        ld a6, \g
.endif
.endm
.macro vARGL n, m
.if \n == 1
        ld t2, -\m*8(s0)
.elseif \n == 2
        ld t3, -\m*8(s0)
.elseif \n == 3
        ld t4, -\m*8(s0)
.elseif \n == 4
        ld t5, -\m*8(s0)
.elseif \n == 5
        ld t6, -\m*8(s0)
.elseif \n == 6
        ld a6, -\m*8(s0)
.endif
.endm
.macro vARGMA n, k
.if \n == 1
        ld t2, (\k)*8(a0)
.elseif \n == 2
        ld t3, (\k)*8(a0)
.elseif \n == 3
        ld t4, (\k)*8(a0)
.elseif \n == 4
        ld t5, (\k)*8(a0)
.elseif \n == 5
        ld t6, (\k)*8(a0)
.elseif \n == 6
        ld a6, (\k)*8(a0)
.endif
.endm
.macro vARG_BF n, f
.if \n == 1
        ld t2, (\f)*8(a1)
.elseif \n == 2
        ld t3, (\f)*8(a1)
.elseif \n == 3
        ld t4, (\f)*8(a1)
.elseif \n == 4
        ld t5, (\f)*8(a1)
.elseif \n == 5
        ld t6, (\f)*8(a1)
.elseif \n == 6
        ld a6, (\f)*8(a1)
.endif
.endm
.macro vARGSUBG n, g
        ld t0, \g
.if \n == 1
        sub t2, t2, t0
.elseif \n == 2
        sub t3, t3, t0
.elseif \n == 3
        sub t4, t4, t0
.elseif \n == 4
        sub t5, t5, t0
.elseif \n == 5
        sub t6, t6, t0
.elseif \n == 6
        sub a6, a6, t0
.endif
.endm
.macro vARGSUBL n, m
        ld t0, -\m*8(s0)
.if \n == 1
        sub t2, t2, t0
.elseif \n == 2
        sub t3, t3, t0
.elseif \n == 3
        sub t4, t4, t0
.elseif \n == 4
        sub t5, t5, t0
.elseif \n == 5
        sub t6, t6, t0
.elseif \n == 6
        sub a6, a6, t0
.endif
.endm
.macro vARGSUBI n, k
        li t0, \k
.if \n == 1
        sub t2, t2, t0
.elseif \n == 2
        sub t3, t3, t0
.elseif \n == 3
        sub t4, t4, t0
.elseif \n == 4
        sub t5, t5, t0
.elseif \n == 5
        sub t6, t6, t0
.elseif \n == 6
        sub a6, a6, t0
.endif
.endm
.macro vARGMULI n, k
        li t0, \k
.if \n == 1
        mul t2, t2, t0
.elseif \n == 2
        mul t3, t3, t0
.elseif \n == 3
        mul t4, t4, t0
.elseif \n == 4
        mul t5, t5, t0
.elseif \n == 5
        mul t6, t6, t0
.elseif \n == 6
        mul a6, a6, t0
.endif
.endm
.macro vARGADDS n, s
        la t0, \s
.if \n == 1
        add t2, t2, t0
.elseif \n == 2
        add t3, t3, t0
.elseif \n == 3
        add t4, t4, t0
.elseif \n == 4
        add t5, t5, t0
.elseif \n == 5
        add t6, t6, t0
.elseif \n == 6
        add a6, a6, t0
.endif
.endm

# ----------------------------------------------------------------------
# Freestanding runtime, RV64 syscall glue.
#
# Together with the architecture-neutral runtime.s (printf, memset,
# memcmp, free -- included below) this replaces libc and the C runtime:
# _start replaces crt0, and the OS-facing functions (open, read, close,
# write, malloc, exit) are implemented with direct Linux RISC-V
# syscalls (ecall: number in a7, arguments in a0-a5).  The call sites
# in the body and in runtime.s are unchanged: these functions keep the
# same names and the standard RISC-V calling convention.  RISC-V Linux
# has no plain open; the wrapper uses openat(AT_FDCWD, path, flags, 0).
# ----------------------------------------------------------------------

.text

# ---- process entry and exit -----------------------------------------

.globl _start
_start:                              # exit(main(argc, argv))
.option push                         # crt0 duty: initialize gp so the
.option norelax                      # linker's gp-relative relaxations
        la gp, __global_pointer$     # work (must itself not be relaxed)
.option pop
        ld a0, 0(sp)                 # argc
        addi a1, sp, 8               # argv
        call main
                                     # status in a0; fall through
.globl exit
exit:                                # exit(status)
        li a7, 93                    # SYS_exit
        ecall

# ---- file I/O --------------------------------------------------------

.globl open
open:                                # open(path, flags) -> fd or < 0
        mv a2, a1                    # flags
        mv a1, a0                    # path
        li a0, -100                  # AT_FDCWD
        li a3, 0                     # mode (unused: c4 never creates)
        li a7, 56                    # SYS_openat
        ecall
        ret

.globl read
read:                                # read(fd, buf, count) -> n or < 0
        li a7, 63                    # SYS_read
        ecall
        ret

.globl write
write:                               # write(fd, buf, count) -> n or < 0
        li a7, 64                    # SYS_write
        ecall
        ret

.globl close
close:                               # close(fd) -> 0 or < 0
        li a7, 57                    # SYS_close
        ecall
        ret

# ---- memory ----------------------------------------------------------

.globl malloc
malloc:                              # malloc(size) -> ptr or 0
        mv a1, a0                    # length
        li a0, 0                     # addr = 0 (kernel chooses)
        li a2, 3                     # PROT_READ|PROT_WRITE
        li a3, 0x22                  # MAP_PRIVATE|MAP_ANONYMOUS
        li a4, -1                    # fd = -1
        li a5, 0                     # offset = 0
        li a7, 222                   # SYS_mmap
        ecall
        bgez a0, .Lrt_malloc_ok      # errors are small negative values
        li a0, 0                     # failure -> 0, like malloc
.Lrt_malloc_ok:
        ret

.include "runtime.s"

.include "c4.s"

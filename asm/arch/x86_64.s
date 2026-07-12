# arch/x86_64.s - x86-64 implementation of the c4.s virtual ISA
#
# Defines WORDSZ and every v-prefixed macro used by the architecture-neutral
# body of c4.s, then includes it.  Each macro expands to exactly the
# instruction sequence of the original hand-written x86-64 translation.
#
# Virtual registers: A = rax (accumulator), B = rcx, C = rdx (scratch).
# Locals are addressed as [rbp - n*WORDSZ], n = word index from the equates
# in the body.  Arguments follow the System V AMD64 ABI (rdi, rsi, rdx,
# rcx, r8, r9; al = 0 before variadic calls).
#
# Build (from the repo root; see the header of c4.s for the details):
#     as -mx86-used-note=no -I. arch/x86_64.s -o c4.o
#     ld -n -Ttext 0x400000 -o c4.elf c4.o && objcopy -O binary c4.elf c4

.intel_syntax noprefix

WORDSZ = 8
ELF_MACHINE = 62               /* e_machine: EM_X86_64 */
ELF_FLAGS = 0

.include "elf.s"                /* ELF header, first bytes of .text */

# ---- function structure ----
.macro vENTER k                  # prologue, \k local words
        push rbp
        mov rbp, rsp
        sub rsp, \k*8
.endm
.macro vRET                      # epilogue; returns A
        mov rsp, rbp
        pop rbp
        ret
.endm
.macro vRETI k                   # return immediate \k
        mov eax, \k
        mov rsp, rbp
        pop rbp
        ret
.endm
.macro vSTARG n, m               # local \m = incoming argument \n
.if \n == 1
        mov [rbp - \m*8], rdi
.elseif \n == 2
        mov [rbp - \m*8], rsi
.elseif \n == 3
        mov [rbp - \m*8], rdx
.elseif \n == 4
        mov [rbp - \m*8], rcx
.elseif \n == 5
        mov [rbp - \m*8], r8
.elseif \n == 6
        mov [rbp - \m*8], r9
.endif
.endm
.macro vCALL fn                  # call, fixed argument list
        call \fn
.endm
.macro vCALLV fn                 # call, variadic (al = 0)
        xor eax, eax
        call \fn
.endm
.macro vRES                      # A = call result
.endm                            # (result is already in rax)
.macro vRES32                    # A = sign-extended 32-bit call result
        cdqe
.endm

# ---- loads and stores ----
.macro vLDAG g               # A = word[g]
        mov rax, [\g]
.endm
.macro vLDBG g               # B = word[g]
        mov rcx, [\g]
.endm
.macro vSTAG g               # word[g] = A
        mov [\g], rax
.endm
.macro vSTBG g               # word[g] = B
        mov [\g], rcx
.endm
.macro vLDAL m               # A = local m
        mov rax, [rbp - \m*8]
.endm
.macro vLDBL m               # B = local m
        mov rcx, [rbp - \m*8]
.endm
.macro vSTAL m               # local m = A
        mov [rbp - \m*8], rax
.endm
.macro vSTBL m               # local m = B
        mov [rbp - \m*8], rcx
.endm
.macro vSTCL m               # local m = C
        mov [rbp - \m*8], rdx
.endm
.macro vLDAI k               # A = k
        mov rax, \k
.endm
.macro vLDBI k               # B = k
        mov rcx, \k
.endm
.macro vLDAS s               # A = &s
        mov eax, offset \s
.endm
.macro vSTIG g, k            # word[g] = k
        mov qword ptr [\g], \k
.endm
.macro vSTIL m, k            # local m = k
        mov qword ptr [rbp - \m*8], \k
.endm
.macro vSTSG g, s            # word[g] = &s
        mov qword ptr [\g], offset \s
.endm
.macro vDEREFA               # A = word[A]
        mov rax, [rax]
.endm
.macro vDEREFAB              # B = word[A]
        mov rcx, [rax]
.endm
.macro vDEREFBA              # A = word[B]
        mov rax, [rcx]
.endm
.macro vDEREFAC              # C = word[A]
        mov rdx, [rax]
.endm
.macro vSTWA_B               # word[A] = B
        mov [rax], rcx
.endm
.macro vSTWB_A               # word[B] = A
        mov [rcx], rax
.endm
.macro vSTWA_I k             # word[A] = k
        mov qword ptr [rax], \k
.endm
.macro vLDSBA                # A = signed byte[A]
        movsx rax, byte ptr [rax]
.endm
.macro vLDSBB                # B = signed byte[B]
        movsx rcx, byte ptr [rcx]
.endm
.macro vLDSBAB k             # B = signed byte[A + k]
        movsx rcx, byte ptr [rax + \k]
.endm
.macro vSTBA_B               # byte[A] = low byte of B
        mov byte ptr [rax], cl
.endm
.macro vSTBB_A               # byte[B] = low byte of A
        mov byte ptr [rcx], al
.endm
.macro vSTBAB_Z              # byte[A + B] = 0
        mov byte ptr [rax+rcx], 0
.endm
.macro vSEXTBYTEA            # A = sign-extended low byte of A
        movsx rax, al
.endm
.macro vLDAF f               # A = word[A + f words]
        mov rax, [rax + (\f)*8]
.endm
.macro vLDBF f               # B = word[A + f words]
        mov rcx, [rax + (\f)*8]
.endm
.macro vLDA_BF f             # A = word[B + f words]
        mov rax, [rcx + (\f)*8]
.endm
.macro vLDB_BF f             # B = word[B + f words]
        mov rcx, [rcx + (\f)*8]
.endm
.macro vSTF_B f              # word[A + f words] = B
        mov [rax + (\f)*8], rcx
.endm
.macro vSTF_I f, k           # word[A + f words] = k
        mov qword ptr [rax + (\f)*8], \k
.endm

# ---- ALU ----
.macro vADDAB                # A += B
        add rax, rcx
.endm
.macro vADDBA                # B += A
        add rcx, rax
.endm
.macro vADDAI k              # A += k
        add rax, \k
.endm
.macro vADDAW k              # A += k words
        add rax, (\k)*8
.endm
.macro vADDBI k              # B += k
        add rcx, \k
.endm
.macro vADDAL m              # A += local m
        add rax, [rbp - \m*8]
.endm
.macro vADDAS s              # A += &s
        add rax, offset \s
.endm
.macro vSUBAI k              # A -= k
        sub rax, \k
.endm
.macro vSUBBI k              # B -= k
        sub rcx, \k
.endm
.macro vSUBAG g              # A -= word[g]
        sub rax, [\g]
.endm
.macro vSUBA_BF f            # A -= word[B + f words]
        sub rax, [rcx + (\f)*8]
.endm
.macro vMULAI k              # A *= k
        imul rax, rax, \k
.endm
.macro vMULBI k              # B *= k
        imul rcx, rcx, \k
.endm
.macro vMULAW                # A *= WORDSZ (int* scaling)
        imul rax, rax, 8
.endm
.macro vSHLAI k              # A <<= k
        shl rax, \k
.endm
.macro vANDBI k              # B &= k
        and rcx, \k
.endm
.macro vALIGNA               # A &= -WORDSZ (align down)
        and rax, -8
.endm
.macro vNEGB                 # B = -B
        neg rcx
.endm
.macro vORBL m               # B |= local m
        or rcx, [rbp - \m*8]
.endm
.macro vXORBL m              # B ^= local m
        xor rcx, [rbp - \m*8]
.endm
.macro vANDBL m              # B &= local m
        and rcx, [rbp - \m*8]
.endm
.macro vADDBL m              # B += local m
        add rcx, [rbp - \m*8]
.endm
.macro vSUBBL m              # B -= local m
        sub rcx, [rbp - \m*8]
.endm
.macro vMULBL m              # B *= local m
        imul rcx, [rbp - \m*8]
.endm
.macro vSHLCB                # C <<= B
        shl rdx, cl
.endm
.macro vSARCB                # C >>= B (arithmetic)
        sar rdx, cl
.endm

# ---- read-modify-write on memory ----
.macro vINCGI g, k           # word[g] += k
        add qword ptr [\g], \k
.endm
.macro vDECGI g, k           # word[g] -= k
        sub qword ptr [\g], \k
.endm
.macro vINCGW g, k           # word[g] += k words
        add qword ptr [\g], (\k)*8
.endm
.macro vDECGW g, k           # word[g] -= k words
        sub qword ptr [\g], (\k)*8
.endm
.macro vINCLI m, k           # local m += k
        add qword ptr [rbp - \m*8], \k
.endm
.macro vDECLI m, k           # local m -= k
        sub qword ptr [rbp - \m*8], \k
.endm
.macro vINCLW m, k           # local m += k words
        add qword ptr [rbp - \m*8], (\k)*8
.endm
.macro vDECLW m, k           # local m -= k words
        sub qword ptr [rbp - \m*8], (\k)*8
.endm
.macro vADDLA m              # local m += A
        add [rbp - \m*8], rax
.endm
.macro vSUBLA m              # local m -= A
        sub [rbp - \m*8], rax
.endm

# ---- division (dividend in A) ----
.macro vDIVL m                   # A = A / local m   (clobbers C)
        cqo
        idiv qword ptr [rbp - \m*8]
.endm
.macro vMODL m                   # C = A % local m   (clobbers A)
        cqo
        idiv qword ptr [rbp - \m*8]
.endm                            # (remainder is left in rdx = C)

# ---- comparisons producing 0/1 in B ----
.macro vSETEQ m                  # B = (B == local m)
        cmp rcx, [rbp - \m*8]
        sete cl
        movzx rcx, cl
.endm
.macro vSETNE m                  # B = (B != local m)
        cmp rcx, [rbp - \m*8]
        setne cl
        movzx rcx, cl
.endm
.macro vSETLT m                  # B = (B < local m)
        cmp rcx, [rbp - \m*8]
        setl cl
        movzx rcx, cl
.endm
.macro vSETGT m                  # B = (B > local m)
        cmp rcx, [rbp - \m*8]
        setg cl
        movzx rcx, cl
.endm
.macro vSETLE m                  # B = (B <= local m)
        cmp rcx, [rbp - \m*8]
        setle cl
        movzx rcx, cl
.endm
.macro vSETGE m                  # B = (B >= local m)
        cmp rcx, [rbp - \m*8]
        setge cl
        movzx rcx, cl
.endm

# ---- branches ----
.macro vJMP l
        jmp \l
.endm
.macro vJZA l                    # branch if A == 0
        test rax, rax
        je \l
.endm
.macro vJNZA l                   # branch if A != 0
        test rax, rax
        jne \l
.endm
.macro vJNZRES l                 # branch if 32-bit call result != 0
        test eax, eax
        jne \l
.endm
.macro vJNE_A_BF f, l            # branch if A != word[B + f words]
        cmp rax, [rcx + (\f)*8]
        jne \l
.endm
# fused compare-and-branch: vJcc_XY, cc = EQ NE LT GT LE GE (signed),
# X vs Y: GI word[g] vs imm, LI local vs imm, AI A vs imm, BI B vs imm,
# AG A vs word[g], AL A vs local, FI word[A + f words] vs imm.
.macro vJEQ_GI g, k, l
        cmp qword ptr [\g], \k
        je \l
.endm
.macro vJEQ_LI m, k, l
        cmp qword ptr [rbp - \m*8], \k
        je \l
.endm
.macro vJEQ_AI k, l
        cmp rax, \k
        je \l
.endm
.macro vJEQ_BI k, l
        cmp rcx, \k
        je \l
.endm
.macro vJEQ_AG g, l
        cmp rax, [\g]
        je \l
.endm
.macro vJEQ_AL m, l
        cmp rax, [rbp - \m*8]
        je \l
.endm
.macro vJEQ_FI f, k, l
        cmp qword ptr [rax + (\f)*8], \k
        je \l
.endm
.macro vJNE_GI g, k, l
        cmp qword ptr [\g], \k
        jne \l
.endm
.macro vJNE_LI m, k, l
        cmp qword ptr [rbp - \m*8], \k
        jne \l
.endm
.macro vJNE_AI k, l
        cmp rax, \k
        jne \l
.endm
.macro vJNE_BI k, l
        cmp rcx, \k
        jne \l
.endm
.macro vJNE_AG g, l
        cmp rax, [\g]
        jne \l
.endm
.macro vJNE_AL m, l
        cmp rax, [rbp - \m*8]
        jne \l
.endm
.macro vJNE_FI f, k, l
        cmp qword ptr [rax + (\f)*8], \k
        jne \l
.endm
.macro vJLT_GI g, k, l
        cmp qword ptr [\g], \k
        jl \l
.endm
.macro vJLT_LI m, k, l
        cmp qword ptr [rbp - \m*8], \k
        jl \l
.endm
.macro vJLT_AI k, l
        cmp rax, \k
        jl \l
.endm
.macro vJLT_BI k, l
        cmp rcx, \k
        jl \l
.endm
.macro vJLT_AG g, l
        cmp rax, [\g]
        jl \l
.endm
.macro vJLT_AL m, l
        cmp rax, [rbp - \m*8]
        jl \l
.endm
.macro vJLT_FI f, k, l
        cmp qword ptr [rax + (\f)*8], \k
        jl \l
.endm
.macro vJGT_GI g, k, l
        cmp qword ptr [\g], \k
        jg \l
.endm
.macro vJGT_LI m, k, l
        cmp qword ptr [rbp - \m*8], \k
        jg \l
.endm
.macro vJGT_AI k, l
        cmp rax, \k
        jg \l
.endm
.macro vJGT_BI k, l
        cmp rcx, \k
        jg \l
.endm
.macro vJGT_AG g, l
        cmp rax, [\g]
        jg \l
.endm
.macro vJGT_AL m, l
        cmp rax, [rbp - \m*8]
        jg \l
.endm
.macro vJGT_FI f, k, l
        cmp qword ptr [rax + (\f)*8], \k
        jg \l
.endm
.macro vJLE_GI g, k, l
        cmp qword ptr [\g], \k
        jle \l
.endm
.macro vJLE_LI m, k, l
        cmp qword ptr [rbp - \m*8], \k
        jle \l
.endm
.macro vJLE_AI k, l
        cmp rax, \k
        jle \l
.endm
.macro vJLE_BI k, l
        cmp rcx, \k
        jle \l
.endm
.macro vJLE_AG g, l
        cmp rax, [\g]
        jle \l
.endm
.macro vJLE_AL m, l
        cmp rax, [rbp - \m*8]
        jle \l
.endm
.macro vJLE_FI f, k, l
        cmp qword ptr [rax + (\f)*8], \k
        jle \l
.endm
.macro vJGE_GI g, k, l
        cmp qword ptr [\g], \k
        jge \l
.endm
.macro vJGE_LI m, k, l
        cmp qword ptr [rbp - \m*8], \k
        jge \l
.endm
.macro vJGE_AI k, l
        cmp rax, \k
        jge \l
.endm
.macro vJGE_BI k, l
        cmp rcx, \k
        jge \l
.endm
.macro vJGE_AG g, l
        cmp rax, [\g]
        jge \l
.endm
.macro vJGE_AL m, l
        cmp rax, [rbp - \m*8]
        jge \l
.endm
.macro vJGE_FI f, k, l
        cmp qword ptr [rax + (\f)*8], \k
        jge \l
.endm

# ---- argument staging (slot n = 1..6) ----
.macro vARGA n
.if \n == 1
        mov rdi, rax
.elseif \n == 2
        mov rsi, rax
.elseif \n == 3
        mov rdx, rax
.elseif \n == 4
        mov rcx, rax
.elseif \n == 5
        mov r8, rax
.elseif \n == 6
        mov r9, rax
.endif
.endm

.macro vARGI n, k
.if \n == 1
        mov edi, \k
.elseif \n == 2
        mov esi, \k
.elseif \n == 3
        mov edx, \k
.elseif \n == 4
        mov ecx, \k
.elseif \n == 5
        mov r8d, \k
.elseif \n == 6
        mov r9d, \k
.endif
.endm

.macro vARGZ n
.if \n == 1
        xor edi, edi
.elseif \n == 2
        xor esi, esi
.elseif \n == 3
        xor edx, edx
.elseif \n == 4
        xor ecx, ecx
.elseif \n == 5
        xor r8d, r8d
.elseif \n == 6
        xor r9d, r9d
.endif
.endm

.macro vARGS n, s
.if \n == 1
        mov edi, offset \s
.elseif \n == 2
        mov esi, offset \s
.elseif \n == 3
        mov edx, offset \s
.elseif \n == 4
        mov ecx, offset \s
.elseif \n == 5
        mov r8d, offset \s
.elseif \n == 6
        mov r9d, offset \s
.endif
.endm

.macro vARGG n, g
.if \n == 1
        mov rdi, [\g]
.elseif \n == 2
        mov rsi, [\g]
.elseif \n == 3
        mov rdx, [\g]
.elseif \n == 4
        mov rcx, [\g]
.elseif \n == 5
        mov r8, [\g]
.elseif \n == 6
        mov r9, [\g]
.endif
.endm

.macro vARGL n, m
.if \n == 1
        mov rdi, [rbp - \m*8]
.elseif \n == 2
        mov rsi, [rbp - \m*8]
.elseif \n == 3
        mov rdx, [rbp - \m*8]
.elseif \n == 4
        mov rcx, [rbp - \m*8]
.elseif \n == 5
        mov r8, [rbp - \m*8]
.elseif \n == 6
        mov r9, [rbp - \m*8]
.endif
.endm

.macro vARGMA n, k
.if \n == 1
        mov rdi, [rax + (\k)*8]
.elseif \n == 2
        mov rsi, [rax + (\k)*8]
.elseif \n == 3
        mov rdx, [rax + (\k)*8]
.elseif \n == 4
        mov rcx, [rax + (\k)*8]
.elseif \n == 5
        mov r8, [rax + (\k)*8]
.elseif \n == 6
        mov r9, [rax + (\k)*8]
.endif
.endm

.macro vARG_BF n, f
.if \n == 1
        mov rdi, [rcx + (\f)*8]
.elseif \n == 2
        mov rsi, [rcx + (\f)*8]
.elseif \n == 3
        mov rdx, [rcx + (\f)*8]
.elseif \n == 4
        mov rcx, [rcx + (\f)*8]
.elseif \n == 5
        mov r8, [rcx + (\f)*8]
.elseif \n == 6
        mov r9, [rcx + (\f)*8]
.endif
.endm

.macro vARGSUBG n, g
.if \n == 1
        sub rdi, [\g]
.elseif \n == 2
        sub rsi, [\g]
.elseif \n == 3
        sub rdx, [\g]
.elseif \n == 4
        sub rcx, [\g]
.elseif \n == 5
        sub r8, [\g]
.elseif \n == 6
        sub r9, [\g]
.endif
.endm

.macro vARGSUBL n, m
.if \n == 1
        sub rdi, [rbp - \m*8]
.elseif \n == 2
        sub rsi, [rbp - \m*8]
.elseif \n == 3
        sub rdx, [rbp - \m*8]
.elseif \n == 4
        sub rcx, [rbp - \m*8]
.elseif \n == 5
        sub r8, [rbp - \m*8]
.elseif \n == 6
        sub r9, [rbp - \m*8]
.endif
.endm

.macro vARGSUBI n, k
.if \n == 1
        sub rdi, \k
.elseif \n == 2
        sub rsi, \k
.elseif \n == 3
        sub rdx, \k
.elseif \n == 4
        sub rcx, \k
.elseif \n == 5
        sub r8, \k
.elseif \n == 6
        sub r9, \k
.endif
.endm

.macro vARGMULI n, k
.if \n == 1
        imul rdi, rdi, \k
.elseif \n == 2
        imul rsi, rsi, \k
.elseif \n == 3
        imul rdx, rdx, \k
.elseif \n == 4
        imul rcx, rcx, \k
.elseif \n == 5
        imul r8, r8, \k
.elseif \n == 6
        imul r9, r9, \k
.endif
.endm

.macro vARGADDS n, s
.if \n == 1
        add rdi, offset \s
.elseif \n == 2
        add rsi, offset \s
.elseif \n == 3
        add rdx, offset \s
.elseif \n == 4
        add rcx, offset \s
.elseif \n == 5
        add r8, offset \s
.elseif \n == 6
        add r9, offset \s
.endif
.endm

# ----------------------------------------------------------------------
# Freestanding runtime, x86-64 syscall glue.
#
# Together with the architecture-neutral runtime.s (printf, memset,
# memcmp, free -- included below) this replaces libc and the C runtime:
# _start replaces crt0, and the OS-facing functions (open, read, close,
# write, malloc, exit) are implemented with direct Linux x86-64
# syscalls.  The call sites in the body and in runtime.s are unchanged:
# these functions keep the same names and the System V AMD64 calling
# convention.
# ----------------------------------------------------------------------

.text

# ---- process entry and exit -----------------------------------------

.globl _start
_start:                              # exit(main(argc, argv))
        mov rdi, [rsp]               # argc
        lea rsi, [rsp+8]             # argv
        call main
        mov rdi, rax                 # fall through into exit
.globl exit
exit:                                # exit(status)
        mov eax, 60                  # SYS_exit
        syscall

# ---- file I/O --------------------------------------------------------

.globl open
open:                                # open(path, flags) -> fd or < 0
        xor edx, edx                 # mode (unused: c4 never creates)
        mov eax, 2                   # SYS_open
        syscall
        ret

.globl read
read:                                # read(fd, buf, count) -> n or < 0
        xor eax, eax                 # SYS_read
        syscall
        ret

.globl write
write:                               # write(fd, buf, count) -> n or < 0
        mov eax, 1                   # SYS_write
        syscall
        ret

.globl close
close:                               # close(fd) -> 0 or < 0
        mov eax, 3                   # SYS_close
        syscall
        ret

# ---- memory ----------------------------------------------------------

.globl malloc
malloc:                              # malloc(size) -> ptr or 0
        mov rsi, rdi                 # length
        xor edi, edi                 # addr = 0 (kernel chooses)
        mov edx, 3                   # PROT_READ|PROT_WRITE
        mov r10d, 0x22               # MAP_PRIVATE|MAP_ANONYMOUS
        mov r8, -1                   # fd = -1
        xor r9d, r9d                 # offset = 0
        mov eax, 9                   # SYS_mmap
        syscall
        test rax, rax                # errors are small negative values
        jns .Lrt_malloc_ok
        xor eax, eax                 # failure -> 0, like malloc
.Lrt_malloc_ok:
        ret

.include "runtime.s"

.include "c4.s"

# End-of-image labels for the sizes in the ELF program header (elf.s):
# the file ends with .data, the memory image with .bss.
.data
ELF_fileend:
.bss
ELF_memend:

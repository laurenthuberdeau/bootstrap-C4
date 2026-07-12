# arch/i386.s - i386 (32-bit x86) implementation of the c4.s virtual ISA
#
# Defines WORDSZ and every v-prefixed macro used by the architecture-neutral
# body of c4.s, then includes it.
#
# Virtual registers: A = eax (accumulator), B = ecx, C = edx (scratch).
# Locals are addressed as [ebp - n*WORDSZ], n = word index from the equates
# in the body.  Arguments follow the i386 System V (cdecl) ABI: all on the
# stack.  vENTER reserves a fixed outgoing-argument area (6 slots) at the
# bottom of the frame, so vARG* macros store to [esp + (n-1)*4] and no
# cleanup is needed after calls.  C (edx) is used as scratch by the
# memory-to-memory vARG* macros; the body never keeps C live across
# argument staging.
#
# Semantics note: WORDSZ = 4, so this build behaves as c4.c would with a
# 32-bit "int" (i.e. without its "#define int long long").  This is the
# one documented deviation from the source embedded in c4.s; it is exact
# for the 64-bit architectures.
#
# Build (from the repo root; freestanding, no 32-bit libc needed):
#     gcc -m32 -nostdlib -static -no-pie -I. arch/i386.s -o c4-i386

.intel_syntax noprefix

WORDSZ = 4
ELF_MACHINE = 3               /* e_machine: EM_386 */
ELF_FLAGS = 0

.include "elf.s"                /* ELF header, first bytes of .text */

# ---- function structure ----
.macro vENTER k                  # prologue, \k local words
        push ebp
        mov ebp, esp
        sub esp, ((\k*4 + 24 + 7) & -16) + 8
.endm                            # keeps esp 16-aligned at call sites and
                                 # reserves 24 bytes of outgoing arguments
.macro vRET                      # epilogue; returns A
        mov esp, ebp
        pop ebp
        ret
.endm
.macro vRETI k                   # return immediate \k
        mov eax, \k
        mov esp, ebp
        pop ebp
        ret
.endm
.macro vSTARG n, m               # local \m = incoming argument \n
        mov eax, [ebp + 4 + \n*4]
        mov [ebp - \m*4], eax
.endm
.macro vCALL fn                  # call, fixed argument list
        call \fn
.endm
.macro vCALLV fn                 # call, variadic
        call \fn
.endm
.macro vRES                      # A = call result
.endm                            # (result is already in eax)
.macro vRES32                    # A = sign-extended 32-bit call result
.endm                            # (words are already 32 bits)

# ---- loads and stores ----
.macro vLDAG g               # A = word[g]
        mov eax, [\g]
.endm
.macro vLDBG g               # B = word[g]
        mov ecx, [\g]
.endm
.macro vSTAG g               # word[g] = A
        mov [\g], eax
.endm
.macro vSTBG g               # word[g] = B
        mov [\g], ecx
.endm
.macro vLDAL m               # A = local m
        mov eax, [ebp - \m*4]
.endm
.macro vLDBL m               # B = local m
        mov ecx, [ebp - \m*4]
.endm
.macro vSTAL m               # local m = A
        mov [ebp - \m*4], eax
.endm
.macro vSTBL m               # local m = B
        mov [ebp - \m*4], ecx
.endm
.macro vSTCL m               # local m = C
        mov [ebp - \m*4], edx
.endm
.macro vLDAI k               # A = k
        mov eax, \k
.endm
.macro vLDBI k               # B = k
        mov ecx, \k
.endm
.macro vLDAS s               # A = &s
        mov eax, offset \s
.endm
.macro vSTIG g, k            # word[g] = k
        mov dword ptr [\g], \k
.endm
.macro vSTIL m, k            # local m = k
        mov dword ptr [ebp - \m*4], \k
.endm
.macro vSTSG g, s            # word[g] = &s
        mov dword ptr [\g], offset \s
.endm
.macro vDEREFA               # A = word[A]
        mov eax, [eax]
.endm
.macro vDEREFAB              # B = word[A]
        mov ecx, [eax]
.endm
.macro vDEREFBA              # A = word[B]
        mov eax, [ecx]
.endm
.macro vDEREFAC              # C = word[A]
        mov edx, [eax]
.endm
.macro vSTWA_B               # word[A] = B
        mov [eax], ecx
.endm
.macro vSTWB_A               # word[B] = A
        mov [ecx], eax
.endm
.macro vSTWA_I k             # word[A] = k
        mov dword ptr [eax], \k
.endm
.macro vLDSBA                # A = signed byte[A]
        movsx eax, byte ptr [eax]
.endm
.macro vLDSBB                # B = signed byte[B]
        movsx ecx, byte ptr [ecx]
.endm
.macro vLDSBAB k             # B = signed byte[A + k]
        movsx ecx, byte ptr [eax + \k]
.endm
.macro vSTBA_B               # byte[A] = low byte of B
        mov byte ptr [eax], cl
.endm
.macro vSTBB_A               # byte[B] = low byte of A
        mov byte ptr [ecx], al
.endm
.macro vSTBAB_Z              # byte[A + B] = 0
        mov byte ptr [eax+ecx], 0
.endm
.macro vSEXTBYTEA            # A = sign-extended low byte of A
        movsx eax, al
.endm
.macro vLDAF f               # A = word[A + f words]
        mov eax, [eax + (\f)*4]
.endm
.macro vLDBF f               # B = word[A + f words]
        mov ecx, [eax + (\f)*4]
.endm
.macro vLDA_BF f             # A = word[B + f words]
        mov eax, [ecx + (\f)*4]
.endm
.macro vLDB_BF f             # B = word[B + f words]
        mov ecx, [ecx + (\f)*4]
.endm
.macro vSTF_B f              # word[A + f words] = B
        mov [eax + (\f)*4], ecx
.endm
.macro vSTF_I f, k           # word[A + f words] = k
        mov dword ptr [eax + (\f)*4], \k
.endm

# ---- ALU ----
.macro vADDAB                # A += B
        add eax, ecx
.endm
.macro vADDBA                # B += A
        add ecx, eax
.endm
.macro vADDAI k              # A += k
        add eax, \k
.endm
.macro vADDAW k              # A += k words
        add eax, (\k)*4
.endm
.macro vADDBI k              # B += k
        add ecx, \k
.endm
.macro vADDAL m              # A += local m
        add eax, [ebp - \m*4]
.endm
.macro vADDAS s              # A += &s
        add eax, offset \s
.endm
.macro vSUBAI k              # A -= k
        sub eax, \k
.endm
.macro vSUBBI k              # B -= k
        sub ecx, \k
.endm
.macro vSUBAG g              # A -= word[g]
        sub eax, [\g]
.endm
.macro vSUBA_BF f            # A -= word[B + f words]
        sub eax, [ecx + (\f)*4]
.endm
.macro vMULAI k              # A *= k
        imul eax, eax, \k
.endm
.macro vMULBI k              # B *= k
        imul ecx, ecx, \k
.endm
.macro vMULAW                # A *= WORDSZ (int* scaling)
        imul eax, eax, 4
.endm
.macro vSHLAI k              # A <<= k
        shl eax, \k
.endm
.macro vANDBI k              # B &= k
        and ecx, \k
.endm
.macro vALIGNA               # A &= -WORDSZ (align down)
        and eax, -4
.endm
.macro vNEGB                 # B = -B
        neg ecx
.endm
.macro vORBL m               # B |= local m
        or ecx, [ebp - \m*4]
.endm
.macro vXORBL m              # B ^= local m
        xor ecx, [ebp - \m*4]
.endm
.macro vANDBL m              # B &= local m
        and ecx, [ebp - \m*4]
.endm
.macro vADDBL m              # B += local m
        add ecx, [ebp - \m*4]
.endm
.macro vSUBBL m              # B -= local m
        sub ecx, [ebp - \m*4]
.endm
.macro vMULBL m              # B *= local m
        imul ecx, [ebp - \m*4]
.endm
.macro vSHLCB                # C <<= B
        shl edx, cl
.endm
.macro vSARCB                # C >>= B (arithmetic)
        sar edx, cl
.endm

# ---- read-modify-write on memory ----
.macro vINCGI g, k           # word[g] += k
        add dword ptr [\g], \k
.endm
.macro vDECGI g, k           # word[g] -= k
        sub dword ptr [\g], \k
.endm
.macro vINCGW g, k           # word[g] += k words
        add dword ptr [\g], (\k)*4
.endm
.macro vDECGW g, k           # word[g] -= k words
        sub dword ptr [\g], (\k)*4
.endm
.macro vINCLI m, k           # local m += k
        add dword ptr [ebp - \m*4], \k
.endm
.macro vDECLI m, k           # local m -= k
        sub dword ptr [ebp - \m*4], \k
.endm
.macro vINCLW m, k           # local m += k words
        add dword ptr [ebp - \m*4], (\k)*4
.endm
.macro vDECLW m, k           # local m -= k words
        sub dword ptr [ebp - \m*4], (\k)*4
.endm
.macro vADDLA m              # local m += A
        add [ebp - \m*4], eax
.endm
.macro vSUBLA m              # local m -= A
        sub [ebp - \m*4], eax
.endm

# ---- division (dividend in A) ----
.macro vDIVL m                   # A = A / local m   (clobbers C)
        cdq
        idiv dword ptr [ebp - \m*4]
.endm
.macro vMODL m                   # C = A % local m   (clobbers A)
        cdq
        idiv dword ptr [ebp - \m*4]
.endm                            # (remainder is left in edx = C)

# ---- comparisons producing 0/1 in B ----
.macro vSETEQ m                  # B = (B == local m)
        cmp ecx, [ebp - \m*4]
        sete cl
        movzx ecx, cl
.endm
.macro vSETNE m                  # B = (B != local m)
        cmp ecx, [ebp - \m*4]
        setne cl
        movzx ecx, cl
.endm
.macro vSETLT m                  # B = (B < local m)
        cmp ecx, [ebp - \m*4]
        setl cl
        movzx ecx, cl
.endm
.macro vSETGT m                  # B = (B > local m)
        cmp ecx, [ebp - \m*4]
        setg cl
        movzx ecx, cl
.endm
.macro vSETLE m                  # B = (B <= local m)
        cmp ecx, [ebp - \m*4]
        setle cl
        movzx ecx, cl
.endm
.macro vSETGE m                  # B = (B >= local m)
        cmp ecx, [ebp - \m*4]
        setge cl
        movzx ecx, cl
.endm

# ---- branches ----
.macro vJMP l
        jmp \l
.endm
.macro vJZA l                    # branch if A == 0
        test eax, eax
        je \l
.endm
.macro vJNZA l                   # branch if A != 0
        test eax, eax
        jne \l
.endm
.macro vJNZRES l                 # branch if 32-bit call result != 0
        test eax, eax
        jne \l
.endm
.macro vJNE_A_BF f, l            # branch if A != word[B + f words]
        cmp eax, [ecx + (\f)*4]
        jne \l
.endm
# fused compare-and-branch: vJcc_XY, cc = EQ NE LT GT LE GE (signed),
# X vs Y: GI word[g] vs imm, LI local vs imm, AI A vs imm, BI B vs imm,
# AG A vs word[g], AL A vs local, FI word[A + f words] vs imm.
.macro vJEQ_GI g, k, l
        cmp dword ptr [\g], \k
        je \l
.endm
.macro vJEQ_LI m, k, l
        cmp dword ptr [ebp - \m*4], \k
        je \l
.endm
.macro vJEQ_AI k, l
        cmp eax, \k
        je \l
.endm
.macro vJEQ_BI k, l
        cmp ecx, \k
        je \l
.endm
.macro vJEQ_AG g, l
        cmp eax, [\g]
        je \l
.endm
.macro vJEQ_AL m, l
        cmp eax, [ebp - \m*4]
        je \l
.endm
.macro vJEQ_FI f, k, l
        cmp dword ptr [eax + (\f)*4], \k
        je \l
.endm
.macro vJNE_GI g, k, l
        cmp dword ptr [\g], \k
        jne \l
.endm
.macro vJNE_LI m, k, l
        cmp dword ptr [ebp - \m*4], \k
        jne \l
.endm
.macro vJNE_AI k, l
        cmp eax, \k
        jne \l
.endm
.macro vJNE_BI k, l
        cmp ecx, \k
        jne \l
.endm
.macro vJNE_AG g, l
        cmp eax, [\g]
        jne \l
.endm
.macro vJNE_AL m, l
        cmp eax, [ebp - \m*4]
        jne \l
.endm
.macro vJNE_FI f, k, l
        cmp dword ptr [eax + (\f)*4], \k
        jne \l
.endm
.macro vJLT_GI g, k, l
        cmp dword ptr [\g], \k
        jl \l
.endm
.macro vJLT_LI m, k, l
        cmp dword ptr [ebp - \m*4], \k
        jl \l
.endm
.macro vJLT_AI k, l
        cmp eax, \k
        jl \l
.endm
.macro vJLT_BI k, l
        cmp ecx, \k
        jl \l
.endm
.macro vJLT_AG g, l
        cmp eax, [\g]
        jl \l
.endm
.macro vJLT_AL m, l
        cmp eax, [ebp - \m*4]
        jl \l
.endm
.macro vJLT_FI f, k, l
        cmp dword ptr [eax + (\f)*4], \k
        jl \l
.endm
.macro vJGT_GI g, k, l
        cmp dword ptr [\g], \k
        jg \l
.endm
.macro vJGT_LI m, k, l
        cmp dword ptr [ebp - \m*4], \k
        jg \l
.endm
.macro vJGT_AI k, l
        cmp eax, \k
        jg \l
.endm
.macro vJGT_BI k, l
        cmp ecx, \k
        jg \l
.endm
.macro vJGT_AG g, l
        cmp eax, [\g]
        jg \l
.endm
.macro vJGT_AL m, l
        cmp eax, [ebp - \m*4]
        jg \l
.endm
.macro vJGT_FI f, k, l
        cmp dword ptr [eax + (\f)*4], \k
        jg \l
.endm
.macro vJLE_GI g, k, l
        cmp dword ptr [\g], \k
        jle \l
.endm
.macro vJLE_LI m, k, l
        cmp dword ptr [ebp - \m*4], \k
        jle \l
.endm
.macro vJLE_AI k, l
        cmp eax, \k
        jle \l
.endm
.macro vJLE_BI k, l
        cmp ecx, \k
        jle \l
.endm
.macro vJLE_AG g, l
        cmp eax, [\g]
        jle \l
.endm
.macro vJLE_AL m, l
        cmp eax, [ebp - \m*4]
        jle \l
.endm
.macro vJLE_FI f, k, l
        cmp dword ptr [eax + (\f)*4], \k
        jle \l
.endm
.macro vJGE_GI g, k, l
        cmp dword ptr [\g], \k
        jge \l
.endm
.macro vJGE_LI m, k, l
        cmp dword ptr [ebp - \m*4], \k
        jge \l
.endm
.macro vJGE_AI k, l
        cmp eax, \k
        jge \l
.endm
.macro vJGE_BI k, l
        cmp ecx, \k
        jge \l
.endm
.macro vJGE_AG g, l
        cmp eax, [\g]
        jge \l
.endm
.macro vJGE_AL m, l
        cmp eax, [ebp - \m*4]
        jge \l
.endm
.macro vJGE_FI f, k, l
        cmp dword ptr [eax + (\f)*4], \k
        jge \l
.endm

# ---- argument staging (slot n = 1..6, in the outgoing area) ----
.macro vARGA n
        mov [esp + (\n-1)*4], eax
.endm
.macro vARGI n, k
        mov dword ptr [esp + (\n-1)*4], \k
.endm
.macro vARGZ n
        mov dword ptr [esp + (\n-1)*4], 0
.endm
.macro vARGS n, s
        mov dword ptr [esp + (\n-1)*4], offset \s
.endm
.macro vARGG n, g
        mov edx, [\g]
        mov [esp + (\n-1)*4], edx
.endm
.macro vARGL n, m
        mov edx, [ebp - \m*4]
        mov [esp + (\n-1)*4], edx
.endm
.macro vARGMA n, k
        mov edx, [eax + (\k)*4]
        mov [esp + (\n-1)*4], edx
.endm
.macro vARG_BF n, f
        mov edx, [ecx + (\f)*4]
        mov [esp + (\n-1)*4], edx
.endm
.macro vARGSUBG n, g
        mov edx, [\g]
        sub [esp + (\n-1)*4], edx
.endm
.macro vARGSUBL n, m
        mov edx, [ebp - \m*4]
        sub [esp + (\n-1)*4], edx
.endm
.macro vARGSUBI n, k
        sub dword ptr [esp + (\n-1)*4], \k
.endm
.macro vARGMULI n, k
        imul edx, dword ptr [esp + (\n-1)*4], \k
        mov [esp + (\n-1)*4], edx
.endm
.macro vARGADDS n, s
        add dword ptr [esp + (\n-1)*4], offset \s
.endm

# ----------------------------------------------------------------------
# Freestanding runtime, i386 syscall glue.
#
# Together with the architecture-neutral runtime.s (printf, memset,
# memcmp, free -- included below) this replaces libc and the C runtime:
# _start replaces crt0, and the OS-facing functions (open, read, close,
# write, malloc, exit) are implemented with direct Linux i386 syscalls
# (int 0x80: number in eax, arguments in ebx, ecx, edx, esi, edi, ebp).
# The call sites in the body and in runtime.s are unchanged: these
# functions keep the same names and the cdecl calling convention (all
# arguments on the stack; ebx, esi, edi and ebp are callee-saved and
# preserved where used).
# ----------------------------------------------------------------------

.text

# ---- process entry and exit -----------------------------------------

.globl _start
_start:                              # exit(main(argc, argv))
        mov eax, [esp]               # argc
        lea edx, [esp+4]             # argv
        push edx
        push eax
        call main
        mov ebx, eax                 # status
        mov eax, 1                   # SYS_exit
        int 0x80
.globl exit
exit:                                # exit(status)
        mov ebx, [esp+4]
        mov eax, 1                   # SYS_exit
        int 0x80

# ---- file I/O --------------------------------------------------------

.globl open
open:                                # open(path, flags) -> fd or < 0
        push ebx
        mov ebx, [esp+8]             # path
        mov ecx, [esp+12]            # flags
        xor edx, edx                 # mode (unused: c4 never creates)
        mov eax, 5                   # SYS_open
        int 0x80
        pop ebx
        ret

.globl read
read:                                # read(fd, buf, count) -> n or < 0
        push ebx
        mov ebx, [esp+8]
        mov ecx, [esp+12]
        mov edx, [esp+16]
        mov eax, 3                   # SYS_read
        int 0x80
        pop ebx
        ret

.globl write
write:                               # write(fd, buf, count) -> n or < 0
        push ebx
        mov ebx, [esp+8]
        mov ecx, [esp+12]
        mov edx, [esp+16]
        mov eax, 4                   # SYS_write
        int 0x80
        pop ebx
        ret

.globl close
close:                               # close(fd) -> 0 or < 0
        push ebx
        mov ebx, [esp+8]
        mov eax, 6                   # SYS_close
        int 0x80
        pop ebx
        ret

# ---- memory ----------------------------------------------------------

.globl malloc
malloc:                              # malloc(size) -> ptr or 0
        push ebx
        push esi
        push edi
        push ebp
        xor ebx, ebx                 # addr = 0 (kernel chooses)
        mov ecx, [esp+20]            # length
        mov edx, 3                   # PROT_READ|PROT_WRITE
        mov esi, 0x22                # MAP_PRIVATE|MAP_ANONYMOUS
        mov edi, -1                  # fd = -1
        xor ebp, ebp                 # page offset = 0
        mov eax, 192                 # SYS_mmap2
        int 0x80
        cmp eax, 0xfffff000          # errors are -4095..-1; a valid
        jbe .Lrt_malloc_ok           # mapping may look negative on i386
        xor eax, eax                 # failure -> 0, like malloc
.Lrt_malloc_ok:
        pop ebp
        pop edi
        pop esi
        pop ebx
        ret

.include "runtime.s"

.include "c4.s"

# End-of-image labels for the sizes in the ELF program header (elf.s):
# the file ends with .data, the memory image with .bss.
.data
ELF_fileend:
.bss
ELF_memend:

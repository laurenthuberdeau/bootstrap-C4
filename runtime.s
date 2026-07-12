# runtime.s - architecture-neutral part of the freestanding runtime
#
# Included by every arch/*.s after its macro definitions.  Together with
# the per-arch syscall glue (_start, exit, open, read, close, write,
# malloc) this replaces libc: the functions here contain only logic, so
# like the c4.s body they are written purely in the virtual ISA and are
# shared by all architectures.  The only OS-facing operation they need
# is write(fd, buf, count), which each arch file provides as a syscall
# wrapper.
#
# printf(fmt, ...) supports only what c4 needs: %d, %s and %c, each with
# an optional decimal field width and an optional precision ("." followed
# by digits or "*").  Any other character after '%' is output literally
# (which also handles "%%").  Every byte is emitted the moment it is
# produced, one write syscall each, with no buffering anywhere; it
# returns the number of bytes written, like libc printf.  Two deviations
# from libc: %d prints the full word-sized value (c4's "int"), where
# glibc's %d would truncate the argument to 32 bits; and the field width
# is honored for %s and %c only, not %d (c4 never uses a width with %d,
# and honoring it would require knowing the digit count before emitting).
#
# c4's PRTF opcode passes printf at most a format and five values; the
# five possible value arguments (incoming arguments 2..6) are spilled to
# the global array pf_args so they can be indexed by pf_argi.
#
# memcmp uses signed byte loads (the virtual ISA has no unsigned ones):
# the sign of its result is meaningful only for bytes >= 128, and c4
# only ever tests the result against zero, on ASCII input.

.bss
.balign WORDSZ
pf_count:       .space WORDSZ        /* bytes written by current printf */
pf_args:        .space 5*WORDSZ      /* printf's spilled value arguments */
pf_char:        .space 1             /* the byte pf_putc hands to write() */
pf_buf:         .space 1             /* one-byte home for %c and literals */

.text

# ---- printf ----------------------------------------------------------

# pf_putc(c): write the single byte c to fd 1 and count it.
pf_putc:
        vENTER 1
pc_c = 1
        vSTARG 1, pc_c
        vLDBL pc_c
        vLDAS pf_char
        vSTBA_B
        vARGI 1, 1                   /* fd 1 (stdout) */
        vARGS 2, pf_char
        vARGI 3, 1
        vCALL write
        vRES
        vJLE_AI 0, .Lrt_pc_done      /* error: drop the byte silently */
        vINCGI pf_count, 1
.Lrt_pc_done:
        vRET

# pf_putu(n): print n as unsigned decimal.  Recursing on n/10 before
# emitting the digit n%10 yields the digits most significant first,
# so each one can be written the moment it is produced.
pf_putu:
        vENTER 3
pu_n = 1
pu_ten = 2
pu_dig = 3
        vSTARG 1, pu_n
        vSTIL pu_ten, 10
        vLDAL pu_n
        vMODL pu_ten
        vSTCL pu_dig                 /* the last digit */
        vLDAL pu_n
        vDIVL pu_ten
        vSTAL pu_n                   /* n = n / 10 */
        vJZA .Lrt_pu_digit
        vARGL 1, pu_n
        vCALL pf_putu
        vRES
.Lrt_pu_digit:
        vLDAL pu_dig
        vADDAI 48                    /* '0' */
        vARGA 1
        vCALL pf_putc
        vRES
        vRET

# printf(fmt, ...) -> bytes written.
.globl printf
printf:
        vENTER 7
pf_fmt = 1
pf_argi = 2
pf_width = 3
pf_prec = 4
pf_item = 5
pf_len = 6
pf_dig = 7
        vSTARG 1, pf_fmt
        vSTARG 2, pf_item            /* borrow slots to spill the value */
        vSTARG 3, pf_len             /* arguments into pf_args (all get */
        vSTARG 4, pf_width           /* reinitialized before use below) */
        vSTARG 5, pf_prec
        vSTARG 6, pf_argi
        vLDAL pf_item
        vSTAG pf_args
        vLDAL pf_len
        vSTAG pf_args+WORDSZ
        vLDAL pf_width
        vSTAG pf_args+2*WORDSZ
        vLDAL pf_prec
        vSTAG pf_args+3*WORDSZ
        vLDAL pf_argi
        vSTAG pf_args+4*WORDSZ
        vSTIG pf_count, 0
        vSTIL pf_argi, 0

.Lrt_pf_loop:
        # emit literal characters until the next '%' or the final NUL
        vLDAL pf_fmt
        vLDSBA
        vJZA .Lrt_pf_end
        vINCLI pf_fmt, 1
        vJEQ_AI 37, .Lrt_pf_percent  /* '%' */
        vARGA 1
        vCALL pf_putc
        vRES
        vJMP .Lrt_pf_loop

        # optional decimal field width
.Lrt_pf_percent:
        vSTIL pf_width, 0
        vSTIL pf_prec, -1
.Lrt_pf_width:
        vLDAL pf_fmt
        vLDSBA
        vJLT_AI 48, .Lrt_pf_width_done  /* '0' */
        vJGT_AI 57, .Lrt_pf_width_done  /* '9' */
        vSUBAI 48                    /* '0' */
        vSTAL pf_dig
        vLDAL pf_width
        vMULAI 10
        vADDAL pf_dig
        vSTAL pf_width
        vINCLI pf_fmt, 1
        vJMP .Lrt_pf_width
.Lrt_pf_width_done:

        # optional precision: '.' then digits or '*'
        vJNE_AI 46, .Lrt_pf_conv     /* '.' */
        vINCLI pf_fmt, 1
        vSTIL pf_prec, 0
        vLDAL pf_fmt
        vLDSBA
        vJNE_AI 42, .Lrt_pf_prec     /* '*' */
        vLDAL pf_argi                /* '*': precision is the next arg */
        vMULAW
        vADDAS pf_args
        vDEREFA
        vSTAL pf_prec
        vINCLI pf_argi, 1
        vINCLI pf_fmt, 1
        vJMP .Lrt_pf_conv
.Lrt_pf_prec:
        vLDAL pf_fmt
        vLDSBA
        vJLT_AI 48, .Lrt_pf_conv     /* '0' */
        vJGT_AI 57, .Lrt_pf_conv     /* '9' */
        vSUBAI 48                    /* '0' */
        vSTAL pf_dig
        vLDAL pf_prec
        vMULAI 10
        vADDAL pf_dig
        vSTAL pf_prec
        vINCLI pf_fmt, 1
        vJMP .Lrt_pf_prec

        # conversion character
.Lrt_pf_conv:
        vLDAL pf_fmt
        vLDSBA
        vINCLI pf_fmt, 1
        vJZA .Lrt_pf_end             /* format ends with a lone '%' */
        vJEQ_AI 100, .Lrt_pf_d       /* 'd' */
        vJEQ_AI 115, .Lrt_pf_s       /* 's' */
        vJEQ_AI 99, .Lrt_pf_c        /* 'c' */
        vSTAL pf_dig                 /* anything else: emit it literally */
        vLDBL pf_dig
        vLDAS pf_buf
        vSTBA_B
        vSTAL pf_item
        vSTIL pf_len, 1
        vJMP .Lrt_pf_emit

.Lrt_pf_d:                           /* signed decimal (width ignored) */
        vLDAL pf_argi
        vMULAW
        vADDAS pf_args
        vDEREFA
        vINCLI pf_argi, 1
        vSTAL pf_item
        vJGE_AI 0, .Lrt_pf_d_mag
        vARGI 1, 45                  /* '-' */
        vCALL pf_putc
        vRES
        vLDBL pf_item
        vNEGB
        vSTBL pf_item
.Lrt_pf_d_mag:
        vARGL 1, pf_item
        vCALL pf_putu
        vRES
        vJMP .Lrt_pf_loop

.Lrt_pf_s:                           /* string, up to NUL or precision */
        vLDAL pf_argi
        vMULAW
        vADDAS pf_args
        vDEREFA
        vINCLI pf_argi, 1
        vSTAL pf_item
        vSTIL pf_len, 0
.Lrt_pf_s_len:
        vLDAL pf_len
        vJEQ_AL pf_prec, .Lrt_pf_s_done  /* never true when prec is -1 */
        vLDAL pf_item
        vADDAL pf_len
        vLDSBA
        vJZA .Lrt_pf_s_done
        vINCLI pf_len, 1
        vJMP .Lrt_pf_s_len
.Lrt_pf_s_done:
        vJMP .Lrt_pf_emit

.Lrt_pf_c:                           /* single character */
        vLDAL pf_argi
        vMULAW
        vADDAS pf_args
        vDEREFA
        vINCLI pf_argi, 1
        vSTAL pf_dig
        vLDBL pf_dig
        vLDAS pf_buf
        vSTBA_B
        vSTAL pf_item
        vSTIL pf_len, 1

.Lrt_pf_emit:                        /* space-pad to the field width, */
        vLDAL pf_len                 /* then emit the conversion itself */
        vSUBLA pf_width              /* width slot now holds pad count */
.Lrt_pf_pad:
        vJLE_LI pf_width, 0, .Lrt_pf_put
        vARGI 1, 32                  /* ' ' */
        vCALL pf_putc
        vRES
        vDECLI pf_width, 1
        vJMP .Lrt_pf_pad
.Lrt_pf_put:
        vJEQ_LI pf_len, 0, .Lrt_pf_loop
        vLDAL pf_item
        vLDSBA
        vARGA 1
        vINCLI pf_item, 1
        vDECLI pf_len, 1
        vCALL pf_putc
        vRES
        vJMP .Lrt_pf_put

.Lrt_pf_end:
        vLDAG pf_count
        vRET

# ---- memory ----------------------------------------------------------

.globl memset
memset:                              /* memset(s, c, n) -> s */
        vENTER 4
ms_s = 1
ms_c = 2
ms_n = 3
ms_p = 4
        vSTARG 1, ms_s
        vSTARG 2, ms_c
        vSTARG 3, ms_n
        vLDAL ms_s
        vSTAL ms_p                   /* walking copy; ms_s stays = s */
.Lrt_ms_loop:
        vJEQ_LI ms_n, 0, .Lrt_ms_done
        vLDBL ms_c
        vLDAL ms_p
        vSTBA_B                      /* byte[p] = (char)c */
        vINCLI ms_p, 1
        vDECLI ms_n, 1
        vJMP .Lrt_ms_loop
.Lrt_ms_done:
        vLDAL ms_s
        vRET

.globl memcmp
memcmp:                              /* memcmp(s1, s2, n) -> <0, 0, >0 */
        vENTER 4
mc_s1 = 1
mc_s2 = 2
mc_n = 3
mc_d = 4
        vSTARG 1, mc_s1
        vSTARG 2, mc_s2
        vSTARG 3, mc_n
.Lrt_mc_loop:
        vJEQ_LI mc_n, 0, .Lrt_mc_zero
        vLDAL mc_s2
        vLDSBA
        vSTAL mc_d                   /* d = *s2 */
        vLDAL mc_s1
        vLDSBA                       /* A = *s1 */
        vJNE_AL mc_d, .Lrt_mc_diff
        vINCLI mc_s1, 1
        vINCLI mc_s2, 1
        vDECLI mc_n, 1
        vJMP .Lrt_mc_loop
.Lrt_mc_diff:
        vSUBLA mc_d                  /* d = *s2 - *s1 ... */
        vLDBL mc_d
        vNEGB
        vSTBL mc_d                   /* ... so -d = *s1 - *s2 */
        vLDAL mc_d
        vRET
.Lrt_mc_zero:
        vRETI 0

.globl free
# free(ptr): no-op (mappings are reclaimed by the kernel on exit)
free:
        vENTER 1
        vRETI 0

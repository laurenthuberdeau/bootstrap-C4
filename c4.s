# If assembled directly, defer to the x86-64 macro definitions;
# arch/*.s files define the virtual ISA (and WORDSZ) and re-include c4.s.
.ifdef WORDSZ
# c4.s - C in four functions (assembly version)
#
# A line-by-line translation of c4.c (by Robert Swierczek) into
# architecture-agnostic assembly, intended to be reviewable against the
# original C source.
#
# Every line of c4.c appears exactly once, in order, as a comment
# prefixed with "#:", directly above the instruction sequence that
# implements it. The original C source can therefore be recovered,
# byte for byte, with:
#
#     sed -n 's/^#://p' c4.s > c4.c
#
# or with extract.c, which does the same extraction and is written in
# the C4 subset of C so that c4 itself can run it (c4 appends an
# "exit(0) cycle = N" line to every run, which the sed '$d' strips):
#
#     ./c4 extract.c c4.s | sed '$d' > c4.c
#
# Comments starting with plain "#" are annotations that are not part
# of the C source.
#
# This file contains no machine instructions. Every C statement is
# implemented with macros from a small virtual instruction set (the
# "v" prefix), defined per architecture in arch/*.s. Porting c4 to a
# new architecture means implementing those macros in one new file;
# this body is shared unchanged.
#
# Build (from the repository root; the binaries are freestanding, so
# no libc is needed for any target):
#     gcc -nostdlib -static -no-pie c4.s -o c4              # native x86-64
#     gcc -nostdlib -static -no-pie -I. arch/x86_64.s -o c4 # same, explicit
#     gcc -m32 -nostdlib -static -no-pie -I. arch/i386.s -o c4-i386
#     aarch64-unknown-linux-gnu-gcc -nostdlib -static -I. arch/aarch64.s -o c4-aarch64
#     riscv64-unknown-linux-gnu-gcc -nostdlib -static -I. arch/riscv64.s -o c4-riscv64
#
# Conventions (chosen for reviewability and portability, not speed):
#   - The virtual machine has two registers, A (accumulator, also the
#     call-result register) and B; a third, C, appears only in shift,
#     division and remainder idioms. No value is ever kept in a
#     register across a call: every C statement starts by loading its
#     operands from memory and ends by storing its result to memory.
#   - Every C variable lives in memory: globals are labels in .bss,
#     locals are frame slots named by word-index equates (e.g.
#     "pp = 1" is the first local slot; the macros scale by WORDSZ).
#   - WORDSZ (defined by the arch file) is the size of the c4 "int"
#     and of pointers: 8 on 64-bit targets, where behaviour is exactly
#     that of c4.c ("#define int long long"); 4 on i386, where the
#     program behaves as c4.c with a 32-bit int (the one documented
#     semantic deviation from the embedded source).
#   - The binary is freestanding: the functions c4.c takes from libc
#     are provided by a two-part "freestanding runtime". The logic
#     (printf, memset, memcmp, free) lives once in runtime.s, written
#     in the same virtual ISA as this body; only the syscall glue
#     (_start, exit, open, read, close, write, malloc) is per-arch,
#     implemented in each arch file with direct Linux syscalls. The
#     body calls all of them through the vARG*/vCALL* macros; each
#     arch file maps those onto its C calling convention. printf
#     supports only what c4 needs: %d, %s and %c, with an optional
#     width and "." precision (digits or *).
#   - Character constants appear as decimal numbers with the character
#     in a comment (e.g. "vJNE_GI tk, 10, ..." for '\n').
#   - Some words are reserved by GAS on one target or another (the
#     Intel-syntax operators and, or, xor, eq, ne, lt, gt, le, ge,
#     shl, shr, mod; register names like si). Identifiers from c4.c
#     that collide get a trailing underscore: the global "le" is
#     "le_", the tokens Or..Mod are Or_..Mod_, and the opcodes OR..MOD
#     and SI are OR_..MOD_ and SI_. The C source quoted in the
#     comments keeps the original names.


#:// c4.c - C in four functions
#:
#:// char, int, and pointer types
#:// if, while, return, and expression statements
#:// just enough features to allow self-compilation and a bit more
#:
#:// Written by Robert Swierczek
#:
#:#include <stdio.h>
#:#include <stdlib.h>
#:#include <memory.h>
#:#include <unistd.h>
#:#include <fcntl.h>
#:#define int long long
#:

# global variables (one 8-byte cell each; "int" is long long)
.bss
.balign WORDSZ
#:char *p, *lp, // current position in source code
#:     *data;   // data/bss pointer
#:
p:      .space WORDSZ
lp:     .space WORDSZ
data:   .space WORDSZ
#:int *e, *le,  // current position in emitted code
#:    *id,      // currently parsed identifier
#:    *sym,     // symbol table (simple list of identifiers)
#:    tk,       // current token
#:    ival,     // current token value
#:    ty,       // current expression type
#:    loc,      // local variable offset
#:    line,     // current line number
#:    src,      // print source and assembly flag
#:    debug;    // print executed instructions
#:
e:      .space WORDSZ
le_:    .space WORDSZ
id:     .space WORDSZ
sym:    .space WORDSZ
tk:     .space WORDSZ
ival:   .space WORDSZ
ty:     .space WORDSZ
loc:    .space WORDSZ
line:   .space WORDSZ
src:    .space WORDSZ
debug:  .space WORDSZ

#:// tokens and classes (operators last and in precedence order)
#:enum {
#:  Num = 128, Fun, Sys, Glo, Loc, Id,
#:  Char, Else, Enum, If, Int, Return, Sizeof, While,
#:  Assign, Cond, Lor, Lan, Or, Xor, And, Eq, Ne, Lt, Gt, Le, Ge, Shl, Shr, Add, Sub, Mul, Div, Mod, Inc, Dec, Brak
#:};
#:
Num = 128
Fun = 129
Sys = 130
Glo = 131
Loc = 132
Id  = 133
Char   = 134
Else   = 135
Enum   = 136
If     = 137
Int    = 138
Return = 139
Sizeof = 140
While  = 141
Assign = 142
Cond   = 143
Lor    = 144
Lan    = 145
Or_     = 146
Xor_    = 147
And_    = 148
Eq_     = 149
Ne_     = 150
Lt_     = 151
Gt_     = 152
Le_     = 153
Ge_     = 154
Shl_    = 155
Shr_    = 156
Add    = 157
Sub    = 158
Mul    = 159
Div    = 160
Mod_    = 161
Inc    = 162
Dec    = 163
Brak   = 164

#:// opcodes
#:enum { LEA ,IMM ,JMP ,JSR ,BZ  ,BNZ ,ENT ,ADJ ,LEV ,LI  ,LC  ,SI  ,SC  ,PSH ,
#:       OR  ,XOR ,AND ,EQ  ,NE  ,LT  ,GT  ,LE  ,GE  ,SHL ,SHR ,ADD ,SUB ,MUL ,DIV ,MOD ,
#:       OPEN,READ,CLOS,PRTF,MALC,FREE,MSET,MCMP,EXIT };
#:
LEA  = 0
IMM  = 1
JMP  = 2
JSR  = 3
BZ   = 4
BNZ  = 5
ENT  = 6
ADJ  = 7
LEV  = 8
LI   = 9
LC   = 10
SI_   = 11
SC   = 12
PSH  = 13
OR_   = 14
XOR_  = 15
AND_  = 16
EQ_   = 17
NE_   = 18
LT_   = 19
GT_   = 20
LE_   = 21
GE_   = 22
SHL_  = 23
SHR_  = 24
ADD  = 25
SUB  = 26
MUL  = 27
DIV  = 28
MOD_  = 29
OPEN = 30
READ = 31
CLOS = 32
PRTF = 33
MALC = 34
FREE = 35
MSET = 36
MCMP = 37
EXIT = 38

#:// types
#:enum { CHAR, INT, PTR };
#:
CHAR = 0
INT  = 1
PTR  = 2

#:// identifier offsets (since we can't create an ident struct)
#:enum { Tk, Hash, Name, Class, Type, Val, HClass, HType, HVal, Idsz };
#:
Tk     = 0
Hash   = 1
Name   = 2
Class  = 3
Type   = 4
Val    = 5
HClass = 6
HType  = 7
HVal   = 8
Idsz   = 9

# string constants
.data
ops:            .ascii "LEA ,IMM ,JMP ,JSR ,BZ  ,BNZ ,ENT ,ADJ ,LEV ,LI  ,LC  ,SI  ,SC  ,PSH ,"
                .ascii "OR  ,XOR ,AND ,EQ  ,NE  ,LT  ,GT  ,LE  ,GE  ,SHL ,SHR ,ADD ,SUB ,MUL ,DIV ,MOD ,"
                .asciz "OPEN,READ,CLOS,PRTF,MALC,FREE,MSET,MCMP,EXIT,"
keywords:       .ascii "char else enum if int return sizeof while "
                .asciz "open read close printf malloc free memset memcmp exit void main"

fmt_src:        .asciz "%d: %.*s"
fmt_ins:        .asciz "%8.4s"
fmt_opval:      .asciz " %d\n"
fmt_nl:         .asciz "\n"
fmt_debug:      .asciz "%d> %.4s"

msg_eof:        .asciz "%d: unexpected eof in expression\n"
msg_op_szof:    .asciz "%d: open paren expected in sizeof\n"
msg_cp_szof:    .asciz "%d: close paren expected in sizeof\n"
msg_bad_call:   .asciz "%d: bad function call\n"
msg_undef_var:  .asciz "%d: undefined variable\n"
msg_bad_cast:   .asciz "%d: bad cast\n"
msg_cp_exp:     .asciz "%d: close paren expected\n"
msg_bad_deref:  .asciz "%d: bad dereference\n"
msg_bad_addr:   .asciz "%d: bad address-of\n"
msg_lval_pre:   .asciz "%d: bad lvalue in pre-increment\n"
msg_bad_expr:   .asciz "%d: bad expression\n"
msg_lval_asgn:  .asciz "%d: bad lvalue in assignment\n"
msg_cond_colon: .asciz "%d: conditional missing colon\n"
msg_lval_post:  .asciz "%d: bad lvalue in post-increment\n"
msg_cb_exp:     .asciz "%d: close bracket expected\n"
msg_ptr_exp:    .asciz "%d: pointer type expected\n"
msg_comp_err:   .asciz "%d: compiler error tk=%d\n"
msg_op_exp:     .asciz "%d: open paren expected\n"
msg_semi_exp:   .asciz "%d: semicolon expected\n"

msg_usage:      .asciz "usage: c4 [-s] [-d] file ...\n"
msg_open:       .asciz "could not open(%s)\n"
msg_m_sym:      .asciz "could not malloc(%d) symbol area\n"
msg_m_text:     .asciz "could not malloc(%d) text area\n"
msg_m_data:     .asciz "could not malloc(%d) data area\n"
msg_m_stack:    .asciz "could not malloc(%d) stack area\n"
msg_m_src:      .asciz "could not malloc(%d) source area\n"
msg_read:       .asciz "read() returned %d\n"
msg_enum_id:    .asciz "%d: bad enum identifier %d\n"
msg_enum_init:  .asciz "%d: bad enum initializer\n"
msg_bad_glo:    .asciz "%d: bad global declaration\n"
msg_dup_glo:    .asciz "%d: duplicate global definition\n"
msg_bad_param:  .asciz "%d: bad parameter declaration\n"
msg_dup_param:  .asciz "%d: duplicate parameter definition\n"
msg_bad_func:   .asciz "%d: bad function definition\n"
msg_bad_loc:    .asciz "%d: bad local declaration\n"
msg_dup_loc:    .asciz "%d: duplicate local definition\n"
msg_no_main:    .asciz "main() not defined\n"
msg_exit:       .asciz "exit(%d) cycle = %d\n"
msg_unknown:    .asciz "unknown instruction = %d! cycle = %d\n"

.text

# ----------------------------------------------------------------------
#:void next()
#:{
#:  char *pp;
# ----------------------------------------------------------------------
.globl next
next:
        vENTER 2
pp = 1                      /* char *pp; */

#:
#:  while (tk = *p) {
.Lnx_while:
        vLDAG p
        vLDSBA
        vSTAG tk
        vJZA .Lnx_end
#:    ++p;
        vINCGI p, 1
#:    if (tk == '\n') {
        vJNE_GI tk, 10, .Lnx_not_nl  /* '\n' */
#:      if (src) {
        vJEQ_GI src, 0, .Lnx_nl_done
#:        printf("%d: %.*s", line, p - lp, lp);
        vARGS 1, fmt_src
        vARGG 2, line
        vARGG 3, p
        vARGSUBG 3, lp
        vARGG 4, lp
        vCALLV printf
        vRES
#:        lp = p;
        vLDAG p
        vSTAG lp
#:        while (le < e) {
.Lnx_src_while:
        vLDAG le_
        vJGE_AG e, .Lnx_nl_done
#:          printf("%8.4s", &"LEA ,IMM ,JMP ,JSR ,BZ  ,BNZ ,ENT ,ADJ ,LEV ,LI  ,LC  ,SI  ,SC  ,PSH ,"
#:                           "OR  ,XOR ,AND ,EQ  ,NE  ,LT  ,GT  ,LE  ,GE  ,SHL ,SHR ,ADD ,SUB ,MUL ,DIV ,MOD ,"
#:                           "OPEN,READ,CLOS,PRTF,MALC,FREE,MSET,MCMP,EXIT,"[*++le * 5]);
        vINCGW le_, 1
        vLDAG le_
        vDEREFA
        vMULAI 5
        vADDAS ops
        vARGA 2
        vARGS 1, fmt_ins
        vCALLV printf
        vRES
#:          if (*le <= ADJ) printf(" %d\n", *++le); else printf("\n");
        vLDAG le_
        vDEREFA
        vJGT_AI ADJ, .Lnx_src_nl
        vINCGW le_, 1
        vLDAG le_
        vARGMA 2, 0
        vARGS 1, fmt_opval
        vCALLV printf
        vRES
        vJMP .Lnx_src_while
.Lnx_src_nl:
        vARGS 1, fmt_nl
        vCALLV printf
        vRES
        vJMP .Lnx_src_while
#:        }
#:      }
#:      ++line;
.Lnx_nl_done:
        vINCGI line, 1
        vJMP .Lnx_while
#:    }
#:    else if (tk == '#') {
.Lnx_not_nl:
        vJNE_GI tk, 35, .Lnx_not_hash  /* '#' */
#:      while (*p != 0 && *p != '\n') ++p;
.Lnx_hash_while:
        vLDAG p
        vLDSBA
        vJZA .Lnx_while
        vJEQ_AI 10, .Lnx_while  /* '\n' */
        vINCGI p, 1
        vJMP .Lnx_hash_while
#:    }
#:    else if ((tk >= 'a' && tk <= 'z') || (tk >= 'A' && tk <= 'Z') || tk == '_') {
.Lnx_not_hash:
        vLDAG tk
        vJLT_AI 97, .Lnx_id_chk_upper  /* 'a' */
        vJLE_AI 122, .Lnx_ident  /* 'z' */
.Lnx_id_chk_upper:
        vJLT_AI 65, .Lnx_id_chk_under  /* 'A' */
        vJLE_AI 90, .Lnx_ident  /* 'Z' */
.Lnx_id_chk_under:
        vJNE_AI 95, .Lnx_not_ident  /* '_' */
.Lnx_ident:
#:      pp = p - 1;
        vLDAG p
        vSUBAI 1
        vSTAL pp
#:      while ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '_')
.Lnx_id_while:
        vLDAG p
        vLDSBA
        vJLT_AI 97, .Lnx_idw_upper  /* 'a' */
        vJLE_AI 122, .Lnx_id_body  /* 'z' */
.Lnx_idw_upper:
        vJLT_AI 65, .Lnx_idw_digit  /* 'A' */
        vJLE_AI 90, .Lnx_id_body  /* 'Z' */
.Lnx_idw_digit:
        vJLT_AI 48, .Lnx_idw_under  /* '0' */
        vJLE_AI 57, .Lnx_id_body  /* '9' */
.Lnx_idw_under:
        vJNE_AI 95, .Lnx_id_hash  /* '_' */
.Lnx_id_body:
#:        tk = tk * 147 + *p++;
        vLDAG tk
        vMULAI 147
        vLDBG p
        vLDSBB
        vADDAB
        vSTAG tk
        vINCGI p, 1
        vJMP .Lnx_id_while
.Lnx_id_hash:
#:      tk = (tk << 6) + (p - pp);
        vLDAG tk
        vSHLAI 6
        vLDBG p
        vSUBBL pp
        vADDAB
        vSTAG tk
#:      id = sym;
        vLDAG sym
        vSTAG id
#:      while (id[Tk]) {
.Lnx_id_lookup:
        vLDAG id
        vJEQ_FI Tk, 0, .Lnx_id_new
#:        if (tk == id[Hash] && !memcmp((char *)id[Name], pp, p - pp)) { tk = id[Tk]; return; }
        vLDAG tk
        vLDBG id
        vJNE_A_BF Hash, .Lnx_id_next
        vLDBG id
        vARG_BF 1, Name
        vARGL 2, pp
        vARGG 3, p
        vARGSUBL 3, pp
        vCALL memcmp
        vRES
        vJNZRES .Lnx_id_next
        vLDBG id
        vLDA_BF Tk
        vSTAG tk
        vRET
#:        id = id + Idsz;
.Lnx_id_next:
        vINCGW id, Idsz
        vJMP .Lnx_id_lookup
#:      }
#:      id[Name] = (int)pp;
#:      id[Hash] = tk;
#:      tk = id[Tk] = Id;
#:      return;
.Lnx_id_new:
        vLDAG id
        vLDBL pp
        vSTF_B Name
        vLDBG tk
        vSTF_B Hash
        vSTF_I Tk, Id
        vSTIG tk, Id
        vRET
#:    }
#:    else if (tk >= '0' && tk <= '9') {
.Lnx_not_ident:
        vLDAG tk
        vJLT_AI 48, .Lnx_not_num  /* '0' */
        vJGT_AI 57, .Lnx_not_num  /* '9' */
#:      if (ival = tk - '0') { while (*p >= '0' && *p <= '9') ival = ival * 10 + *p++ - '0'; }
        vSUBAI 48  /* '0' */
        vSTAG ival
        vJZA .Lnx_num_hexoct
.Lnx_dec_while:
        vLDAG p
        vLDSBA
        vJLT_AI 48, .Lnx_num_done  /* '0' */
        vJGT_AI 57, .Lnx_num_done  /* '9' */
        vLDBG ival
        vMULBI 10
        vADDBA
        vSUBBI 48  /* '0' */
        vSTBG ival
        vINCGI p, 1
        vJMP .Lnx_dec_while
#:      else if (*p == 'x' || *p == 'X') {
.Lnx_num_hexoct:
        vLDAG p
        vLDSBA
        vJEQ_AI 120, .Lnx_hex  /* 'x' */
        vJEQ_AI 88, .Lnx_hex  /* 'X' */
        vJMP .Lnx_oct
#:        while ((tk = *++p) && ((tk >= '0' && tk <= '9') || (tk >= 'a' && tk <= 'f') || (tk >= 'A' && tk <= 'F')))
.Lnx_hex:
        vINCGI p, 1
        vLDAG p
        vLDSBA
        vSTAG tk
        vJZA .Lnx_num_done
        vJLT_AI 48, .Lnx_hex_lower  /* '0' */
        vJLE_AI 57, .Lnx_hex_digit  /* '9' */
.Lnx_hex_lower:
        vJLT_AI 97, .Lnx_hex_upper  /* 'a' */
        vJLE_AI 102, .Lnx_hex_digit  /* 'f' */
.Lnx_hex_upper:
        vJLT_AI 65, .Lnx_num_done  /* 'A' */
        vJGT_AI 70, .Lnx_num_done  /* 'F' */
#:          ival = ival * 16 + (tk & 15) + (tk >= 'A' ? 9 : 0);
.Lnx_hex_digit:
        vLDAG ival
        vMULAI 16
        vLDBG tk
        vANDBI 15
        vADDAB
        vJLT_GI tk, 65, .Lnx_hex_no9  /* 'A' */
        vADDAI 9
.Lnx_hex_no9:
        vSTAG ival
        vJMP .Lnx_hex
#:      }
#:      else { while (*p >= '0' && *p <= '7') ival = ival * 8 + *p++ - '0'; }
.Lnx_oct:
        vLDAG p
        vLDSBA
        vJLT_AI 48, .Lnx_num_done  /* '0' */
        vJGT_AI 55, .Lnx_num_done  /* '7' */
        vLDBG ival
        vMULBI 8
        vADDBA
        vSUBBI 48  /* '0' */
        vSTBG ival
        vINCGI p, 1
        vJMP .Lnx_oct
#:      tk = Num;
#:      return;
.Lnx_num_done:
        vSTIG tk, Num
        vRET
#:    }
#:    else if (tk == '/') {
.Lnx_not_num:
        vJNE_GI tk, 47, .Lnx_not_div  /* '/' */
#:      if (*p == '/') {
        vLDAG p
        vLDSBA
        vJNE_AI 47, .Lnx_div_op  /* '/' */
#:        ++p;
        vINCGI p, 1
#:        while (*p != 0 && *p != '\n') ++p;
.Lnx_cmt_while:
        vLDAG p
        vLDSBA
        vJZA .Lnx_while
        vJEQ_AI 10, .Lnx_while  /* '\n' */
        vINCGI p, 1
        vJMP .Lnx_cmt_while
#:      }
#:      else {
#:        tk = Div;
#:        return;
#:      }
.Lnx_div_op:
        vSTIG tk, Div
        vRET
#:    }
#:    else if (tk == '\'' || tk == '"') {
.Lnx_not_div:
        vJEQ_GI tk, 39, .Lnx_quote  /* '\'' */
        vJNE_GI tk, 34, .Lnx_not_quote  /* '"' */
.Lnx_quote:
#:      pp = data;
        vLDAG data
        vSTAL pp
#:      while (*p != 0 && *p != tk) {
.Lnx_str_while:
        vLDAG p
        vLDSBA
        vJZA .Lnx_str_done
        vJEQ_AG tk, .Lnx_str_done
#:        if ((ival = *p++) == '\\') {
        vSTAG ival
        vINCGI p, 1
        vJNE_AI 92, .Lnx_str_store  /* '\\' */
#:          if ((ival = *p++) == 'n') ival = '\n';
        vLDAG p
        vLDSBA
        vSTAG ival
        vINCGI p, 1
        vJNE_AI 110, .Lnx_str_store  /* 'n' */
        vSTIG ival, 10  /* '\n' */
#:        }
#:        if (tk == '"') *data++ = ival;
.Lnx_str_store:
        vJNE_GI tk, 34, .Lnx_str_while  /* '"' */
        vLDAG data
        vLDBG ival
        vSTBA_B
        vINCGI data, 1
        vJMP .Lnx_str_while
#:      }
#:      ++p;
#:      if (tk == '"') ival = (int)pp; else tk = Num;
#:      return;
.Lnx_str_done:
        vINCGI p, 1
        vJNE_GI tk, 34, .Lnx_char_const  /* '"' */
        vLDAL pp
        vSTAG ival
        vRET
.Lnx_char_const:
        vSTIG tk, Num
        vRET
#:    }
#:    else if (tk == '=') { if (*p == '=') { ++p; tk = Eq; } else tk = Assign; return; }
.Lnx_not_quote:
        vJNE_GI tk, 61, .Lnx_not_assign  /* '=' */
        vLDAG p
        vLDSBA
        vJNE_AI 61, .Lnx_op_assign  /* '=' */
        vINCGI p, 1
        vSTIG tk, Eq_
        vRET
.Lnx_op_assign:
        vSTIG tk, Assign
        vRET
#:    else if (tk == '+') { if (*p == '+') { ++p; tk = Inc; } else tk = Add; return; }
.Lnx_not_assign:
        vJNE_GI tk, 43, .Lnx_not_add  /* '+' */
        vLDAG p
        vLDSBA
        vJNE_AI 43, .Lnx_op_add  /* '+' */
        vINCGI p, 1
        vSTIG tk, Inc
        vRET
.Lnx_op_add:
        vSTIG tk, Add
        vRET
#:    else if (tk == '-') { if (*p == '-') { ++p; tk = Dec; } else tk = Sub; return; }
.Lnx_not_add:
        vJNE_GI tk, 45, .Lnx_not_sub  /* '-' */
        vLDAG p
        vLDSBA
        vJNE_AI 45, .Lnx_op_sub  /* '-' */
        vINCGI p, 1
        vSTIG tk, Dec
        vRET
.Lnx_op_sub:
        vSTIG tk, Sub
        vRET
#:    else if (tk == '!') { if (*p == '=') { ++p; tk = Ne; } return; }
.Lnx_not_sub:
        vJNE_GI tk, 33, .Lnx_not_bang  /* '!' */
        vLDAG p
        vLDSBA
        vJNE_AI 61, .Lnx_bang_ret  /* '=' */
        vINCGI p, 1
        vSTIG tk, Ne_
.Lnx_bang_ret:
        vRET
#:    else if (tk == '<') { if (*p == '=') { ++p; tk = Le; } else if (*p == '<') { ++p; tk = Shl; } else tk = Lt; return; }
.Lnx_not_bang:
        vJNE_GI tk, 60, .Lnx_not_lt  /* '<' */
        vLDAG p
        vLDSBA
        vJNE_AI 61, .Lnx_lt_shl  /* '=' */
        vINCGI p, 1
        vSTIG tk, Le_
        vRET
.Lnx_lt_shl:
        vJNE_AI 60, .Lnx_op_lt  /* '<' */
        vINCGI p, 1
        vSTIG tk, Shl_
        vRET
.Lnx_op_lt:
        vSTIG tk, Lt_
        vRET
#:    else if (tk == '>') { if (*p == '=') { ++p; tk = Ge; } else if (*p == '>') { ++p; tk = Shr; } else tk = Gt; return; }
.Lnx_not_lt:
        vJNE_GI tk, 62, .Lnx_not_gt  /* '>' */
        vLDAG p
        vLDSBA
        vJNE_AI 61, .Lnx_gt_shr  /* '=' */
        vINCGI p, 1
        vSTIG tk, Ge_
        vRET
.Lnx_gt_shr:
        vJNE_AI 62, .Lnx_op_gt  /* '>' */
        vINCGI p, 1
        vSTIG tk, Shr_
        vRET
.Lnx_op_gt:
        vSTIG tk, Gt_
        vRET
#:    else if (tk == '|') { if (*p == '|') { ++p; tk = Lor; } else tk = Or; return; }
.Lnx_not_gt:
        vJNE_GI tk, 124, .Lnx_not_or  /* '|' */
        vLDAG p
        vLDSBA
        vJNE_AI 124, .Lnx_op_or  /* '|' */
        vINCGI p, 1
        vSTIG tk, Lor
        vRET
.Lnx_op_or:
        vSTIG tk, Or_
        vRET
#:    else if (tk == '&') { if (*p == '&') { ++p; tk = Lan; } else tk = And; return; }
.Lnx_not_or:
        vJNE_GI tk, 38, .Lnx_not_and  /* '&' */
        vLDAG p
        vLDSBA
        vJNE_AI 38, .Lnx_op_and  /* '&' */
        vINCGI p, 1
        vSTIG tk, Lan
        vRET
.Lnx_op_and:
        vSTIG tk, And_
        vRET
#:    else if (tk == '^') { tk = Xor; return; }
.Lnx_not_and:
        vJNE_GI tk, 94, .Lnx_not_xor  /* '^' */
        vSTIG tk, Xor_
        vRET
#:    else if (tk == '%') { tk = Mod; return; }
.Lnx_not_xor:
        vJNE_GI tk, 37, .Lnx_not_mod  /* '%' */
        vSTIG tk, Mod_
        vRET
#:    else if (tk == '*') { tk = Mul; return; }
.Lnx_not_mod:
        vJNE_GI tk, 42, .Lnx_not_mul  /* '*' */
        vSTIG tk, Mul
        vRET
#:    else if (tk == '[') { tk = Brak; return; }
.Lnx_not_mul:
        vJNE_GI tk, 91, .Lnx_not_brak  /* '[' */
        vSTIG tk, Brak
        vRET
#:    else if (tk == '?') { tk = Cond; return; }
.Lnx_not_brak:
        vJNE_GI tk, 63, .Lnx_not_cond  /* '?' */
        vSTIG tk, Cond
        vRET
#:    else if (tk == '~' || tk == ';' || tk == '{' || tk == '}' || tk == '(' || tk == ')' || tk == ']' || tk == ',' || tk == ':') return;
.Lnx_not_cond:
        vLDAG tk
        vJEQ_AI 126, .Lnx_punct_ret  /* '~' */
        vJEQ_AI 59, .Lnx_punct_ret  /* ';' */
        vJEQ_AI 123, .Lnx_punct_ret  /* '{' */
        vJEQ_AI 125, .Lnx_punct_ret  /* '}' */
        vJEQ_AI 40, .Lnx_punct_ret  /* '(' */
        vJEQ_AI 41, .Lnx_punct_ret  /* ')' */
        vJEQ_AI 93, .Lnx_punct_ret  /* ']' */
        vJEQ_AI 44, .Lnx_punct_ret  /* ',' */
        vJNE_AI 58, .Lnx_while  /* ':' */
.Lnx_punct_ret:
        vRET
#:  }
#:}
.Lnx_end:
        vRET

# ----------------------------------------------------------------------
#:
#:void expr(int lev)
#:{
#:  int t, *d;
# ----------------------------------------------------------------------
.globl expr
expr:
        vENTER 4
lev = 1                      /* int lev; (argument) */
t = 2                      /* int t; */
d = 3                      /* int *d; */
        vSTARG 1, lev

#:
#:  if (!tk) { printf("%d: unexpected eof in expression\n", line); exit(-1); }
        vJNE_GI tk, 0, .Lex_num
        vARGS 1, msg_eof
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
#:  else if (tk == Num) { *++e = IMM; *++e = ival; next(); ty = INT; }
.Lex_num:
        vJNE_GI tk, Num, .Lex_str
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vLDBG ival
        vSTWA_B
        vCALL next
        vRES
        vSTIG ty, INT
        vJMP .Lex_climb
#:  else if (tk == '"') {
.Lex_str:
        vJNE_GI tk, 34, .Lex_sizeof  /* '"' */
#:    *++e = IMM; *++e = ival; next();
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vLDBG ival
        vSTWA_B
        vCALL next
        vRES
#:    while (tk == '"') next();
.Lex_str_while:
        vJNE_GI tk, 34, .Lex_str_align  /* '"' */
        vCALL next
        vRES
        vJMP .Lex_str_while
#:    data = (char *)((int)data + sizeof(int) & -sizeof(int)); ty = PTR;
.Lex_str_align:
        vLDAG data
        vADDAW 1
        vALIGNA
        vSTAG data
        vSTIG ty, PTR
        vJMP .Lex_climb
#:  }
#:  else if (tk == Sizeof) {
.Lex_sizeof:
        vJNE_GI tk, Sizeof, .Lex_id
#:    next(); if (tk == '(') next(); else { printf("%d: open paren expected in sizeof\n", line); exit(-1); }
        vCALL next
        vRES
        vJEQ_GI tk, 40, .Lex_szf_open  /* '(' */
        vARGS 1, msg_op_szof
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_szf_open:
        vCALL next
        vRES
#:    ty = INT; if (tk == Int) next(); else if (tk == Char) { next(); ty = CHAR; }
        vSTIG ty, INT
        vJNE_GI tk, Int, .Lex_szf_char
        vCALL next
        vRES
        vJMP .Lex_szf_mul
.Lex_szf_char:
        vJNE_GI tk, Char, .Lex_szf_mul
        vCALL next
        vRES
        vSTIG ty, CHAR
#:    while (tk == Mul) { next(); ty = ty + PTR; }
.Lex_szf_mul:
        vJNE_GI tk, Mul, .Lex_szf_close
        vCALL next
        vRES
        vINCGI ty, PTR
        vJMP .Lex_szf_mul
#:    if (tk == ')') next(); else { printf("%d: close paren expected in sizeof\n", line); exit(-1); }
.Lex_szf_close:
        vJEQ_GI tk, 41, .Lex_szf_emit  /* ')' */
        vARGS 1, msg_cp_szof
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_szf_emit:
        vCALL next
        vRES
#:    *++e = IMM; *++e = (ty == CHAR) ? sizeof(char) : sizeof(int);
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vLDBI WORDSZ  /* sizeof(int) */
        vJNE_GI ty, CHAR, .Lex_szf_store
        vLDBI 1  /* sizeof(char) */
.Lex_szf_store:
        vSTWA_B
#:    ty = INT;
        vSTIG ty, INT
        vJMP .Lex_climb
#:  }
#:  else if (tk == Id) {
.Lex_id:
        vJNE_GI tk, Id, .Lex_paren
#:    d = id; next();
        vLDAG id
        vSTAL d
        vCALL next
        vRES
#:    if (tk == '(') {
        vJNE_GI tk, 40, .Lex_id_num  /* '(' */
#:      next();
        vCALL next
        vRES
#:      t = 0;
        vSTIL t, 0
#:      while (tk != ')') { expr(Assign); *++e = PSH; ++t; if (tk == ',') next(); }
.Lex_call_args:
        vJEQ_GI tk, 41, .Lex_call_done  /* ')' */
        vARGI 1, Assign
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCLI t, 1
        vJNE_GI tk, 44, .Lex_call_args  /* ',' */
        vCALL next
        vRES
        vJMP .Lex_call_args
.Lex_call_done:
#:      next();
        vCALL next
        vRES
#:      if (d[Class] == Sys) *++e = d[Val];
        vLDAL d
        vJNE_FI Class, Sys, .Lex_call_fun
        vLDBF Val
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vJMP .Lex_call_adj
#:      else if (d[Class] == Fun) { *++e = JSR; *++e = d[Val]; }
.Lex_call_fun:
        vJNE_FI Class, Fun, .Lex_call_err
        vINCGW e, 1
        vLDAG e
        vSTWA_I JSR
        vLDBL d
        vLDB_BF Val
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vJMP .Lex_call_adj
#:      else { printf("%d: bad function call\n", line); exit(-1); }
.Lex_call_err:
        vARGS 1, msg_bad_call
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
#:      if (t) { *++e = ADJ; *++e = t; }
.Lex_call_adj:
        vJEQ_LI t, 0, .Lex_call_ty
        vINCGW e, 1
        vLDAG e
        vSTWA_I ADJ
        vLDBL t
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:      ty = d[Type];
.Lex_call_ty:
        vLDAL d
        vLDAF Type
        vSTAG ty
        vJMP .Lex_climb
#:    }
#:    else if (d[Class] == Num) { *++e = IMM; *++e = d[Val]; ty = INT; }
.Lex_id_num:
        vLDAL d
        vJNE_FI Class, Num, .Lex_id_var
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vLDBL d
        vLDB_BF Val
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else {
#:      if (d[Class] == Loc) { *++e = LEA; *++e = loc - d[Val]; }
.Lex_id_var:
        vLDAL d
        vJNE_FI Class, Loc, .Lex_id_glo
        vINCGW e, 1
        vLDAG e
        vSTWA_I LEA
        vLDAG loc
        vLDBL d
        vSUBA_BF Val
        vINCGW e, 1
        vLDBG e
        vSTWB_A
        vJMP .Lex_id_load
#:      else if (d[Class] == Glo) { *++e = IMM; *++e = d[Val]; }
.Lex_id_glo:
        vLDAL d
        vJNE_FI Class, Glo, .Lex_id_undef
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vLDBL d
        vLDB_BF Val
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vJMP .Lex_id_load
#:      else { printf("%d: undefined variable\n", line); exit(-1); }
.Lex_id_undef:
        vARGS 1, msg_undef_var
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
#:      *++e = ((ty = d[Type]) == CHAR) ? LC : LI;
.Lex_id_load:
        vLDAL d
        vLDAF Type
        vSTAG ty
        vLDBI LI
        vJNE_AI CHAR, .Lex_id_emit_load
        vLDBI LC
.Lex_id_emit_load:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vJMP .Lex_climb
#:    }
#:  }
#:  else if (tk == '(') {
.Lex_paren:
        vJNE_GI tk, 40, .Lex_deref  /* '(' */
#:    next();
        vCALL next
        vRES
#:    if (tk == Int || tk == Char) {
        vJEQ_GI tk, Int, .Lex_cast
        vJNE_GI tk, Char, .Lex_group
#:      t = (tk == Int) ? INT : CHAR; next();
.Lex_cast:
        vLDAI INT
        vJEQ_GI tk, Int, .Lex_cast_t
        vLDAI CHAR
.Lex_cast_t:
        vSTAL t
        vCALL next
        vRES
#:      while (tk == Mul) { next(); t = t + PTR; }
.Lex_cast_mul:
        vJNE_GI tk, Mul, .Lex_cast_close
        vCALL next
        vRES
        vINCLI t, PTR
        vJMP .Lex_cast_mul
#:      if (tk == ')') next(); else { printf("%d: bad cast\n", line); exit(-1); }
.Lex_cast_close:
        vJEQ_GI tk, 41, .Lex_cast_ok  /* ')' */
        vARGS 1, msg_bad_cast
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_cast_ok:
        vCALL next
        vRES
#:      expr(Inc);
        vARGI 1, Inc
        vCALL expr
        vRES
#:      ty = t;
        vLDAL t
        vSTAG ty
        vJMP .Lex_climb
#:    }
#:    else {
#:      expr(Assign);
.Lex_group:
        vARGI 1, Assign
        vCALL expr
        vRES
#:      if (tk == ')') next(); else { printf("%d: close paren expected\n", line); exit(-1); }
        vJEQ_GI tk, 41, .Lex_group_ok  /* ')' */
        vARGS 1, msg_cp_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_group_ok:
        vCALL next
        vRES
        vJMP .Lex_climb
#:    }
#:  }
#:  else if (tk == Mul) {
.Lex_deref:
        vJNE_GI tk, Mul, .Lex_addrof
#:    next(); expr(Inc);
        vCALL next
        vRES
        vARGI 1, Inc
        vCALL expr
        vRES
#:    if (ty > INT) ty = ty - PTR; else { printf("%d: bad dereference\n", line); exit(-1); }
        vJGT_GI ty, INT, .Lex_deref_ok
        vARGS 1, msg_bad_deref
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_deref_ok:
        vDECGI ty, PTR
#:    *++e = (ty == CHAR) ? LC : LI;
        vLDBI LI
        vJNE_GI ty, CHAR, .Lex_deref_emit
        vLDBI LC
.Lex_deref_emit:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vJMP .Lex_climb
#:  }
#:  else if (tk == And) {
.Lex_addrof:
        vJNE_GI tk, And_, .Lex_not
#:    next(); expr(Inc);
        vCALL next
        vRES
        vARGI 1, Inc
        vCALL expr
        vRES
#:    if (*e == LC || *e == LI) --e; else { printf("%d: bad address-of\n", line); exit(-1); }
        vLDAG e
        vDEREFA
        vJEQ_AI LC, .Lex_addr_ok
        vJEQ_AI LI, .Lex_addr_ok
        vARGS 1, msg_bad_addr
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_addr_ok:
        vDECGW e, 1
#:    ty = ty + PTR;
        vINCGI ty, PTR
        vJMP .Lex_climb
#:  }
#:  else if (tk == '!') { next(); expr(Inc); *++e = PSH; *++e = IMM; *++e = 0; *++e = EQ; ty = INT; }
.Lex_not:
        vJNE_GI tk, 33, .Lex_bnot  /* '!' */
        vCALL next
        vRES
        vARGI 1, Inc
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vSTWA_I 0
        vINCGW e, 1
        vLDAG e
        vSTWA_I EQ_
        vSTIG ty, INT
        vJMP .Lex_climb
#:  else if (tk == '~') { next(); expr(Inc); *++e = PSH; *++e = IMM; *++e = -1; *++e = XOR; ty = INT; }
.Lex_bnot:
        vJNE_GI tk, 126, .Lex_pos  /* '~' */
        vCALL next
        vRES
        vARGI 1, Inc
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vSTWA_I -1
        vINCGW e, 1
        vLDAG e
        vSTWA_I XOR_
        vSTIG ty, INT
        vJMP .Lex_climb
#:  else if (tk == Add) { next(); expr(Inc); ty = INT; }
.Lex_pos:
        vJNE_GI tk, Add, .Lex_neg
        vCALL next
        vRES
        vARGI 1, Inc
        vCALL expr
        vRES
        vSTIG ty, INT
        vJMP .Lex_climb
#:  else if (tk == Sub) {
.Lex_neg:
        vJNE_GI tk, Sub, .Lex_predec
#:    next(); *++e = IMM;
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
#:    if (tk == Num) { *++e = -ival; next(); } else { *++e = -1; *++e = PSH; expr(Inc); *++e = MUL; }
        vJNE_GI tk, Num, .Lex_neg_expr
        vLDBG ival
        vNEGB
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vCALL next
        vRES
        vJMP .Lex_neg_done
.Lex_neg_expr:
        vINCGW e, 1
        vLDAG e
        vSTWA_I -1
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Inc
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I MUL
#:    ty = INT;
.Lex_neg_done:
        vSTIG ty, INT
        vJMP .Lex_climb
#:  }
#:  else if (tk == Inc || tk == Dec) {
.Lex_predec:
        vJEQ_GI tk, Inc, .Lex_pre
        vJNE_GI tk, Dec, .Lex_bad_expr
.Lex_pre:
#:    t = tk; next(); expr(Inc);
        vLDAG tk
        vSTAL t
        vCALL next
        vRES
        vARGI 1, Inc
        vCALL expr
        vRES
#:    if (*e == LC) { *e = PSH; *++e = LC; }
        vLDAG e
        vDEREFAB
        vJNE_BI LC, .Lex_pre_li
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I LC
        vJMP .Lex_pre_emit
#:    else if (*e == LI) { *e = PSH; *++e = LI; }
.Lex_pre_li:
        vJNE_BI LI, .Lex_pre_err
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I LI
        vJMP .Lex_pre_emit
#:    else { printf("%d: bad lvalue in pre-increment\n", line); exit(-1); }
.Lex_pre_err:
        vARGS 1, msg_lval_pre
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_pre_emit:
#:    *++e = PSH;
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
#:    *++e = IMM; *++e = (ty > PTR) ? sizeof(int) : sizeof(char);
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vLDBI WORDSZ  /* sizeof(int) */
        vJGT_GI ty, PTR, .Lex_pre_size
        vLDBI 1  /* sizeof(char) */
.Lex_pre_size:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:    *++e = (t == Inc) ? ADD : SUB;
        vLDBI ADD
        vJEQ_LI t, Inc, .Lex_pre_addsub
        vLDBI SUB
.Lex_pre_addsub:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:    *++e = (ty == CHAR) ? SC : SI;
        vLDBI SI_
        vJNE_GI ty, CHAR, .Lex_pre_store
        vLDBI SC
.Lex_pre_store:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vJMP .Lex_climb
#:  }
#:  else { printf("%d: bad expression\n", line); exit(-1); }
.Lex_bad_expr:
        vARGS 1, msg_bad_expr
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES

#:
#:  while (tk >= lev) { // "precedence climbing" or "Top Down Operator Precedence" method
.Lex_climb:
        vLDAG tk
        vJLT_AL lev, .Lex_done
#:    t = ty;
        vLDAG ty
        vSTAL t
#:    if (tk == Assign) {
        vJNE_GI tk, Assign, .Lex_cond
#:      next();
        vCALL next
        vRES
#:      if (*e == LC || *e == LI) *e = PSH; else { printf("%d: bad lvalue in assignment\n", line); exit(-1); }
        vLDAG e
        vDEREFAB
        vJEQ_BI LC, .Lex_asgn_ok
        vJEQ_BI LI, .Lex_asgn_ok
        vARGS 1, msg_lval_asgn
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_asgn_ok:
        vSTWA_I PSH
#:      expr(Assign); *++e = ((ty = t) == CHAR) ? SC : SI;
        vARGI 1, Assign
        vCALL expr
        vRES
        vLDAL t
        vSTAG ty
        vLDBI SI_
        vJNE_AI CHAR, .Lex_asgn_emit
        vLDBI SC
.Lex_asgn_emit:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vJMP .Lex_climb
#:    }
#:    else if (tk == Cond) {
.Lex_cond:
        vJNE_GI tk, Cond, .Lex_lor
#:      next();
        vCALL next
        vRES
#:      *++e = BZ; d = ++e;
        vINCGW e, 1
        vLDAG e
        vSTWA_I BZ
        vINCGW e, 1
        vLDAG e
        vSTAL d
#:      expr(Assign);
        vARGI 1, Assign
        vCALL expr
        vRES
#:      if (tk == ':') next(); else { printf("%d: conditional missing colon\n", line); exit(-1); }
        vJEQ_GI tk, 58, .Lex_cond_colon  /* ':' */
        vARGS 1, msg_cond_colon
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_cond_colon:
        vCALL next
        vRES
#:      *d = (int)(e + 3); *++e = JMP; d = ++e;
        vLDAG e
        vADDAW 3
        vLDBL d
        vSTWB_A
        vINCGW e, 1
        vLDAG e
        vSTWA_I JMP
        vINCGW e, 1
        vLDAG e
        vSTAL d
#:      expr(Cond);
        vARGI 1, Cond
        vCALL expr
        vRES
#:      *d = (int)(e + 1);
        vLDAG e
        vADDAW 1
        vLDBL d
        vSTWB_A
        vJMP .Lex_climb
#:    }
#:    else if (tk == Lor) { next(); *++e = BNZ; d = ++e; expr(Lan); *d = (int)(e + 1); ty = INT; }
.Lex_lor:
        vJNE_GI tk, Lor, .Lex_lan
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I BNZ
        vINCGW e, 1
        vLDAG e
        vSTAL d
        vARGI 1, Lan
        vCALL expr
        vRES
        vLDAG e
        vADDAW 1
        vLDBL d
        vSTWB_A
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Lan) { next(); *++e = BZ;  d = ++e; expr(Or);  *d = (int)(e + 1); ty = INT; }
.Lex_lan:
        vJNE_GI tk, Lan, .Lex_or
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I BZ
        vINCGW e, 1
        vLDAG e
        vSTAL d
        vARGI 1, Or_
        vCALL expr
        vRES
        vLDAG e
        vADDAW 1
        vLDBL d
        vSTWB_A
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Or)  { next(); *++e = PSH; expr(Xor); *++e = OR;  ty = INT; }
.Lex_or:
        vJNE_GI tk, Or_, .Lex_xor
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Xor_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I OR_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Xor) { next(); *++e = PSH; expr(And); *++e = XOR; ty = INT; }
.Lex_xor:
        vJNE_GI tk, Xor_, .Lex_and
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, And_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I XOR_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == And) { next(); *++e = PSH; expr(Eq);  *++e = AND; ty = INT; }
.Lex_and:
        vJNE_GI tk, And_, .Lex_eq
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Eq_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I AND_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Eq)  { next(); *++e = PSH; expr(Lt);  *++e = EQ;  ty = INT; }
.Lex_eq:
        vJNE_GI tk, Eq_, .Lex_ne
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Lt_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I EQ_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Ne)  { next(); *++e = PSH; expr(Lt);  *++e = NE;  ty = INT; }
.Lex_ne:
        vJNE_GI tk, Ne_, .Lex_lt
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Lt_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I NE_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Lt)  { next(); *++e = PSH; expr(Shl); *++e = LT;  ty = INT; }
.Lex_lt:
        vJNE_GI tk, Lt_, .Lex_gt
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Shl_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I LT_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Gt)  { next(); *++e = PSH; expr(Shl); *++e = GT;  ty = INT; }
.Lex_gt:
        vJNE_GI tk, Gt_, .Lex_le
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Shl_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I GT_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Le)  { next(); *++e = PSH; expr(Shl); *++e = LE;  ty = INT; }
.Lex_le:
        vJNE_GI tk, Le_, .Lex_ge
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Shl_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I LE_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Ge)  { next(); *++e = PSH; expr(Shl); *++e = GE;  ty = INT; }
.Lex_ge:
        vJNE_GI tk, Ge_, .Lex_shl
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Shl_
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I GE_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Shl) { next(); *++e = PSH; expr(Add); *++e = SHL; ty = INT; }
.Lex_shl:
        vJNE_GI tk, Shl_, .Lex_shr
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Add
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I SHL_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Shr) { next(); *++e = PSH; expr(Add); *++e = SHR; ty = INT; }
.Lex_shr:
        vJNE_GI tk, Shr_, .Lex_add
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Add
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I SHR_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Add) {
.Lex_add:
        vJNE_GI tk, Add, .Lex_sub
#:      next(); *++e = PSH; expr(Mul);
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Mul
        vCALL expr
        vRES
#:      if ((ty = t) > PTR) { *++e = PSH; *++e = IMM; *++e = sizeof(int); *++e = MUL;  }
        vLDAL t
        vSTAG ty
        vJLE_AI PTR, .Lex_add_emit
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vSTWA_I WORDSZ  /* sizeof(int) */
        vINCGW e, 1
        vLDAG e
        vSTWA_I MUL
#:      *++e = ADD;
.Lex_add_emit:
        vINCGW e, 1
        vLDAG e
        vSTWA_I ADD
        vJMP .Lex_climb
#:    }
#:    else if (tk == Sub) {
.Lex_sub:
        vJNE_GI tk, Sub, .Lex_mul
#:      next(); *++e = PSH; expr(Mul);
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Mul
        vCALL expr
        vRES
#:      if (t > PTR && t == ty) { *++e = SUB; *++e = PSH; *++e = IMM; *++e = sizeof(int); *++e = DIV; ty = INT; }
        vLDAL t
        vJLE_AI PTR, .Lex_sub_ptr_int
        vJNE_AG ty, .Lex_sub_ptr_int
        vINCGW e, 1
        vLDAG e
        vSTWA_I SUB
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vSTWA_I WORDSZ  /* sizeof(int) */
        vINCGW e, 1
        vLDAG e
        vSTWA_I DIV
        vSTIG ty, INT
        vJMP .Lex_climb
#:      else if ((ty = t) > PTR) { *++e = PSH; *++e = IMM; *++e = sizeof(int); *++e = MUL; *++e = SUB; }
.Lex_sub_ptr_int:
        vLDAL t
        vSTAG ty
        vJLE_AI PTR, .Lex_sub_plain
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vSTWA_I WORDSZ  /* sizeof(int) */
        vINCGW e, 1
        vLDAG e
        vSTWA_I MUL
        vINCGW e, 1
        vLDAG e
        vSTWA_I SUB
        vJMP .Lex_climb
#:      else *++e = SUB;
.Lex_sub_plain:
        vINCGW e, 1
        vLDAG e
        vSTWA_I SUB
        vJMP .Lex_climb
#:    }
#:    else if (tk == Mul) { next(); *++e = PSH; expr(Inc); *++e = MUL; ty = INT; }
.Lex_mul:
        vJNE_GI tk, Mul, .Lex_div
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Inc
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I MUL
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Div) { next(); *++e = PSH; expr(Inc); *++e = DIV; ty = INT; }
.Lex_div:
        vJNE_GI tk, Div, .Lex_mod
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Inc
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I DIV
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Mod) { next(); *++e = PSH; expr(Inc); *++e = MOD; ty = INT; }
.Lex_mod:
        vJNE_GI tk, Mod_, .Lex_post
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Inc
        vCALL expr
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I MOD_
        vSTIG ty, INT
        vJMP .Lex_climb
#:    else if (tk == Inc || tk == Dec) {
.Lex_post:
        vJEQ_GI tk, Inc, .Lex_post_go
        vJEQ_GI tk, Dec, .Lex_post_go
        vJMP .Lex_brak
.Lex_post_go:
#:      if (*e == LC) { *e = PSH; *++e = LC; }
        vLDAG e
        vDEREFAB
        vJNE_BI LC, .Lex_post_li
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I LC
        vJMP .Lex_post_emit
#:      else if (*e == LI) { *e = PSH; *++e = LI; }
.Lex_post_li:
        vJNE_BI LI, .Lex_post_err
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I LI
        vJMP .Lex_post_emit
#:      else { printf("%d: bad lvalue in post-increment\n", line); exit(-1); }
.Lex_post_err:
        vARGS 1, msg_lval_post
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_post_emit:
#:      *++e = PSH; *++e = IMM; *++e = (ty > PTR) ? sizeof(int) : sizeof(char);
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vLDBI WORDSZ  /* sizeof(int) */
        vJGT_GI ty, PTR, .Lex_post_size1
        vLDBI 1  /* sizeof(char) */
.Lex_post_size1:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:      *++e = (tk == Inc) ? ADD : SUB;
        vLDBI ADD
        vJEQ_GI tk, Inc, .Lex_post_addsub
        vLDBI SUB
.Lex_post_addsub:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:      *++e = (ty == CHAR) ? SC : SI;
        vLDBI SI_
        vJNE_GI ty, CHAR, .Lex_post_store
        vLDBI SC
.Lex_post_store:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:      *++e = PSH; *++e = IMM; *++e = (ty > PTR) ? sizeof(int) : sizeof(char);
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vLDBI WORDSZ  /* sizeof(int) */
        vJGT_GI ty, PTR, .Lex_post_size2
        vLDBI 1  /* sizeof(char) */
.Lex_post_size2:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:      *++e = (tk == Inc) ? SUB : ADD;
        vLDBI SUB
        vJEQ_GI tk, Inc, .Lex_post_subadd
        vLDBI ADD
.Lex_post_subadd:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:      next();
        vCALL next
        vRES
        vJMP .Lex_climb
#:    }
#:    else if (tk == Brak) {
.Lex_brak:
        vJNE_GI tk, Brak, .Lex_bad_tk
#:      next(); *++e = PSH; expr(Assign);
        vCALL next
        vRES
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vARGI 1, Assign
        vCALL expr
        vRES
#:      if (tk == ']') next(); else { printf("%d: close bracket expected\n", line); exit(-1); }
        vJEQ_GI tk, 93, .Lex_brak_ok  /* ']' */
        vARGS 1, msg_cb_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_brak_ok:
        vCALL next
        vRES
#:      if (t > PTR) { *++e = PSH; *++e = IMM; *++e = sizeof(int); *++e = MUL;  }
        vLDAL t
        vJLE_AI PTR, .Lex_brak_chk
        vINCGW e, 1
        vLDAG e
        vSTWA_I PSH
        vINCGW e, 1
        vLDAG e
        vSTWA_I IMM
        vINCGW e, 1
        vLDAG e
        vSTWA_I WORDSZ  /* sizeof(int) */
        vINCGW e, 1
        vLDAG e
        vSTWA_I MUL
        vJMP .Lex_brak_add
#:      else if (t < PTR) { printf("%d: pointer type expected\n", line); exit(-1); }
.Lex_brak_chk:
        vJEQ_AI PTR, .Lex_brak_add
        vARGS 1, msg_ptr_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lex_brak_add:
#:      *++e = ADD;
        vINCGW e, 1
        vLDAG e
        vSTWA_I ADD
#:      *++e = ((ty = t - PTR) == CHAR) ? LC : LI;
        vLDAL t
        vSUBAI PTR
        vSTAG ty
        vLDBI LI
        vJNE_AI CHAR, .Lex_brak_load
        vLDBI LC
.Lex_brak_load:
        vINCGW e, 1
        vLDAG e
        vSTWA_B
        vJMP .Lex_climb
#:    }
#:    else { printf("%d: compiler error tk=%d\n", line, tk); exit(-1); }
.Lex_bad_tk:
        vARGS 1, msg_comp_err
        vARGG 2, line
        vARGG 3, tk
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
#:  }
#:}
.Lex_done:
        vRET

# ----------------------------------------------------------------------
#:
#:void stmt()
#:{
#:  int *a, *b;
# ----------------------------------------------------------------------
.globl stmt
stmt:
        vENTER 2
a = 1                      /* int *a; */
b = 2                      /* int *b; */

#:
#:  if (tk == If) {
        vJNE_GI tk, If, .Lst_while
#:    next();
        vCALL next
        vRES
#:    if (tk == '(') next(); else { printf("%d: open paren expected\n", line); exit(-1); }
        vJEQ_GI tk, 40, .Lst_if_open  /* '(' */
        vARGS 1, msg_op_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lst_if_open:
        vCALL next
        vRES
#:    expr(Assign);
        vARGI 1, Assign
        vCALL expr
        vRES
#:    if (tk == ')') next(); else { printf("%d: close paren expected\n", line); exit(-1); }
        vJEQ_GI tk, 41, .Lst_if_close  /* ')' */
        vARGS 1, msg_cp_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lst_if_close:
        vCALL next
        vRES
#:    *++e = BZ; b = ++e;
        vINCGW e, 1
        vLDAG e
        vSTWA_I BZ
        vINCGW e, 1
        vLDAG e
        vSTAL b
#:    stmt();
        vCALL stmt
        vRES
#:    if (tk == Else) {
        vJNE_GI tk, Else, .Lst_if_end
#:      *b = (int)(e + 3); *++e = JMP; b = ++e;
        vLDAG e
        vADDAW 3
        vLDBL b
        vSTWB_A
        vINCGW e, 1
        vLDAG e
        vSTWA_I JMP
        vINCGW e, 1
        vLDAG e
        vSTAL b
#:      next();
        vCALL next
        vRES
#:      stmt();
        vCALL stmt
        vRES
#:    }
#:    *b = (int)(e + 1);
.Lst_if_end:
        vLDAG e
        vADDAW 1
        vLDBL b
        vSTWB_A
        vRET
#:  }
#:  else if (tk == While) {
.Lst_while:
        vJNE_GI tk, While, .Lst_return
#:    next();
        vCALL next
        vRES
#:    a = e + 1;
        vLDAG e
        vADDAW 1
        vSTAL a
#:    if (tk == '(') next(); else { printf("%d: open paren expected\n", line); exit(-1); }
        vJEQ_GI tk, 40, .Lst_wh_open  /* '(' */
        vARGS 1, msg_op_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lst_wh_open:
        vCALL next
        vRES
#:    expr(Assign);
        vARGI 1, Assign
        vCALL expr
        vRES
#:    if (tk == ')') next(); else { printf("%d: close paren expected\n", line); exit(-1); }
        vJEQ_GI tk, 41, .Lst_wh_close  /* ')' */
        vARGS 1, msg_cp_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lst_wh_close:
        vCALL next
        vRES
#:    *++e = BZ; b = ++e;
        vINCGW e, 1
        vLDAG e
        vSTWA_I BZ
        vINCGW e, 1
        vLDAG e
        vSTAL b
#:    stmt();
        vCALL stmt
        vRES
#:    *++e = JMP; *++e = (int)a;
        vINCGW e, 1
        vLDAG e
        vSTWA_I JMP
        vLDBL a
        vINCGW e, 1
        vLDAG e
        vSTWA_B
#:    *b = (int)(e + 1);
        vLDAG e
        vADDAW 1
        vLDBL b
        vSTWB_A
        vRET
#:  }
#:  else if (tk == Return) {
.Lst_return:
        vJNE_GI tk, Return, .Lst_block
#:    next();
        vCALL next
        vRES
#:    if (tk != ';') expr(Assign);
        vJEQ_GI tk, 59, .Lst_ret_lev  /* ';' */
        vARGI 1, Assign
        vCALL expr
        vRES
.Lst_ret_lev:
#:    *++e = LEV;
        vINCGW e, 1
        vLDAG e
        vSTWA_I LEV
#:    if (tk == ';') next(); else { printf("%d: semicolon expected\n", line); exit(-1); }
        vJEQ_GI tk, 59, .Lst_ret_semi  /* ';' */
        vARGS 1, msg_semi_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lst_ret_semi:
        vCALL next
        vRES
        vRET
#:  }
#:  else if (tk == '{') {
.Lst_block:
        vJNE_GI tk, 123, .Lst_semi  /* '{' */
#:    next();
        vCALL next
        vRES
#:    while (tk != '}') stmt();
.Lst_block_while:
        vJEQ_GI tk, 125, .Lst_block_done  /* '}' */
        vCALL stmt
        vRES
        vJMP .Lst_block_while
.Lst_block_done:
#:    next();
        vCALL next
        vRES
        vRET
#:  }
#:  else if (tk == ';') {
.Lst_semi:
        vJNE_GI tk, 59, .Lst_expr  /* ';' */
#:    next();
        vCALL next
        vRES
        vRET
#:  }
#:  else {
#:    expr(Assign);
.Lst_expr:
        vARGI 1, Assign
        vCALL expr
        vRES
#:    if (tk == ';') next(); else { printf("%d: semicolon expected\n", line); exit(-1); }
        vJEQ_GI tk, 59, .Lst_expr_semi  /* ';' */
        vARGS 1, msg_semi_exp
        vARGG 2, line
        vCALLV printf
        vRES
        vARGI 1, -1
        vCALL exit
        vRES
.Lst_expr_semi:
        vCALL next
        vRES
        vRET
#:  }
#:}

# ----------------------------------------------------------------------
#:
#:int main(int argc, char **argv)
#:{
#:  int fd, bt, ty, poolsz, *idmain;
#:  int *pc, *sp, *bp, a, cycle; // vm registers
#:  int i, *t; // temps
# ----------------------------------------------------------------------
# note: locals ty, sp, bp are named ty_, sp_, bp_ below ("ty" collides
# with the global variable; "sp" and "bp" are x86 register names)
.globl main
main:
        vENTER 14
argc = 1                      /* int argc;   (argument) */
argv = 2                      /* char **argv; (argument) */
fd = 3                      /* int fd; */
bt = 4                      /* int bt; */
ty_ = 5                      /* int ty; */
poolsz = 6                      /* int poolsz; */
idmain = 7                      /* int *idmain; */
pc = 8                      /* int *pc; */
sp_ = 9                      /* int *sp; */
bp_ = 10                      /* int *bp; */
a = 11                      /* int a; */
cycle = 12                      /* int cycle; */
i = 13                      /* int i; */
t = 14                      /* int *t; */
        vSTARG 1, argc
        vSTARG 2, argv

#:
#:  --argc; ++argv;
        vDECLI argc, 1
        vINCLW argv, 1
#:  if (argc > 0 && **argv == '-' && (*argv)[1] == 's') { src = 1; --argc; ++argv; }
        vJLE_LI argc, 0, .Lm_chk_d
        vLDAL argv
        vDEREFA
        vLDSBAB 0
        vJNE_BI 45, .Lm_chk_d  /* '-' */
        vLDSBAB 1
        vJNE_BI 115, .Lm_chk_d  /* 's' */
        vSTIG src, 1
        vDECLI argc, 1
        vINCLW argv, 1
#:  if (argc > 0 && **argv == '-' && (*argv)[1] == 'd') { debug = 1; --argc; ++argv; }
.Lm_chk_d:
        vJLE_LI argc, 0, .Lm_usage_chk
        vLDAL argv
        vDEREFA
        vLDSBAB 0
        vJNE_BI 45, .Lm_usage_chk  /* '-' */
        vLDSBAB 1
        vJNE_BI 100, .Lm_usage_chk  /* 'd' */
        vSTIG debug, 1
        vDECLI argc, 1
        vINCLW argv, 1
#:  if (argc < 1) { printf("usage: c4 [-s] [-d] file ...\n"); return -1; }
.Lm_usage_chk:
        vJGE_LI argc, 1, .Lm_open_file
        vARGS 1, msg_usage
        vCALLV printf
        vRES
        vRETI -1
#:
#:  if ((fd = open(*argv, 0)) < 0) { printf("could not open(%s)\n", *argv); return -1; }
.Lm_open_file:
        vLDAL argv
        vARGMA 1, 0
        vARGZ 2
        vCALLV open
        vRES32
        vSTAL fd
        vJGE_AI 0, .Lm_pool
        vARGS 1, msg_open
        vLDAL argv
        vARGMA 2, 0
        vCALLV printf
        vRES
        vRETI -1
#:
#:  poolsz = 256*1024; // arbitrary size
.Lm_pool:
        vSTIL poolsz, 256*1024
#:  if (!(sym = malloc(poolsz))) { printf("could not malloc(%d) symbol area\n", poolsz); return -1; }
        vARGL 1, poolsz
        vCALL malloc
        vRES
        vSTAG sym
        vJNZA .Lm_m_text
        vARGS 1, msg_m_sym
        vARGL 2, poolsz
        vCALLV printf
        vRES
        vRETI -1
#:  if (!(le = e = malloc(poolsz))) { printf("could not malloc(%d) text area\n", poolsz); return -1; }
.Lm_m_text:
        vARGL 1, poolsz
        vCALL malloc
        vRES
        vSTAG e
        vSTAG le_
        vJNZA .Lm_m_data
        vARGS 1, msg_m_text
        vARGL 2, poolsz
        vCALLV printf
        vRES
        vRETI -1
#:  if (!(data = malloc(poolsz))) { printf("could not malloc(%d) data area\n", poolsz); return -1; }
.Lm_m_data:
        vARGL 1, poolsz
        vCALL malloc
        vRES
        vSTAG data
        vJNZA .Lm_m_stack
        vARGS 1, msg_m_data
        vARGL 2, poolsz
        vCALLV printf
        vRES
        vRETI -1
#:  if (!(sp = malloc(poolsz))) { printf("could not malloc(%d) stack area\n", poolsz); return -1; }
.Lm_m_stack:
        vARGL 1, poolsz
        vCALL malloc
        vRES
        vSTAL sp_
        vJNZA .Lm_memset
        vARGS 1, msg_m_stack
        vARGL 2, poolsz
        vCALLV printf
        vRES
        vRETI -1
#:
#:  memset(sym,  0, poolsz);
.Lm_memset:
        vARGG 1, sym
        vARGZ 2
        vARGL 3, poolsz
        vCALL memset
        vRES
#:  memset(e,    0, poolsz);
        vARGG 1, e
        vARGZ 2
        vARGL 3, poolsz
        vCALL memset
        vRES
#:  memset(data, 0, poolsz);
        vARGG 1, data
        vARGZ 2
        vARGL 3, poolsz
        vCALL memset
        vRES

#:
#:  p = "char else enum if int return sizeof while "
#:      "open read close printf malloc free memset memcmp exit void main";
        vSTSG p, keywords
#:  i = Char; while (i <= While) { next(); id[Tk] = i++; } // add keywords to symbol table
        vSTIL i, Char
.Lm_kw_loop:
        vJGT_LI i, While, .Lm_sys_init
        vCALL next
        vRES
        vLDAG id
        vLDBL i
        vSTF_B Tk
        vINCLI i, 1
        vJMP .Lm_kw_loop
#:  i = OPEN; while (i <= EXIT) { next(); id[Class] = Sys; id[Type] = INT; id[Val] = i++; } // add library to symbol table
.Lm_sys_init:
        vSTIL i, OPEN
.Lm_sys_loop:
        vJGT_LI i, EXIT, .Lm_void
        vCALL next
        vRES
        vLDAG id
        vSTF_I Class, Sys
        vSTF_I Type, INT
        vLDBL i
        vSTF_B Val
        vINCLI i, 1
        vJMP .Lm_sys_loop
#:  next(); id[Tk] = Char; // handle void type
.Lm_void:
        vCALL next
        vRES
        vLDAG id
        vSTF_I Tk, Char
#:  next(); idmain = id; // keep track of main
        vCALL next
        vRES
        vLDAG id
        vSTAL idmain

#:
#:  if (!(lp = p = malloc(poolsz))) { printf("could not malloc(%d) source area\n", poolsz); return -1; }
        vARGL 1, poolsz
        vCALL malloc
        vRES
        vSTAG p
        vSTAG lp
        vJNZA .Lm_read_src
        vARGS 1, msg_m_src
        vARGL 2, poolsz
        vCALLV printf
        vRES
        vRETI -1
#:  if ((i = read(fd, p, poolsz-1)) <= 0) { printf("read() returned %d\n", i); return -1; }
.Lm_read_src:
        vARGL 1, fd
        vARGG 2, p
        vARGL 3, poolsz
        vARGSUBI 3, 1
        vCALL read
        vRES
        vSTAL i
        vJGT_AI 0, .Lm_read_ok
        vARGS 1, msg_read
        vARGL 2, i
        vCALLV printf
        vRES
        vRETI -1
#:  p[i] = 0;
.Lm_read_ok:
        vLDAG p
        vLDBL i
        vSTBAB_Z
#:  close(fd);
        vARGL 1, fd
        vCALL close
        vRES

#:
#:  // parse declarations
#:  line = 1;
        vSTIG line, 1
#:  next();
        vCALL next
        vRES
#:  while (tk) {
.Lm_decl_loop:
        vJEQ_GI tk, 0, .Lm_run_setup
#:    bt = INT; // basetype
        vSTIL bt, INT
#:    if (tk == Int) next();
        vJNE_GI tk, Int, .Lm_decl_char
        vCALL next
        vRES
        vJMP .Lm_decl_names
#:    else if (tk == Char) { next(); bt = CHAR; }
.Lm_decl_char:
        vJNE_GI tk, Char, .Lm_decl_enum
        vCALL next
        vRES
        vSTIL bt, CHAR
        vJMP .Lm_decl_names
#:    else if (tk == Enum) {
.Lm_decl_enum:
        vJNE_GI tk, Enum, .Lm_decl_names
#:      next();
        vCALL next
        vRES
#:      if (tk != '{') next();
        vJEQ_GI tk, 123, .Lm_enum_body  /* '{' */
        vCALL next
        vRES
#:      if (tk == '{') {
.Lm_enum_body:
        vJNE_GI tk, 123, .Lm_decl_names  /* '{' */
#:        next();
        vCALL next
        vRES
#:        i = 0;
        vSTIL i, 0
#:        while (tk != '}') {
.Lm_enum_loop:
        vJEQ_GI tk, 125, .Lm_enum_done  /* '}' */
#:          if (tk != Id) { printf("%d: bad enum identifier %d\n", line, tk); return -1; }
        vJEQ_GI tk, Id, .Lm_enum_id
        vARGS 1, msg_enum_id
        vARGG 2, line
        vARGG 3, tk
        vCALLV printf
        vRES
        vRETI -1
#:          next();
.Lm_enum_id:
        vCALL next
        vRES
#:          if (tk == Assign) {
        vJNE_GI tk, Assign, .Lm_enum_set
#:            next();
        vCALL next
        vRES
#:            if (tk != Num) { printf("%d: bad enum initializer\n", line); return -1; }
        vJEQ_GI tk, Num, .Lm_enum_val
        vARGS 1, msg_enum_init
        vARGG 2, line
        vCALLV printf
        vRES
        vRETI -1
#:            i = ival;
.Lm_enum_val:
        vLDAG ival
        vSTAL i
#:            next();
        vCALL next
        vRES
#:          }
#:          id[Class] = Num; id[Type] = INT; id[Val] = i++;
.Lm_enum_set:
        vLDAG id
        vSTF_I Class, Num
        vSTF_I Type, INT
        vLDBL i
        vSTF_B Val
        vINCLI i, 1
#:          if (tk == ',') next();
        vJNE_GI tk, 44, .Lm_enum_loop  /* ',' */
        vCALL next
        vRES
        vJMP .Lm_enum_loop
#:        }
#:        next();
.Lm_enum_done:
        vCALL next
        vRES
#:      }
#:    }
#:    while (tk != ';' && tk != '}') {
.Lm_decl_names:
        vJEQ_GI tk, 59, .Lm_decl_next  /* ';' */
        vJEQ_GI tk, 125, .Lm_decl_next  /* '}' */
#:      ty = bt;
        vLDAL bt
        vSTAL ty_
#:      while (tk == Mul) { next(); ty = ty + PTR; }
.Lm_gmul:
        vJNE_GI tk, Mul, .Lm_gname
        vCALL next
        vRES
        vINCLI ty_, PTR
        vJMP .Lm_gmul
#:      if (tk != Id) { printf("%d: bad global declaration\n", line); return -1; }
.Lm_gname:
        vJEQ_GI tk, Id, .Lm_gdup
        vARGS 1, msg_bad_glo
        vARGG 2, line
        vCALLV printf
        vRES
        vRETI -1
#:      if (id[Class]) { printf("%d: duplicate global definition\n", line); return -1; }
.Lm_gdup:
        vLDAG id
        vJEQ_FI Class, 0, .Lm_gok
        vARGS 1, msg_dup_glo
        vARGG 2, line
        vCALLV printf
        vRES
        vRETI -1
#:      next();
.Lm_gok:
        vCALL next
        vRES
#:      id[Type] = ty;
        vLDAG id
        vLDBL ty_
        vSTF_B Type
#:      if (tk == '(') { // function
        vJNE_GI tk, 40, .Lm_gvar  /* '(' */
#:        id[Class] = Fun;
        vLDAG id
        vSTF_I Class, Fun
#:        id[Val] = (int)(e + 1);
        vLDBG e
        vADDBI WORDSZ
        vSTF_B Val
#:        next(); i = 0;
        vCALL next
        vRES
        vSTIL i, 0
#:        while (tk != ')') {
.Lm_param_loop:
        vJEQ_GI tk, 41, .Lm_param_done  /* ')' */
#:          ty = INT;
        vSTIL ty_, INT
#:          if (tk == Int) next();
        vJNE_GI tk, Int, .Lm_param_char
        vCALL next
        vRES
        vJMP .Lm_param_mul
#:          else if (tk == Char) { next(); ty = CHAR; }
.Lm_param_char:
        vJNE_GI tk, Char, .Lm_param_mul
        vCALL next
        vRES
        vSTIL ty_, CHAR
#:          while (tk == Mul) { next(); ty = ty + PTR; }
.Lm_param_mul:
        vJNE_GI tk, Mul, .Lm_param_id
        vCALL next
        vRES
        vINCLI ty_, PTR
        vJMP .Lm_param_mul
#:          if (tk != Id) { printf("%d: bad parameter declaration\n", line); return -1; }
.Lm_param_id:
        vJEQ_GI tk, Id, .Lm_param_dup
        vARGS 1, msg_bad_param
        vARGG 2, line
        vCALLV printf
        vRES
        vRETI -1
#:          if (id[Class] == Loc) { printf("%d: duplicate parameter definition\n", line); return -1; }
.Lm_param_dup:
        vLDAG id
        vJNE_FI Class, Loc, .Lm_param_set
        vARGS 1, msg_dup_param
        vARGG 2, line
        vCALLV printf
        vRES
        vRETI -1
#:          id[HClass] = id[Class]; id[Class] = Loc;
.Lm_param_set:
        vLDAG id
        vLDBF Class
        vSTF_B HClass
        vSTF_I Class, Loc
#:          id[HType]  = id[Type];  id[Type] = ty;
        vLDBF Type
        vSTF_B HType
        vLDBL ty_
        vSTF_B Type
#:          id[HVal]   = id[Val];   id[Val] = i++;
        vLDBF Val
        vSTF_B HVal
        vLDBL i
        vSTF_B Val
        vINCLI i, 1
#:          next();
        vCALL next
        vRES
#:          if (tk == ',') next();
        vJNE_GI tk, 44, .Lm_param_loop  /* ',' */
        vCALL next
        vRES
        vJMP .Lm_param_loop
#:        }
#:        next();
.Lm_param_done:
        vCALL next
        vRES
#:        if (tk != '{') { printf("%d: bad function definition\n", line); return -1; }
        vJEQ_GI tk, 123, .Lm_fbody  /* '{' */
        vARGS 1, msg_bad_func
        vARGG 2, line
        vCALLV printf
        vRES
        vRETI -1
#:        loc = ++i;
.Lm_fbody:
        vINCLI i, 1
        vLDAL i
        vSTAG loc
#:        next();
        vCALL next
        vRES
#:        while (tk == Int || tk == Char) {
.Lm_local_loop:
        vJEQ_GI tk, Int, .Lm_local_bt
        vJEQ_GI tk, Char, .Lm_local_bt
        vJMP .Lm_fbody_emit
#:          bt = (tk == Int) ? INT : CHAR;
.Lm_local_bt:
        vLDAI INT
        vJEQ_GI tk, Int, .Lm_local_bts
        vLDAI CHAR
.Lm_local_bts:
        vSTAL bt
#:          next();
        vCALL next
        vRES
#:          while (tk != ';') {
.Lm_local_names:
        vJEQ_GI tk, 59, .Lm_local_semi  /* ';' */
#:            ty = bt;
        vLDAL bt
        vSTAL ty_
#:            while (tk == Mul) { next(); ty = ty + PTR; }
.Lm_lmul:
        vJNE_GI tk, Mul, .Lm_lid
        vCALL next
        vRES
        vINCLI ty_, PTR
        vJMP .Lm_lmul
#:            if (tk != Id) { printf("%d: bad local declaration\n", line); return -1; }
.Lm_lid:
        vJEQ_GI tk, Id, .Lm_ldup
        vARGS 1, msg_bad_loc
        vARGG 2, line
        vCALLV printf
        vRES
        vRETI -1
#:            if (id[Class] == Loc) { printf("%d: duplicate local definition\n", line); return -1; }
.Lm_ldup:
        vLDAG id
        vJNE_FI Class, Loc, .Lm_local_set
        vARGS 1, msg_dup_loc
        vARGG 2, line
        vCALLV printf
        vRES
        vRETI -1
#:            id[HClass] = id[Class]; id[Class] = Loc;
.Lm_local_set:
        vLDAG id
        vLDBF Class
        vSTF_B HClass
        vSTF_I Class, Loc
#:            id[HType]  = id[Type];  id[Type] = ty;
        vLDBF Type
        vSTF_B HType
        vLDBL ty_
        vSTF_B Type
#:            id[HVal]   = id[Val];   id[Val] = ++i;
        vLDBF Val
        vSTF_B HVal
        vINCLI i, 1
        vLDBL i
        vSTF_B Val
#:            next();
        vCALL next
        vRES
#:            if (tk == ',') next();
        vJNE_GI tk, 44, .Lm_local_names  /* ',' */
        vCALL next
        vRES
        vJMP .Lm_local_names
#:          }
#:          next();
.Lm_local_semi:
        vCALL next
        vRES
        vJMP .Lm_local_loop
#:        }
#:        *++e = ENT; *++e = i - loc;
.Lm_fbody_emit:
        vINCGW e, 1
        vLDAG e
        vSTWA_I ENT
        vLDAL i
        vSUBAG loc
        vINCGW e, 1
        vLDBG e
        vSTWB_A
#:        while (tk != '}') stmt();
.Lm_stmt_loop:
        vJEQ_GI tk, 125, .Lm_stmt_done  /* '}' */
        vCALL stmt
        vRES
        vJMP .Lm_stmt_loop
#:        *++e = LEV;
.Lm_stmt_done:
        vINCGW e, 1
        vLDAG e
        vSTWA_I LEV
#:        id = sym; // unwind symbol table locals
        vLDAG sym
        vSTAG id
#:        while (id[Tk]) {
.Lm_unwind:
        vLDAG id
        vJEQ_FI Tk, 0, .Lm_gnext
#:          if (id[Class] == Loc) {
        vJNE_FI Class, Loc, .Lm_unwind_next
#:            id[Class] = id[HClass];
        vLDBF HClass
        vSTF_B Class
#:            id[Type] = id[HType];
        vLDBF HType
        vSTF_B Type
#:            id[Val] = id[HVal];
        vLDBF HVal
        vSTF_B Val
#:          }
#:          id = id + Idsz;
.Lm_unwind_next:
        vINCGW id, Idsz
        vJMP .Lm_unwind
#:        }
#:      }
#:      else {
#:        id[Class] = Glo;
.Lm_gvar:
        vLDAG id
        vSTF_I Class, Glo
#:        id[Val] = (int)data;
        vLDBG data
        vSTF_B Val
#:        data = data + sizeof(int);
        vINCGI data, WORDSZ
#:      }
#:      if (tk == ',') next();
.Lm_gnext:
        vJNE_GI tk, 44, .Lm_decl_names  /* ',' */
        vCALL next
        vRES
        vJMP .Lm_decl_names
#:    }
#:    next();
.Lm_decl_next:
        vCALL next
        vRES
        vJMP .Lm_decl_loop
#:  }

#:
#:  if (!(pc = (int *)idmain[Val])) { printf("main() not defined\n"); return -1; }
.Lm_run_setup:
        vLDAL idmain
        vLDAF Val
        vSTAL pc
        vJNZA .Lm_src_chk
        vARGS 1, msg_no_main
        vCALLV printf
        vRES
        vRETI -1
#:  if (src) return 0;
.Lm_src_chk:
        vJEQ_GI src, 0, .Lm_stack
        vRETI 0

#:
#:  // setup stack
#:  bp = sp = (int *)((int)sp + poolsz);
.Lm_stack:
        vLDAL sp_
        vADDAL poolsz
        vSTAL sp_
        vSTAL bp_
#:  *--sp = EXIT; // call exit if main returns
        vDECLW sp_, 1
        vLDAL sp_
        vSTWA_I EXIT
#:  *--sp = PSH; t = sp;
        vDECLW sp_, 1
        vLDAL sp_
        vSTWA_I PSH
        vSTAL t
#:  *--sp = argc;
        vDECLW sp_, 1
        vLDAL sp_
        vLDBL argc
        vSTWA_B
#:  *--sp = (int)argv;
        vDECLW sp_, 1
        vLDAL sp_
        vLDBL argv
        vSTWA_B
#:  *--sp = (int)t;
        vDECLW sp_, 1
        vLDAL sp_
        vLDBL t
        vSTWA_B

#:
#:  // run...
#:  cycle = 0;
        vSTIL cycle, 0
#:  while (1) {
#:    i = *pc++; ++cycle;
.Lm_vm:
        vLDAL pc
        vDEREFAB
        vSTBL i
        vINCLW pc, 1
        vINCLI cycle, 1
#:    if (debug) {
        vJEQ_GI debug, 0, .Lm_op_lea
#:      printf("%d> %.4s", cycle,
#:        &"LEA ,IMM ,JMP ,JSR ,BZ  ,BNZ ,ENT ,ADJ ,LEV ,LI  ,LC  ,SI  ,SC  ,PSH ,"
#:         "OR  ,XOR ,AND ,EQ  ,NE  ,LT  ,GT  ,LE  ,GE  ,SHL ,SHR ,ADD ,SUB ,MUL ,DIV ,MOD ,"
#:         "OPEN,READ,CLOS,PRTF,MALC,FREE,MSET,MCMP,EXIT,"[i * 5]);
        vARGS 1, fmt_debug
        vARGL 2, cycle
        vARGL 3, i
        vARGMULI 3, 5
        vARGADDS 3, ops
        vCALLV printf
        vRES
#:      if (i <= ADJ) printf(" %d\n", *pc); else printf("\n");
        vJGT_LI i, ADJ, .Lm_dbg_nl
        vARGS 1, fmt_opval
        vLDAL pc
        vARGMA 2, 0
        vCALLV printf
        vRES
        vJMP .Lm_op_lea
.Lm_dbg_nl:
        vARGS 1, fmt_nl
        vCALLV printf
        vRES
#:    }
#:    if      (i == LEA) a = (int)(bp + *pc++);                             // load local address
.Lm_op_lea:
        vJNE_LI i, LEA, .Lm_op_imm
        vLDAL pc
        vDEREFA
        vMULAW  /* (int *) arithmetic scales by 8 */
        vADDAL bp_
        vSTAL a
        vINCLW pc, 1
        vJMP .Lm_vm
#:    else if (i == IMM) a = *pc++;                                         // load global address or immediate
.Lm_op_imm:
        vJNE_LI i, IMM, .Lm_op_jmp
        vLDAL pc
        vDEREFA
        vSTAL a
        vINCLW pc, 1
        vJMP .Lm_vm
#:    else if (i == JMP) pc = (int *)*pc;                                   // jump
.Lm_op_jmp:
        vJNE_LI i, JMP, .Lm_op_jsr
        vLDAL pc
        vDEREFA
        vSTAL pc
        vJMP .Lm_vm
#:    else if (i == JSR) { *--sp = (int)(pc + 1); pc = (int *)*pc; }        // jump to subroutine
.Lm_op_jsr:
        vJNE_LI i, JSR, .Lm_op_bz
        vDECLW sp_, 1
        vLDAL pc
        vADDAW 1
        vLDBL sp_
        vSTWB_A
        vLDAL pc
        vDEREFA
        vSTAL pc
        vJMP .Lm_vm
#:    else if (i == BZ)  pc = a ? pc + 1 : (int *)*pc;                      // branch if zero
.Lm_op_bz:
        vJNE_LI i, BZ, .Lm_op_bnz
        vJEQ_LI a, 0, .Lm_bz_taken
        vINCLW pc, 1
        vJMP .Lm_vm
.Lm_bz_taken:
        vLDAL pc
        vDEREFA
        vSTAL pc
        vJMP .Lm_vm
#:    else if (i == BNZ) pc = a ? (int *)*pc : pc + 1;                      // branch if not zero
.Lm_op_bnz:
        vJNE_LI i, BNZ, .Lm_op_ent
        vJNE_LI a, 0, .Lm_bnz_taken
        vINCLW pc, 1
        vJMP .Lm_vm
.Lm_bnz_taken:
        vLDAL pc
        vDEREFA
        vSTAL pc
        vJMP .Lm_vm
#:    else if (i == ENT) { *--sp = (int)bp; bp = sp; sp = sp - *pc++; }     // enter subroutine
.Lm_op_ent:
        vJNE_LI i, ENT, .Lm_op_adj
        vDECLW sp_, 1
        vLDAL sp_
        vLDBL bp_
        vSTWA_B
        vLDAL sp_
        vSTAL bp_
        vLDAL pc
        vDEREFA
        vMULAW  /* (int *) arithmetic scales by 8 */
        vSUBLA sp_
        vINCLW pc, 1
        vJMP .Lm_vm
#:    else if (i == ADJ) sp = sp + *pc++;                                   // stack adjust
.Lm_op_adj:
        vJNE_LI i, ADJ, .Lm_op_lev
        vLDAL pc
        vDEREFA
        vMULAW  /* (int *) arithmetic scales by 8 */
        vADDLA sp_
        vINCLW pc, 1
        vJMP .Lm_vm
#:    else if (i == LEV) { sp = bp; bp = (int *)*sp++; pc = (int *)*sp++; } // leave subroutine
.Lm_op_lev:
        vJNE_LI i, LEV, .Lm_op_li
        vLDAL bp_
        vSTAL sp_
        vLDAL sp_
        vDEREFAB
        vSTBL bp_
        vINCLW sp_, 1
        vLDAL sp_
        vDEREFAB
        vSTBL pc
        vINCLW sp_, 1
        vJMP .Lm_vm
#:    else if (i == LI)  a = *(int *)a;                                     // load int
.Lm_op_li:
        vJNE_LI i, LI, .Lm_op_lc
        vLDAL a
        vDEREFA
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == LC)  a = *(char *)a;                                    // load char
.Lm_op_lc:
        vJNE_LI i, LC, .Lm_op_si
        vLDAL a
        vLDSBA
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == SI)  *(int *)*sp++ = a;                                 // store int
.Lm_op_si:
        vJNE_LI i, SI_, .Lm_op_sc
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vLDAL a
        vSTWB_A
        vJMP .Lm_vm
#:    else if (i == SC)  a = *(char *)*sp++ = a;                            // store char
.Lm_op_sc:
        vJNE_LI i, SC, .Lm_op_psh
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vLDAL a
        vSTBB_A
        vSEXTBYTEA  /* value of the assignment is the stored char */
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == PSH) *--sp = a;                                         // push
.Lm_op_psh:
        vJNE_LI i, PSH, .Lm_op_or
        vDECLW sp_, 1
        vLDAL sp_
        vLDBL a
        vSTWA_B
        vJMP .Lm_vm

#:
#:    else if (i == OR)  a = *sp++ |  a;
.Lm_op_or:
        vJNE_LI i, OR_, .Lm_op_xor
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vORBL a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == XOR) a = *sp++ ^  a;
.Lm_op_xor:
        vJNE_LI i, XOR_, .Lm_op_and
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vXORBL a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == AND) a = *sp++ &  a;
.Lm_op_and:
        vJNE_LI i, AND_, .Lm_op_eq
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vANDBL a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == EQ)  a = *sp++ == a;
.Lm_op_eq:
        vJNE_LI i, EQ_, .Lm_op_ne
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vSETEQ a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == NE)  a = *sp++ != a;
.Lm_op_ne:
        vJNE_LI i, NE_, .Lm_op_lt
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vSETNE a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == LT)  a = *sp++ <  a;
.Lm_op_lt:
        vJNE_LI i, LT_, .Lm_op_gt
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vSETLT a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == GT)  a = *sp++ >  a;
.Lm_op_gt:
        vJNE_LI i, GT_, .Lm_op_le
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vSETGT a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == LE)  a = *sp++ <= a;
.Lm_op_le:
        vJNE_LI i, LE_, .Lm_op_ge
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vSETLE a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == GE)  a = *sp++ >= a;
.Lm_op_ge:
        vJNE_LI i, GE_, .Lm_op_shl
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vSETGE a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == SHL) a = *sp++ << a;
.Lm_op_shl:
        vJNE_LI i, SHL_, .Lm_op_shr
        vLDAL sp_
        vDEREFAC
        vINCLW sp_, 1
        vLDBL a
        vSHLCB
        vSTCL a
        vJMP .Lm_vm
#:    else if (i == SHR) a = *sp++ >> a;
.Lm_op_shr:
        vJNE_LI i, SHR_, .Lm_op_add
        vLDAL sp_
        vDEREFAC
        vINCLW sp_, 1
        vLDBL a
        vSARCB  /* arithmetic shift: values are signed */
        vSTCL a
        vJMP .Lm_vm
#:    else if (i == ADD) a = *sp++ +  a;
.Lm_op_add:
        vJNE_LI i, ADD, .Lm_op_sub
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vADDBL a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == SUB) a = *sp++ -  a;
.Lm_op_sub:
        vJNE_LI i, SUB, .Lm_op_mul
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vSUBBL a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == MUL) a = *sp++ *  a;
.Lm_op_mul:
        vJNE_LI i, MUL, .Lm_op_div
        vLDAL sp_
        vDEREFAB
        vINCLW sp_, 1
        vMULBL a
        vSTBL a
        vJMP .Lm_vm
#:    else if (i == DIV) a = *sp++ /  a;
.Lm_op_div:
        vJNE_LI i, DIV, .Lm_op_mod
        vLDBL sp_
        vDEREFBA
        vINCLW sp_, 1
        vDIVL a
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == MOD) a = *sp++ %  a;
.Lm_op_mod:
        vJNE_LI i, MOD_, .Lm_op_open
        vLDBL sp_
        vDEREFBA
        vINCLW sp_, 1
        vMODL a
        vSTCL a  /* remainder is in rdx */
        vJMP .Lm_vm

#:
#:    else if (i == OPEN) a = open((char *)sp[1], *sp);
.Lm_op_open:
        vJNE_LI i, OPEN, .Lm_op_read
        vLDAL sp_
        vARGMA 1, 1
        vARGMA 2, 0
        vCALLV open
        vRES32
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == READ) a = read(sp[2], (char *)sp[1], *sp);
.Lm_op_read:
        vJNE_LI i, READ, .Lm_op_clos
        vLDAL sp_
        vARGMA 1, 2
        vARGMA 2, 1
        vARGMA 3, 0
        vCALL read
        vRES
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == CLOS) a = close(*sp);
.Lm_op_clos:
        vJNE_LI i, CLOS, .Lm_op_prtf
        vLDAL sp_
        vARGMA 1, 0
        vCALL close
        vRES32
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == PRTF) { t = sp + pc[1]; a = printf((char *)t[-1], t[-2], t[-3], t[-4], t[-5], t[-6]); }
.Lm_op_prtf:
        vJNE_LI i, PRTF, .Lm_op_malc
        vLDAL pc
        vLDAF 1
        vMULAW  /* (int *) arithmetic scales by 8 */
        vADDAL sp_
        vSTAL t
        vLDAL t
        vARGMA 1, -1
        vARGMA 2, -2
        vARGMA 3, -3
        vARGMA 4, -4
        vARGMA 5, -5
        vARGMA 6, -6
        vCALLV printf
        vRES32
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == MALC) a = (int)malloc(*sp);
.Lm_op_malc:
        vJNE_LI i, MALC, .Lm_op_free
        vLDAL sp_
        vARGMA 1, 0
        vCALL malloc
        vRES
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == FREE) free((void *)*sp);
.Lm_op_free:
        vJNE_LI i, FREE, .Lm_op_mset
        vLDAL sp_
        vARGMA 1, 0
        vCALL free
        vRES
        vJMP .Lm_vm
#:    else if (i == MSET) a = (int)memset((char *)sp[2], sp[1], *sp);
.Lm_op_mset:
        vJNE_LI i, MSET, .Lm_op_mcmp
        vLDAL sp_
        vARGMA 1, 2
        vARGMA 2, 1
        vARGMA 3, 0
        vCALL memset
        vRES
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == MCMP) a = memcmp((char *)sp[2], (char *)sp[1], *sp);
.Lm_op_mcmp:
        vJNE_LI i, MCMP, .Lm_op_exit
        vLDAL sp_
        vARGMA 1, 2
        vARGMA 2, 1
        vARGMA 3, 0
        vCALL memcmp
        vRES32
        vSTAL a
        vJMP .Lm_vm
#:    else if (i == EXIT) { printf("exit(%d) cycle = %d\n", *sp, cycle); return *sp; }
.Lm_op_exit:
        vJNE_LI i, EXIT, .Lm_op_unknown
        vARGS 1, msg_exit
        vLDAL sp_
        vARGMA 2, 0
        vARGL 3, cycle
        vCALLV printf
        vRES
        vLDAL sp_
        vDEREFA
        vRET
#:    else { printf("unknown instruction = %d! cycle = %d\n", i, cycle); return -1; }
.Lm_op_unknown:
        vARGS 1, msg_unknown
        vARGL 2, i
        vARGL 3, cycle
        vCALLV printf
        vRES
        vRETI -1
#:  }
#:}

.section .note.GNU-stack,"",%progbits

.else
.include "arch/x86_64.s"
.endif

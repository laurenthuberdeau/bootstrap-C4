# c4.s - C in four functions (x86-64 assembly version)
#
# A line-by-line translation of c4.c (by Robert Swierczek) into x86-64
# assembly, intended to be reviewable against the original C source.
#
# Every line of c4.c appears exactly once, in order, as a comment
# prefixed with "#:", directly above the instruction sequence that
# implements it.  The original C source can therefore be recovered,
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
# Conventions (chosen for reviewability, not speed):
#   - Every C variable lives in memory: globals are labels in .bss,
#     locals are fixed rbp-relative stack slots named with equates
#     (e.g. "pp = -8" then "[rbp+pp]").
#   - "int" in c4.c is "long long" (8 bytes).  All values are 8 bytes.
#   - Expressions are evaluated with rax as the accumulator and rcx
#     (sometimes rdx) as a scratch register.  No value is ever kept in
#     a register across a call: every C statement starts by loading its
#     operands from memory and ends by storing its result to memory.
#   - Functions use the System V AMD64 calling convention: integer
#     args in rdi, rsi, rdx, rcx, r8, r9; result in rax; al = 0 before
#     variadic calls (printf, open).  The binary is freestanding: the
#     functions c4.c takes from libc (printf, malloc, open, read,
#     close, memset, memcmp, free, exit) are implemented at the bottom
#     of this file ("freestanding runtime") with direct Linux
#     syscalls, and _start replaces the C runtime.  printf supports
#     only what c4 needs: %d, %s and %c, with an optional width and
#     "." precision (digits or *).
#   - Character constants appear as decimal numbers with the character
#     in a comment (e.g. "cmp rax, 10" for '\n').
#   - GAS Intel syntax reserves some words as expression operators
#     (and, or, xor, eq, ne, lt, gt, le, ge, shl, shr, mod, all
#     case-insensitive) and register names (si).  Identifiers from
#     c4.c that collide with these get a trailing underscore in the
#     code: the global "le" is "le_", the tokens Or..Mod are Or_..Mod_,
#     and the opcodes OR..MOD and SI are OR_..MOD_ and SI_.  The C
#     source quoted in the comments keeps the original names.
#   - Instruction subset: mov, movsx, movzx, cdqe, cqo, push, pop,
#     add, sub, imul, idiv, neg, and, or, xor, shl, sar, cmp, test,
#     sete/setne/setl/setg/setle/setge, jmp, je/jne/jl/jle/jg/jge,
#     call, ret; the freestanding runtime additionally uses lea, div,
#     jns/jle and syscall.
#   - Assemble and link with:  gcc -nostdlib -static -no-pie c4.s -o c4

.intel_syntax noprefix

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
.align 8
#:char *p, *lp, // current position in source code
#:     *data;   // data/bss pointer
#:
p:      .space 8
lp:     .space 8
data:   .space 8
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
e:      .space 8
le_:    .space 8
id:     .space 8
sym:    .space 8
tk:     .space 8
ival:   .space 8
ty:     .space 8
loc:    .space 8
line:   .space 8
src:    .space 8
debug:  .space 8

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
        push rbp
        mov rbp, rsp
        sub rsp, 16
        pp = -8                      # char *pp;

#:
#:  while (tk = *p) {
.Lnx_while:
        mov rax, [p]
        movsx rax, byte ptr [rax]
        mov [tk], rax
        test rax, rax
        je .Lnx_end
#:    ++p;
        add qword ptr [p], 1
#:    if (tk == '\n') {
        cmp qword ptr [tk], 10       # '\n'
        jne .Lnx_not_nl
#:      if (src) {
        cmp qword ptr [src], 0
        je .Lnx_nl_done
#:        printf("%d: %.*s", line, p - lp, lp);
        mov edi, offset fmt_src
        mov rsi, [line]
        mov rdx, [p]
        sub rdx, [lp]
        mov rcx, [lp]
        xor eax, eax
        call printf
#:        lp = p;
        mov rax, [p]
        mov [lp], rax
#:        while (le < e) {
.Lnx_src_while:
        mov rax, [le_]
        cmp rax, [e]
        jge .Lnx_nl_done
#:          printf("%8.4s", &"LEA ,IMM ,JMP ,JSR ,BZ  ,BNZ ,ENT ,ADJ ,LEV ,LI  ,LC  ,SI  ,SC  ,PSH ,"
#:                           "OR  ,XOR ,AND ,EQ  ,NE  ,LT  ,GT  ,LE  ,GE  ,SHL ,SHR ,ADD ,SUB ,MUL ,DIV ,MOD ,"
#:                           "OPEN,READ,CLOS,PRTF,MALC,FREE,MSET,MCMP,EXIT,"[*++le * 5]);
        add qword ptr [le_], 8
        mov rax, [le_]
        mov rax, [rax]
        imul rax, rax, 5
        add rax, offset ops
        mov rsi, rax
        mov edi, offset fmt_ins
        xor eax, eax
        call printf
#:          if (*le <= ADJ) printf(" %d\n", *++le); else printf("\n");
        mov rax, [le_]
        mov rax, [rax]
        cmp rax, ADJ
        jg .Lnx_src_nl
        add qword ptr [le_], 8
        mov rax, [le_]
        mov rsi, [rax]
        mov edi, offset fmt_opval
        xor eax, eax
        call printf
        jmp .Lnx_src_while
.Lnx_src_nl:
        mov edi, offset fmt_nl
        xor eax, eax
        call printf
        jmp .Lnx_src_while
#:        }
#:      }
#:      ++line;
.Lnx_nl_done:
        add qword ptr [line], 1
        jmp .Lnx_while
#:    }
#:    else if (tk == '#') {
.Lnx_not_nl:
        cmp qword ptr [tk], 35       # '#'
        jne .Lnx_not_hash
#:      while (*p != 0 && *p != '\n') ++p;
.Lnx_hash_while:
        mov rax, [p]
        movsx rax, byte ptr [rax]
        test rax, rax
        je .Lnx_while
        cmp rax, 10                  # '\n'
        je .Lnx_while
        add qword ptr [p], 1
        jmp .Lnx_hash_while
#:    }
#:    else if ((tk >= 'a' && tk <= 'z') || (tk >= 'A' && tk <= 'Z') || tk == '_') {
.Lnx_not_hash:
        mov rax, [tk]
        cmp rax, 97                  # 'a'
        jl .Lnx_id_chk_upper
        cmp rax, 122                 # 'z'
        jle .Lnx_ident
.Lnx_id_chk_upper:
        cmp rax, 65                  # 'A'
        jl .Lnx_id_chk_under
        cmp rax, 90                  # 'Z'
        jle .Lnx_ident
.Lnx_id_chk_under:
        cmp rax, 95                  # '_'
        jne .Lnx_not_ident
.Lnx_ident:
#:      pp = p - 1;
        mov rax, [p]
        sub rax, 1
        mov [rbp+pp], rax
#:      while ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == '_')
.Lnx_id_while:
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 97                  # 'a'
        jl .Lnx_idw_upper
        cmp rax, 122                 # 'z'
        jle .Lnx_id_body
.Lnx_idw_upper:
        cmp rax, 65                  # 'A'
        jl .Lnx_idw_digit
        cmp rax, 90                  # 'Z'
        jle .Lnx_id_body
.Lnx_idw_digit:
        cmp rax, 48                  # '0'
        jl .Lnx_idw_under
        cmp rax, 57                  # '9'
        jle .Lnx_id_body
.Lnx_idw_under:
        cmp rax, 95                  # '_'
        jne .Lnx_id_hash
.Lnx_id_body:
#:        tk = tk * 147 + *p++;
        mov rax, [tk]
        imul rax, rax, 147
        mov rcx, [p]
        movsx rcx, byte ptr [rcx]
        add rax, rcx
        mov [tk], rax
        add qword ptr [p], 1
        jmp .Lnx_id_while
.Lnx_id_hash:
#:      tk = (tk << 6) + (p - pp);
        mov rax, [tk]
        shl rax, 6
        mov rcx, [p]
        sub rcx, [rbp+pp]
        add rax, rcx
        mov [tk], rax
#:      id = sym;
        mov rax, [sym]
        mov [id], rax
#:      while (id[Tk]) {
.Lnx_id_lookup:
        mov rax, [id]
        cmp qword ptr [rax+Tk*8], 0
        je .Lnx_id_new
#:        if (tk == id[Hash] && !memcmp((char *)id[Name], pp, p - pp)) { tk = id[Tk]; return; }
        mov rax, [tk]
        mov rcx, [id]
        cmp rax, [rcx+Hash*8]
        jne .Lnx_id_next
        mov rcx, [id]
        mov rdi, [rcx+Name*8]
        mov rsi, [rbp+pp]
        mov rdx, [p]
        sub rdx, [rbp+pp]
        call memcmp
        test eax, eax
        jne .Lnx_id_next
        mov rcx, [id]
        mov rax, [rcx+Tk*8]
        mov [tk], rax
        mov rsp, rbp
        pop rbp
        ret
#:        id = id + Idsz;
.Lnx_id_next:
        add qword ptr [id], Idsz*8
        jmp .Lnx_id_lookup
#:      }
#:      id[Name] = (int)pp;
#:      id[Hash] = tk;
#:      tk = id[Tk] = Id;
#:      return;
.Lnx_id_new:
        mov rax, [id]
        mov rcx, [rbp+pp]
        mov [rax+Name*8], rcx
        mov rcx, [tk]
        mov [rax+Hash*8], rcx
        mov qword ptr [rax+Tk*8], Id
        mov qword ptr [tk], Id
        mov rsp, rbp
        pop rbp
        ret
#:    }
#:    else if (tk >= '0' && tk <= '9') {
.Lnx_not_ident:
        mov rax, [tk]
        cmp rax, 48                  # '0'
        jl .Lnx_not_num
        cmp rax, 57                  # '9'
        jg .Lnx_not_num
#:      if (ival = tk - '0') { while (*p >= '0' && *p <= '9') ival = ival * 10 + *p++ - '0'; }
        sub rax, 48                  # '0'
        mov [ival], rax
        test rax, rax
        je .Lnx_num_hexoct
.Lnx_dec_while:
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 48                  # '0'
        jl .Lnx_num_done
        cmp rax, 57                  # '9'
        jg .Lnx_num_done
        mov rcx, [ival]
        imul rcx, rcx, 10
        add rcx, rax
        sub rcx, 48                  # '0'
        mov [ival], rcx
        add qword ptr [p], 1
        jmp .Lnx_dec_while
#:      else if (*p == 'x' || *p == 'X') {
.Lnx_num_hexoct:
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 120                 # 'x'
        je .Lnx_hex
        cmp rax, 88                  # 'X'
        je .Lnx_hex
        jmp .Lnx_oct
#:        while ((tk = *++p) && ((tk >= '0' && tk <= '9') || (tk >= 'a' && tk <= 'f') || (tk >= 'A' && tk <= 'F')))
.Lnx_hex:
        add qword ptr [p], 1
        mov rax, [p]
        movsx rax, byte ptr [rax]
        mov [tk], rax
        test rax, rax
        je .Lnx_num_done
        cmp rax, 48                  # '0'
        jl .Lnx_hex_lower
        cmp rax, 57                  # '9'
        jle .Lnx_hex_digit
.Lnx_hex_lower:
        cmp rax, 97                  # 'a'
        jl .Lnx_hex_upper
        cmp rax, 102                 # 'f'
        jle .Lnx_hex_digit
.Lnx_hex_upper:
        cmp rax, 65                  # 'A'
        jl .Lnx_num_done
        cmp rax, 70                  # 'F'
        jg .Lnx_num_done
#:          ival = ival * 16 + (tk & 15) + (tk >= 'A' ? 9 : 0);
.Lnx_hex_digit:
        mov rax, [ival]
        imul rax, rax, 16
        mov rcx, [tk]
        and rcx, 15
        add rax, rcx
        cmp qword ptr [tk], 65       # 'A'
        jl .Lnx_hex_no9
        add rax, 9
.Lnx_hex_no9:
        mov [ival], rax
        jmp .Lnx_hex
#:      }
#:      else { while (*p >= '0' && *p <= '7') ival = ival * 8 + *p++ - '0'; }
.Lnx_oct:
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 48                  # '0'
        jl .Lnx_num_done
        cmp rax, 55                  # '7'
        jg .Lnx_num_done
        mov rcx, [ival]
        imul rcx, rcx, 8
        add rcx, rax
        sub rcx, 48                  # '0'
        mov [ival], rcx
        add qword ptr [p], 1
        jmp .Lnx_oct
#:      tk = Num;
#:      return;
.Lnx_num_done:
        mov qword ptr [tk], Num
        mov rsp, rbp
        pop rbp
        ret
#:    }
#:    else if (tk == '/') {
.Lnx_not_num:
        cmp qword ptr [tk], 47       # '/'
        jne .Lnx_not_div
#:      if (*p == '/') {
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 47                  # '/'
        jne .Lnx_div_op
#:        ++p;
        add qword ptr [p], 1
#:        while (*p != 0 && *p != '\n') ++p;
.Lnx_cmt_while:
        mov rax, [p]
        movsx rax, byte ptr [rax]
        test rax, rax
        je .Lnx_while
        cmp rax, 10                  # '\n'
        je .Lnx_while
        add qword ptr [p], 1
        jmp .Lnx_cmt_while
#:      }
#:      else {
#:        tk = Div;
#:        return;
#:      }
.Lnx_div_op:
        mov qword ptr [tk], Div
        mov rsp, rbp
        pop rbp
        ret
#:    }
#:    else if (tk == '\'' || tk == '"') {
.Lnx_not_div:
        cmp qword ptr [tk], 39       # '\''
        je .Lnx_quote
        cmp qword ptr [tk], 34       # '"'
        jne .Lnx_not_quote
.Lnx_quote:
#:      pp = data;
        mov rax, [data]
        mov [rbp+pp], rax
#:      while (*p != 0 && *p != tk) {
.Lnx_str_while:
        mov rax, [p]
        movsx rax, byte ptr [rax]
        test rax, rax
        je .Lnx_str_done
        cmp rax, [tk]
        je .Lnx_str_done
#:        if ((ival = *p++) == '\\') {
        mov [ival], rax
        add qword ptr [p], 1
        cmp rax, 92                  # '\\'
        jne .Lnx_str_store
#:          if ((ival = *p++) == 'n') ival = '\n';
        mov rax, [p]
        movsx rax, byte ptr [rax]
        mov [ival], rax
        add qword ptr [p], 1
        cmp rax, 110                 # 'n'
        jne .Lnx_str_store
        mov qword ptr [ival], 10     # '\n'
#:        }
#:        if (tk == '"') *data++ = ival;
.Lnx_str_store:
        cmp qword ptr [tk], 34       # '"'
        jne .Lnx_str_while
        mov rax, [data]
        mov rcx, [ival]
        mov byte ptr [rax], cl
        add qword ptr [data], 1
        jmp .Lnx_str_while
#:      }
#:      ++p;
#:      if (tk == '"') ival = (int)pp; else tk = Num;
#:      return;
.Lnx_str_done:
        add qword ptr [p], 1
        cmp qword ptr [tk], 34       # '"'
        jne .Lnx_char_const
        mov rax, [rbp+pp]
        mov [ival], rax
        mov rsp, rbp
        pop rbp
        ret
.Lnx_char_const:
        mov qword ptr [tk], Num
        mov rsp, rbp
        pop rbp
        ret
#:    }
#:    else if (tk == '=') { if (*p == '=') { ++p; tk = Eq; } else tk = Assign; return; }
.Lnx_not_quote:
        cmp qword ptr [tk], 61       # '='
        jne .Lnx_not_assign
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 61                  # '='
        jne .Lnx_op_assign
        add qword ptr [p], 1
        mov qword ptr [tk], Eq_
        mov rsp, rbp
        pop rbp
        ret
.Lnx_op_assign:
        mov qword ptr [tk], Assign
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '+') { if (*p == '+') { ++p; tk = Inc; } else tk = Add; return; }
.Lnx_not_assign:
        cmp qword ptr [tk], 43       # '+'
        jne .Lnx_not_add
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 43                  # '+'
        jne .Lnx_op_add
        add qword ptr [p], 1
        mov qword ptr [tk], Inc
        mov rsp, rbp
        pop rbp
        ret
.Lnx_op_add:
        mov qword ptr [tk], Add
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '-') { if (*p == '-') { ++p; tk = Dec; } else tk = Sub; return; }
.Lnx_not_add:
        cmp qword ptr [tk], 45       # '-'
        jne .Lnx_not_sub
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 45                  # '-'
        jne .Lnx_op_sub
        add qword ptr [p], 1
        mov qword ptr [tk], Dec
        mov rsp, rbp
        pop rbp
        ret
.Lnx_op_sub:
        mov qword ptr [tk], Sub
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '!') { if (*p == '=') { ++p; tk = Ne; } return; }
.Lnx_not_sub:
        cmp qword ptr [tk], 33       # '!'
        jne .Lnx_not_bang
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 61                  # '='
        jne .Lnx_bang_ret
        add qword ptr [p], 1
        mov qword ptr [tk], Ne_
.Lnx_bang_ret:
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '<') { if (*p == '=') { ++p; tk = Le; } else if (*p == '<') { ++p; tk = Shl; } else tk = Lt; return; }
.Lnx_not_bang:
        cmp qword ptr [tk], 60       # '<'
        jne .Lnx_not_lt
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 61                  # '='
        jne .Lnx_lt_shl
        add qword ptr [p], 1
        mov qword ptr [tk], Le_
        mov rsp, rbp
        pop rbp
        ret
.Lnx_lt_shl:
        cmp rax, 60                  # '<'
        jne .Lnx_op_lt
        add qword ptr [p], 1
        mov qword ptr [tk], Shl_
        mov rsp, rbp
        pop rbp
        ret
.Lnx_op_lt:
        mov qword ptr [tk], Lt_
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '>') { if (*p == '=') { ++p; tk = Ge; } else if (*p == '>') { ++p; tk = Shr; } else tk = Gt; return; }
.Lnx_not_lt:
        cmp qword ptr [tk], 62       # '>'
        jne .Lnx_not_gt
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 61                  # '='
        jne .Lnx_gt_shr
        add qword ptr [p], 1
        mov qword ptr [tk], Ge_
        mov rsp, rbp
        pop rbp
        ret
.Lnx_gt_shr:
        cmp rax, 62                  # '>'
        jne .Lnx_op_gt
        add qword ptr [p], 1
        mov qword ptr [tk], Shr_
        mov rsp, rbp
        pop rbp
        ret
.Lnx_op_gt:
        mov qword ptr [tk], Gt_
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '|') { if (*p == '|') { ++p; tk = Lor; } else tk = Or; return; }
.Lnx_not_gt:
        cmp qword ptr [tk], 124      # '|'
        jne .Lnx_not_or
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 124                 # '|'
        jne .Lnx_op_or
        add qword ptr [p], 1
        mov qword ptr [tk], Lor
        mov rsp, rbp
        pop rbp
        ret
.Lnx_op_or:
        mov qword ptr [tk], Or_
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '&') { if (*p == '&') { ++p; tk = Lan; } else tk = And; return; }
.Lnx_not_or:
        cmp qword ptr [tk], 38       # '&'
        jne .Lnx_not_and
        mov rax, [p]
        movsx rax, byte ptr [rax]
        cmp rax, 38                  # '&'
        jne .Lnx_op_and
        add qword ptr [p], 1
        mov qword ptr [tk], Lan
        mov rsp, rbp
        pop rbp
        ret
.Lnx_op_and:
        mov qword ptr [tk], And_
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '^') { tk = Xor; return; }
.Lnx_not_and:
        cmp qword ptr [tk], 94       # '^'
        jne .Lnx_not_xor
        mov qword ptr [tk], Xor_
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '%') { tk = Mod; return; }
.Lnx_not_xor:
        cmp qword ptr [tk], 37       # '%'
        jne .Lnx_not_mod
        mov qword ptr [tk], Mod_
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '*') { tk = Mul; return; }
.Lnx_not_mod:
        cmp qword ptr [tk], 42       # '*'
        jne .Lnx_not_mul
        mov qword ptr [tk], Mul
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '[') { tk = Brak; return; }
.Lnx_not_mul:
        cmp qword ptr [tk], 91       # '['
        jne .Lnx_not_brak
        mov qword ptr [tk], Brak
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '?') { tk = Cond; return; }
.Lnx_not_brak:
        cmp qword ptr [tk], 63       # '?'
        jne .Lnx_not_cond
        mov qword ptr [tk], Cond
        mov rsp, rbp
        pop rbp
        ret
#:    else if (tk == '~' || tk == ';' || tk == '{' || tk == '}' || tk == '(' || tk == ')' || tk == ']' || tk == ',' || tk == ':') return;
.Lnx_not_cond:
        mov rax, [tk]
        cmp rax, 126                 # '~'
        je .Lnx_punct_ret
        cmp rax, 59                  # ';'
        je .Lnx_punct_ret
        cmp rax, 123                 # '{'
        je .Lnx_punct_ret
        cmp rax, 125                 # '}'
        je .Lnx_punct_ret
        cmp rax, 40                  # '('
        je .Lnx_punct_ret
        cmp rax, 41                  # ')'
        je .Lnx_punct_ret
        cmp rax, 93                  # ']'
        je .Lnx_punct_ret
        cmp rax, 44                  # ','
        je .Lnx_punct_ret
        cmp rax, 58                  # ':'
        jne .Lnx_while
.Lnx_punct_ret:
        mov rsp, rbp
        pop rbp
        ret
#:  }
#:}
.Lnx_end:
        mov rsp, rbp
        pop rbp
        ret

# ----------------------------------------------------------------------
#:
#:void expr(int lev)
#:{
#:  int t, *d;
# ----------------------------------------------------------------------
.globl expr
expr:
        push rbp
        mov rbp, rsp
        sub rsp, 32
        lev = -8                     # int lev; (argument)
        t   = -16                    # int t;
        d   = -24                    # int *d;
        mov [rbp+lev], rdi

#:
#:  if (!tk) { printf("%d: unexpected eof in expression\n", line); exit(-1); }
        cmp qword ptr [tk], 0
        jne .Lex_num
        mov edi, offset msg_eof
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
#:  else if (tk == Num) { *++e = IMM; *++e = ival; next(); ty = INT; }
.Lex_num:
        cmp qword ptr [tk], Num
        jne .Lex_str
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov rcx, [ival]
        mov [rax], rcx
        call next
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:  else if (tk == '"') {
.Lex_str:
        cmp qword ptr [tk], 34       # '"'
        jne .Lex_sizeof
#:    *++e = IMM; *++e = ival; next();
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov rcx, [ival]
        mov [rax], rcx
        call next
#:    while (tk == '"') next();
.Lex_str_while:
        cmp qword ptr [tk], 34       # '"'
        jne .Lex_str_align
        call next
        jmp .Lex_str_while
#:    data = (char *)((int)data + sizeof(int) & -sizeof(int)); ty = PTR;
.Lex_str_align:
        mov rax, [data]
        add rax, 8
        and rax, -8
        mov [data], rax
        mov qword ptr [ty], PTR
        jmp .Lex_climb
#:  }
#:  else if (tk == Sizeof) {
.Lex_sizeof:
        cmp qword ptr [tk], Sizeof
        jne .Lex_id
#:    next(); if (tk == '(') next(); else { printf("%d: open paren expected in sizeof\n", line); exit(-1); }
        call next
        cmp qword ptr [tk], 40       # '('
        je .Lex_szf_open
        mov edi, offset msg_op_szof
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_szf_open:
        call next
#:    ty = INT; if (tk == Int) next(); else if (tk == Char) { next(); ty = CHAR; }
        mov qword ptr [ty], INT
        cmp qword ptr [tk], Int
        jne .Lex_szf_char
        call next
        jmp .Lex_szf_mul
.Lex_szf_char:
        cmp qword ptr [tk], Char
        jne .Lex_szf_mul
        call next
        mov qword ptr [ty], CHAR
#:    while (tk == Mul) { next(); ty = ty + PTR; }
.Lex_szf_mul:
        cmp qword ptr [tk], Mul
        jne .Lex_szf_close
        call next
        add qword ptr [ty], PTR
        jmp .Lex_szf_mul
#:    if (tk == ')') next(); else { printf("%d: close paren expected in sizeof\n", line); exit(-1); }
.Lex_szf_close:
        cmp qword ptr [tk], 41       # ')'
        je .Lex_szf_emit
        mov edi, offset msg_cp_szof
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_szf_emit:
        call next
#:    *++e = IMM; *++e = (ty == CHAR) ? sizeof(char) : sizeof(int);
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov rcx, 8                   # sizeof(int)
        cmp qword ptr [ty], CHAR
        jne .Lex_szf_store
        mov rcx, 1                   # sizeof(char)
.Lex_szf_store:
        mov [rax], rcx
#:    ty = INT;
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:  }
#:  else if (tk == Id) {
.Lex_id:
        cmp qword ptr [tk], Id
        jne .Lex_paren
#:    d = id; next();
        mov rax, [id]
        mov [rbp+d], rax
        call next
#:    if (tk == '(') {
        cmp qword ptr [tk], 40       # '('
        jne .Lex_id_num
#:      next();
        call next
#:      t = 0;
        mov qword ptr [rbp+t], 0
#:      while (tk != ')') { expr(Assign); *++e = PSH; ++t; if (tk == ',') next(); }
.Lex_call_args:
        cmp qword ptr [tk], 41       # ')'
        je .Lex_call_done
        mov edi, Assign
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [rbp+t], 1
        cmp qword ptr [tk], 44       # ','
        jne .Lex_call_args
        call next
        jmp .Lex_call_args
.Lex_call_done:
#:      next();
        call next
#:      if (d[Class] == Sys) *++e = d[Val];
        mov rax, [rbp+d]
        cmp qword ptr [rax+Class*8], Sys
        jne .Lex_call_fun
        mov rcx, [rax+Val*8]
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        jmp .Lex_call_adj
#:      else if (d[Class] == Fun) { *++e = JSR; *++e = d[Val]; }
.Lex_call_fun:
        cmp qword ptr [rax+Class*8], Fun
        jne .Lex_call_err
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], JSR
        mov rcx, [rbp+d]
        mov rcx, [rcx+Val*8]
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        jmp .Lex_call_adj
#:      else { printf("%d: bad function call\n", line); exit(-1); }
.Lex_call_err:
        mov edi, offset msg_bad_call
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
#:      if (t) { *++e = ADJ; *++e = t; }
.Lex_call_adj:
        cmp qword ptr [rbp+t], 0
        je .Lex_call_ty
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], ADJ
        mov rcx, [rbp+t]
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:      ty = d[Type];
.Lex_call_ty:
        mov rax, [rbp+d]
        mov rax, [rax+Type*8]
        mov [ty], rax
        jmp .Lex_climb
#:    }
#:    else if (d[Class] == Num) { *++e = IMM; *++e = d[Val]; ty = INT; }
.Lex_id_num:
        mov rax, [rbp+d]
        cmp qword ptr [rax+Class*8], Num
        jne .Lex_id_var
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        mov rcx, [rbp+d]
        mov rcx, [rcx+Val*8]
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else {
#:      if (d[Class] == Loc) { *++e = LEA; *++e = loc - d[Val]; }
.Lex_id_var:
        mov rax, [rbp+d]
        cmp qword ptr [rax+Class*8], Loc
        jne .Lex_id_glo
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LEA
        mov rax, [loc]
        mov rcx, [rbp+d]
        sub rax, [rcx+Val*8]
        add qword ptr [e], 8
        mov rcx, [e]
        mov [rcx], rax
        jmp .Lex_id_load
#:      else if (d[Class] == Glo) { *++e = IMM; *++e = d[Val]; }
.Lex_id_glo:
        mov rax, [rbp+d]
        cmp qword ptr [rax+Class*8], Glo
        jne .Lex_id_undef
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        mov rcx, [rbp+d]
        mov rcx, [rcx+Val*8]
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        jmp .Lex_id_load
#:      else { printf("%d: undefined variable\n", line); exit(-1); }
.Lex_id_undef:
        mov edi, offset msg_undef_var
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
#:      *++e = ((ty = d[Type]) == CHAR) ? LC : LI;
.Lex_id_load:
        mov rax, [rbp+d]
        mov rax, [rax+Type*8]
        mov [ty], rax
        mov rcx, LI
        cmp rax, CHAR
        jne .Lex_id_emit_load
        mov rcx, LC
.Lex_id_emit_load:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        jmp .Lex_climb
#:    }
#:  }
#:  else if (tk == '(') {
.Lex_paren:
        cmp qword ptr [tk], 40       # '('
        jne .Lex_deref
#:    next();
        call next
#:    if (tk == Int || tk == Char) {
        cmp qword ptr [tk], Int
        je .Lex_cast
        cmp qword ptr [tk], Char
        jne .Lex_group
#:      t = (tk == Int) ? INT : CHAR; next();
.Lex_cast:
        mov rax, INT
        cmp qword ptr [tk], Int
        je .Lex_cast_t
        mov rax, CHAR
.Lex_cast_t:
        mov [rbp+t], rax
        call next
#:      while (tk == Mul) { next(); t = t + PTR; }
.Lex_cast_mul:
        cmp qword ptr [tk], Mul
        jne .Lex_cast_close
        call next
        add qword ptr [rbp+t], PTR
        jmp .Lex_cast_mul
#:      if (tk == ')') next(); else { printf("%d: bad cast\n", line); exit(-1); }
.Lex_cast_close:
        cmp qword ptr [tk], 41       # ')'
        je .Lex_cast_ok
        mov edi, offset msg_bad_cast
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_cast_ok:
        call next
#:      expr(Inc);
        mov edi, Inc
        call expr
#:      ty = t;
        mov rax, [rbp+t]
        mov [ty], rax
        jmp .Lex_climb
#:    }
#:    else {
#:      expr(Assign);
.Lex_group:
        mov edi, Assign
        call expr
#:      if (tk == ')') next(); else { printf("%d: close paren expected\n", line); exit(-1); }
        cmp qword ptr [tk], 41       # ')'
        je .Lex_group_ok
        mov edi, offset msg_cp_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_group_ok:
        call next
        jmp .Lex_climb
#:    }
#:  }
#:  else if (tk == Mul) {
.Lex_deref:
        cmp qword ptr [tk], Mul
        jne .Lex_addrof
#:    next(); expr(Inc);
        call next
        mov edi, Inc
        call expr
#:    if (ty > INT) ty = ty - PTR; else { printf("%d: bad dereference\n", line); exit(-1); }
        cmp qword ptr [ty], INT
        jg .Lex_deref_ok
        mov edi, offset msg_bad_deref
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_deref_ok:
        sub qword ptr [ty], PTR
#:    *++e = (ty == CHAR) ? LC : LI;
        mov rcx, LI
        cmp qword ptr [ty], CHAR
        jne .Lex_deref_emit
        mov rcx, LC
.Lex_deref_emit:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        jmp .Lex_climb
#:  }
#:  else if (tk == And) {
.Lex_addrof:
        cmp qword ptr [tk], And_
        jne .Lex_not
#:    next(); expr(Inc);
        call next
        mov edi, Inc
        call expr
#:    if (*e == LC || *e == LI) --e; else { printf("%d: bad address-of\n", line); exit(-1); }
        mov rax, [e]
        mov rax, [rax]
        cmp rax, LC
        je .Lex_addr_ok
        cmp rax, LI
        je .Lex_addr_ok
        mov edi, offset msg_bad_addr
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_addr_ok:
        sub qword ptr [e], 8
#:    ty = ty + PTR;
        add qword ptr [ty], PTR
        jmp .Lex_climb
#:  }
#:  else if (tk == '!') { next(); expr(Inc); *++e = PSH; *++e = IMM; *++e = 0; *++e = EQ; ty = INT; }
.Lex_not:
        cmp qword ptr [tk], 33       # '!'
        jne .Lex_bnot
        call next
        mov edi, Inc
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], 0
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], EQ_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:  else if (tk == '~') { next(); expr(Inc); *++e = PSH; *++e = IMM; *++e = -1; *++e = XOR; ty = INT; }
.Lex_bnot:
        cmp qword ptr [tk], 126      # '~'
        jne .Lex_pos
        call next
        mov edi, Inc
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], -1
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], XOR_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:  else if (tk == Add) { next(); expr(Inc); ty = INT; }
.Lex_pos:
        cmp qword ptr [tk], Add
        jne .Lex_neg
        call next
        mov edi, Inc
        call expr
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:  else if (tk == Sub) {
.Lex_neg:
        cmp qword ptr [tk], Sub
        jne .Lex_predec
#:    next(); *++e = IMM;
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
#:    if (tk == Num) { *++e = -ival; next(); } else { *++e = -1; *++e = PSH; expr(Inc); *++e = MUL; }
        cmp qword ptr [tk], Num
        jne .Lex_neg_expr
        mov rcx, [ival]
        neg rcx
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        call next
        jmp .Lex_neg_done
.Lex_neg_expr:
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], -1
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Inc
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], MUL
#:    ty = INT;
.Lex_neg_done:
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:  }
#:  else if (tk == Inc || tk == Dec) {
.Lex_predec:
        cmp qword ptr [tk], Inc
        je .Lex_pre
        cmp qword ptr [tk], Dec
        jne .Lex_bad_expr
.Lex_pre:
#:    t = tk; next(); expr(Inc);
        mov rax, [tk]
        mov [rbp+t], rax
        call next
        mov edi, Inc
        call expr
#:    if (*e == LC) { *e = PSH; *++e = LC; }
        mov rax, [e]
        mov rcx, [rax]
        cmp rcx, LC
        jne .Lex_pre_li
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LC
        jmp .Lex_pre_emit
#:    else if (*e == LI) { *e = PSH; *++e = LI; }
.Lex_pre_li:
        cmp rcx, LI
        jne .Lex_pre_err
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LI
        jmp .Lex_pre_emit
#:    else { printf("%d: bad lvalue in pre-increment\n", line); exit(-1); }
.Lex_pre_err:
        mov edi, offset msg_lval_pre
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_pre_emit:
#:    *++e = PSH;
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
#:    *++e = IMM; *++e = (ty > PTR) ? sizeof(int) : sizeof(char);
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        mov rcx, 8                   # sizeof(int)
        cmp qword ptr [ty], PTR
        jg .Lex_pre_size
        mov rcx, 1                   # sizeof(char)
.Lex_pre_size:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:    *++e = (t == Inc) ? ADD : SUB;
        mov rcx, ADD
        cmp qword ptr [rbp+t], Inc
        je .Lex_pre_addsub
        mov rcx, SUB
.Lex_pre_addsub:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:    *++e = (ty == CHAR) ? SC : SI;
        mov rcx, SI_
        cmp qword ptr [ty], CHAR
        jne .Lex_pre_store
        mov rcx, SC
.Lex_pre_store:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        jmp .Lex_climb
#:  }
#:  else { printf("%d: bad expression\n", line); exit(-1); }
.Lex_bad_expr:
        mov edi, offset msg_bad_expr
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit

#:
#:  while (tk >= lev) { // "precedence climbing" or "Top Down Operator Precedence" method
.Lex_climb:
        mov rax, [tk]
        cmp rax, [rbp+lev]
        jl .Lex_done
#:    t = ty;
        mov rax, [ty]
        mov [rbp+t], rax
#:    if (tk == Assign) {
        cmp qword ptr [tk], Assign
        jne .Lex_cond
#:      next();
        call next
#:      if (*e == LC || *e == LI) *e = PSH; else { printf("%d: bad lvalue in assignment\n", line); exit(-1); }
        mov rax, [e]
        mov rcx, [rax]
        cmp rcx, LC
        je .Lex_asgn_ok
        cmp rcx, LI
        je .Lex_asgn_ok
        mov edi, offset msg_lval_asgn
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_asgn_ok:
        mov qword ptr [rax], PSH
#:      expr(Assign); *++e = ((ty = t) == CHAR) ? SC : SI;
        mov edi, Assign
        call expr
        mov rax, [rbp+t]
        mov [ty], rax
        mov rcx, SI_
        cmp rax, CHAR
        jne .Lex_asgn_emit
        mov rcx, SC
.Lex_asgn_emit:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        jmp .Lex_climb
#:    }
#:    else if (tk == Cond) {
.Lex_cond:
        cmp qword ptr [tk], Cond
        jne .Lex_lor
#:      next();
        call next
#:      *++e = BZ; d = ++e;
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], BZ
        add qword ptr [e], 8
        mov rax, [e]
        mov [rbp+d], rax
#:      expr(Assign);
        mov edi, Assign
        call expr
#:      if (tk == ':') next(); else { printf("%d: conditional missing colon\n", line); exit(-1); }
        cmp qword ptr [tk], 58       # ':'
        je .Lex_cond_colon
        mov edi, offset msg_cond_colon
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_cond_colon:
        call next
#:      *d = (int)(e + 3); *++e = JMP; d = ++e;
        mov rax, [e]
        add rax, 24
        mov rcx, [rbp+d]
        mov [rcx], rax
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], JMP
        add qword ptr [e], 8
        mov rax, [e]
        mov [rbp+d], rax
#:      expr(Cond);
        mov edi, Cond
        call expr
#:      *d = (int)(e + 1);
        mov rax, [e]
        add rax, 8
        mov rcx, [rbp+d]
        mov [rcx], rax
        jmp .Lex_climb
#:    }
#:    else if (tk == Lor) { next(); *++e = BNZ; d = ++e; expr(Lan); *d = (int)(e + 1); ty = INT; }
.Lex_lor:
        cmp qword ptr [tk], Lor
        jne .Lex_lan
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], BNZ
        add qword ptr [e], 8
        mov rax, [e]
        mov [rbp+d], rax
        mov edi, Lan
        call expr
        mov rax, [e]
        add rax, 8
        mov rcx, [rbp+d]
        mov [rcx], rax
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Lan) { next(); *++e = BZ;  d = ++e; expr(Or);  *d = (int)(e + 1); ty = INT; }
.Lex_lan:
        cmp qword ptr [tk], Lan
        jne .Lex_or
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], BZ
        add qword ptr [e], 8
        mov rax, [e]
        mov [rbp+d], rax
        mov edi, Or_
        call expr
        mov rax, [e]
        add rax, 8
        mov rcx, [rbp+d]
        mov [rcx], rax
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Or)  { next(); *++e = PSH; expr(Xor); *++e = OR;  ty = INT; }
.Lex_or:
        cmp qword ptr [tk], Or_
        jne .Lex_xor
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Xor_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], OR_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Xor) { next(); *++e = PSH; expr(And); *++e = XOR; ty = INT; }
.Lex_xor:
        cmp qword ptr [tk], Xor_
        jne .Lex_and
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, And_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], XOR_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == And) { next(); *++e = PSH; expr(Eq);  *++e = AND; ty = INT; }
.Lex_and:
        cmp qword ptr [tk], And_
        jne .Lex_eq
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Eq_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], AND_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Eq)  { next(); *++e = PSH; expr(Lt);  *++e = EQ;  ty = INT; }
.Lex_eq:
        cmp qword ptr [tk], Eq_
        jne .Lex_ne
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Lt_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], EQ_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Ne)  { next(); *++e = PSH; expr(Lt);  *++e = NE;  ty = INT; }
.Lex_ne:
        cmp qword ptr [tk], Ne_
        jne .Lex_lt
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Lt_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], NE_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Lt)  { next(); *++e = PSH; expr(Shl); *++e = LT;  ty = INT; }
.Lex_lt:
        cmp qword ptr [tk], Lt_
        jne .Lex_gt
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Shl_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LT_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Gt)  { next(); *++e = PSH; expr(Shl); *++e = GT;  ty = INT; }
.Lex_gt:
        cmp qword ptr [tk], Gt_
        jne .Lex_le
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Shl_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], GT_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Le)  { next(); *++e = PSH; expr(Shl); *++e = LE;  ty = INT; }
.Lex_le:
        cmp qword ptr [tk], Le_
        jne .Lex_ge
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Shl_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LE_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Ge)  { next(); *++e = PSH; expr(Shl); *++e = GE;  ty = INT; }
.Lex_ge:
        cmp qword ptr [tk], Ge_
        jne .Lex_shl
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Shl_
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], GE_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Shl) { next(); *++e = PSH; expr(Add); *++e = SHL; ty = INT; }
.Lex_shl:
        cmp qword ptr [tk], Shl_
        jne .Lex_shr
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Add
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], SHL_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Shr) { next(); *++e = PSH; expr(Add); *++e = SHR; ty = INT; }
.Lex_shr:
        cmp qword ptr [tk], Shr_
        jne .Lex_add
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Add
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], SHR_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Add) {
.Lex_add:
        cmp qword ptr [tk], Add
        jne .Lex_sub
#:      next(); *++e = PSH; expr(Mul);
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Mul
        call expr
#:      if ((ty = t) > PTR) { *++e = PSH; *++e = IMM; *++e = sizeof(int); *++e = MUL;  }
        mov rax, [rbp+t]
        mov [ty], rax
        cmp rax, PTR
        jle .Lex_add_emit
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], 8       # sizeof(int)
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], MUL
#:      *++e = ADD;
.Lex_add_emit:
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], ADD
        jmp .Lex_climb
#:    }
#:    else if (tk == Sub) {
.Lex_sub:
        cmp qword ptr [tk], Sub
        jne .Lex_mul
#:      next(); *++e = PSH; expr(Mul);
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Mul
        call expr
#:      if (t > PTR && t == ty) { *++e = SUB; *++e = PSH; *++e = IMM; *++e = sizeof(int); *++e = DIV; ty = INT; }
        mov rax, [rbp+t]
        cmp rax, PTR
        jle .Lex_sub_ptr_int
        cmp rax, [ty]
        jne .Lex_sub_ptr_int
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], SUB
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], 8       # sizeof(int)
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], DIV
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:      else if ((ty = t) > PTR) { *++e = PSH; *++e = IMM; *++e = sizeof(int); *++e = MUL; *++e = SUB; }
.Lex_sub_ptr_int:
        mov rax, [rbp+t]
        mov [ty], rax
        cmp rax, PTR
        jle .Lex_sub_plain
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], 8       # sizeof(int)
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], MUL
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], SUB
        jmp .Lex_climb
#:      else *++e = SUB;
.Lex_sub_plain:
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], SUB
        jmp .Lex_climb
#:    }
#:    else if (tk == Mul) { next(); *++e = PSH; expr(Inc); *++e = MUL; ty = INT; }
.Lex_mul:
        cmp qword ptr [tk], Mul
        jne .Lex_div
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Inc
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], MUL
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Div) { next(); *++e = PSH; expr(Inc); *++e = DIV; ty = INT; }
.Lex_div:
        cmp qword ptr [tk], Div
        jne .Lex_mod
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Inc
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], DIV
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Mod) { next(); *++e = PSH; expr(Inc); *++e = MOD; ty = INT; }
.Lex_mod:
        cmp qword ptr [tk], Mod_
        jne .Lex_post
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Inc
        call expr
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], MOD_
        mov qword ptr [ty], INT
        jmp .Lex_climb
#:    else if (tk == Inc || tk == Dec) {
.Lex_post:
        cmp qword ptr [tk], Inc
        je .Lex_post_go
        cmp qword ptr [tk], Dec
        je .Lex_post_go
        jmp .Lex_brak
.Lex_post_go:
#:      if (*e == LC) { *e = PSH; *++e = LC; }
        mov rax, [e]
        mov rcx, [rax]
        cmp rcx, LC
        jne .Lex_post_li
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LC
        jmp .Lex_post_emit
#:      else if (*e == LI) { *e = PSH; *++e = LI; }
.Lex_post_li:
        cmp rcx, LI
        jne .Lex_post_err
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LI
        jmp .Lex_post_emit
#:      else { printf("%d: bad lvalue in post-increment\n", line); exit(-1); }
.Lex_post_err:
        mov edi, offset msg_lval_post
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_post_emit:
#:      *++e = PSH; *++e = IMM; *++e = (ty > PTR) ? sizeof(int) : sizeof(char);
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        mov rcx, 8                   # sizeof(int)
        cmp qword ptr [ty], PTR
        jg .Lex_post_size1
        mov rcx, 1                   # sizeof(char)
.Lex_post_size1:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:      *++e = (tk == Inc) ? ADD : SUB;
        mov rcx, ADD
        cmp qword ptr [tk], Inc
        je .Lex_post_addsub
        mov rcx, SUB
.Lex_post_addsub:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:      *++e = (ty == CHAR) ? SC : SI;
        mov rcx, SI_
        cmp qword ptr [ty], CHAR
        jne .Lex_post_store
        mov rcx, SC
.Lex_post_store:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:      *++e = PSH; *++e = IMM; *++e = (ty > PTR) ? sizeof(int) : sizeof(char);
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        mov rcx, 8                   # sizeof(int)
        cmp qword ptr [ty], PTR
        jg .Lex_post_size2
        mov rcx, 1                   # sizeof(char)
.Lex_post_size2:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:      *++e = (tk == Inc) ? SUB : ADD;
        mov rcx, SUB
        cmp qword ptr [tk], Inc
        je .Lex_post_subadd
        mov rcx, ADD
.Lex_post_subadd:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:      next();
        call next
        jmp .Lex_climb
#:    }
#:    else if (tk == Brak) {
.Lex_brak:
        cmp qword ptr [tk], Brak
        jne .Lex_bad_tk
#:      next(); *++e = PSH; expr(Assign);
        call next
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        mov edi, Assign
        call expr
#:      if (tk == ']') next(); else { printf("%d: close bracket expected\n", line); exit(-1); }
        cmp qword ptr [tk], 93       # ']'
        je .Lex_brak_ok
        mov edi, offset msg_cb_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_brak_ok:
        call next
#:      if (t > PTR) { *++e = PSH; *++e = IMM; *++e = sizeof(int); *++e = MUL;  }
        mov rax, [rbp+t]
        cmp rax, PTR
        jle .Lex_brak_chk
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], PSH
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], IMM
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], 8       # sizeof(int)
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], MUL
        jmp .Lex_brak_add
#:      else if (t < PTR) { printf("%d: pointer type expected\n", line); exit(-1); }
.Lex_brak_chk:
        cmp rax, PTR
        je .Lex_brak_add
        mov edi, offset msg_ptr_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lex_brak_add:
#:      *++e = ADD;
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], ADD
#:      *++e = ((ty = t - PTR) == CHAR) ? LC : LI;
        mov rax, [rbp+t]
        sub rax, PTR
        mov [ty], rax
        mov rcx, LI
        cmp rax, CHAR
        jne .Lex_brak_load
        mov rcx, LC
.Lex_brak_load:
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
        jmp .Lex_climb
#:    }
#:    else { printf("%d: compiler error tk=%d\n", line, tk); exit(-1); }
.Lex_bad_tk:
        mov edi, offset msg_comp_err
        mov rsi, [line]
        mov rdx, [tk]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
#:  }
#:}
.Lex_done:
        mov rsp, rbp
        pop rbp
        ret

# ----------------------------------------------------------------------
#:
#:void stmt()
#:{
#:  int *a, *b;
# ----------------------------------------------------------------------
.globl stmt
stmt:
        push rbp
        mov rbp, rsp
        sub rsp, 16
        a = -8                       # int *a;
        b = -16                      # int *b;

#:
#:  if (tk == If) {
        cmp qword ptr [tk], If
        jne .Lst_while
#:    next();
        call next
#:    if (tk == '(') next(); else { printf("%d: open paren expected\n", line); exit(-1); }
        cmp qword ptr [tk], 40       # '('
        je .Lst_if_open
        mov edi, offset msg_op_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lst_if_open:
        call next
#:    expr(Assign);
        mov edi, Assign
        call expr
#:    if (tk == ')') next(); else { printf("%d: close paren expected\n", line); exit(-1); }
        cmp qword ptr [tk], 41       # ')'
        je .Lst_if_close
        mov edi, offset msg_cp_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lst_if_close:
        call next
#:    *++e = BZ; b = ++e;
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], BZ
        add qword ptr [e], 8
        mov rax, [e]
        mov [rbp+b], rax
#:    stmt();
        call stmt
#:    if (tk == Else) {
        cmp qword ptr [tk], Else
        jne .Lst_if_end
#:      *b = (int)(e + 3); *++e = JMP; b = ++e;
        mov rax, [e]
        add rax, 24
        mov rcx, [rbp+b]
        mov [rcx], rax
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], JMP
        add qword ptr [e], 8
        mov rax, [e]
        mov [rbp+b], rax
#:      next();
        call next
#:      stmt();
        call stmt
#:    }
#:    *b = (int)(e + 1);
.Lst_if_end:
        mov rax, [e]
        add rax, 8
        mov rcx, [rbp+b]
        mov [rcx], rax
        mov rsp, rbp
        pop rbp
        ret
#:  }
#:  else if (tk == While) {
.Lst_while:
        cmp qword ptr [tk], While
        jne .Lst_return
#:    next();
        call next
#:    a = e + 1;
        mov rax, [e]
        add rax, 8
        mov [rbp+a], rax
#:    if (tk == '(') next(); else { printf("%d: open paren expected\n", line); exit(-1); }
        cmp qword ptr [tk], 40       # '('
        je .Lst_wh_open
        mov edi, offset msg_op_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lst_wh_open:
        call next
#:    expr(Assign);
        mov edi, Assign
        call expr
#:    if (tk == ')') next(); else { printf("%d: close paren expected\n", line); exit(-1); }
        cmp qword ptr [tk], 41       # ')'
        je .Lst_wh_close
        mov edi, offset msg_cp_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lst_wh_close:
        call next
#:    *++e = BZ; b = ++e;
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], BZ
        add qword ptr [e], 8
        mov rax, [e]
        mov [rbp+b], rax
#:    stmt();
        call stmt
#:    *++e = JMP; *++e = (int)a;
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], JMP
        mov rcx, [rbp+a]
        add qword ptr [e], 8
        mov rax, [e]
        mov [rax], rcx
#:    *b = (int)(e + 1);
        mov rax, [e]
        add rax, 8
        mov rcx, [rbp+b]
        mov [rcx], rax
        mov rsp, rbp
        pop rbp
        ret
#:  }
#:  else if (tk == Return) {
.Lst_return:
        cmp qword ptr [tk], Return
        jne .Lst_block
#:    next();
        call next
#:    if (tk != ';') expr(Assign);
        cmp qword ptr [tk], 59       # ';'
        je .Lst_ret_lev
        mov edi, Assign
        call expr
.Lst_ret_lev:
#:    *++e = LEV;
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LEV
#:    if (tk == ';') next(); else { printf("%d: semicolon expected\n", line); exit(-1); }
        cmp qword ptr [tk], 59       # ';'
        je .Lst_ret_semi
        mov edi, offset msg_semi_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lst_ret_semi:
        call next
        mov rsp, rbp
        pop rbp
        ret
#:  }
#:  else if (tk == '{') {
.Lst_block:
        cmp qword ptr [tk], 123      # '{'
        jne .Lst_semi
#:    next();
        call next
#:    while (tk != '}') stmt();
.Lst_block_while:
        cmp qword ptr [tk], 125      # '}'
        je .Lst_block_done
        call stmt
        jmp .Lst_block_while
.Lst_block_done:
#:    next();
        call next
        mov rsp, rbp
        pop rbp
        ret
#:  }
#:  else if (tk == ';') {
.Lst_semi:
        cmp qword ptr [tk], 59       # ';'
        jne .Lst_expr
#:    next();
        call next
        mov rsp, rbp
        pop rbp
        ret
#:  }
#:  else {
#:    expr(Assign);
.Lst_expr:
        mov edi, Assign
        call expr
#:    if (tk == ';') next(); else { printf("%d: semicolon expected\n", line); exit(-1); }
        cmp qword ptr [tk], 59       # ';'
        je .Lst_expr_semi
        mov edi, offset msg_semi_exp
        mov rsi, [line]
        xor eax, eax
        call printf
        mov edi, -1
        call exit
.Lst_expr_semi:
        call next
        mov rsp, rbp
        pop rbp
        ret
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
        push rbp
        mov rbp, rsp
        sub rsp, 112
        argc   = -8                  # int argc;   (argument)
        argv   = -16                 # char **argv; (argument)
        fd     = -24                 # int fd;
        bt     = -32                 # int bt;
        ty_    = -40                 # int ty;
        poolsz = -48                 # int poolsz;
        idmain = -56                 # int *idmain;
        pc     = -64                 # int *pc;
        sp_    = -72                 # int *sp;
        bp_    = -80                 # int *bp;
        a      = -88                 # int a;
        cycle  = -96                 # int cycle;
        i      = -104                # int i;
        t      = -112                # int *t;
        mov [rbp+argc], rdi
        mov [rbp+argv], rsi

#:
#:  --argc; ++argv;
        sub qword ptr [rbp+argc], 1
        add qword ptr [rbp+argv], 8
#:  if (argc > 0 && **argv == '-' && (*argv)[1] == 's') { src = 1; --argc; ++argv; }
        cmp qword ptr [rbp+argc], 0
        jle .Lm_chk_d
        mov rax, [rbp+argv]
        mov rax, [rax]
        movsx rcx, byte ptr [rax]
        cmp rcx, 45                  # '-'
        jne .Lm_chk_d
        movsx rcx, byte ptr [rax+1]
        cmp rcx, 115                 # 's'
        jne .Lm_chk_d
        mov qword ptr [src], 1
        sub qword ptr [rbp+argc], 1
        add qword ptr [rbp+argv], 8
#:  if (argc > 0 && **argv == '-' && (*argv)[1] == 'd') { debug = 1; --argc; ++argv; }
.Lm_chk_d:
        cmp qword ptr [rbp+argc], 0
        jle .Lm_usage_chk
        mov rax, [rbp+argv]
        mov rax, [rax]
        movsx rcx, byte ptr [rax]
        cmp rcx, 45                  # '-'
        jne .Lm_usage_chk
        movsx rcx, byte ptr [rax+1]
        cmp rcx, 100                 # 'd'
        jne .Lm_usage_chk
        mov qword ptr [debug], 1
        sub qword ptr [rbp+argc], 1
        add qword ptr [rbp+argv], 8
#:  if (argc < 1) { printf("usage: c4 [-s] [-d] file ...\n"); return -1; }
.Lm_usage_chk:
        cmp qword ptr [rbp+argc], 1
        jge .Lm_open_file
        mov edi, offset msg_usage
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:
#:  if ((fd = open(*argv, 0)) < 0) { printf("could not open(%s)\n", *argv); return -1; }
.Lm_open_file:
        mov rax, [rbp+argv]
        mov rdi, [rax]
        xor esi, esi
        xor eax, eax
        call open
        cdqe
        mov [rbp+fd], rax
        cmp rax, 0
        jge .Lm_pool
        mov edi, offset msg_open
        mov rax, [rbp+argv]
        mov rsi, [rax]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:
#:  poolsz = 256*1024; // arbitrary size
.Lm_pool:
        mov qword ptr [rbp+poolsz], 256*1024
#:  if (!(sym = malloc(poolsz))) { printf("could not malloc(%d) symbol area\n", poolsz); return -1; }
        mov rdi, [rbp+poolsz]
        call malloc
        mov [sym], rax
        test rax, rax
        jne .Lm_m_text
        mov edi, offset msg_m_sym
        mov rsi, [rbp+poolsz]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:  if (!(le = e = malloc(poolsz))) { printf("could not malloc(%d) text area\n", poolsz); return -1; }
.Lm_m_text:
        mov rdi, [rbp+poolsz]
        call malloc
        mov [e], rax
        mov [le_], rax
        test rax, rax
        jne .Lm_m_data
        mov edi, offset msg_m_text
        mov rsi, [rbp+poolsz]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:  if (!(data = malloc(poolsz))) { printf("could not malloc(%d) data area\n", poolsz); return -1; }
.Lm_m_data:
        mov rdi, [rbp+poolsz]
        call malloc
        mov [data], rax
        test rax, rax
        jne .Lm_m_stack
        mov edi, offset msg_m_data
        mov rsi, [rbp+poolsz]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:  if (!(sp = malloc(poolsz))) { printf("could not malloc(%d) stack area\n", poolsz); return -1; }
.Lm_m_stack:
        mov rdi, [rbp+poolsz]
        call malloc
        mov [rbp+sp_], rax
        test rax, rax
        jne .Lm_memset
        mov edi, offset msg_m_stack
        mov rsi, [rbp+poolsz]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:
#:  memset(sym,  0, poolsz);
.Lm_memset:
        mov rdi, [sym]
        xor esi, esi
        mov rdx, [rbp+poolsz]
        call memset
#:  memset(e,    0, poolsz);
        mov rdi, [e]
        xor esi, esi
        mov rdx, [rbp+poolsz]
        call memset
#:  memset(data, 0, poolsz);
        mov rdi, [data]
        xor esi, esi
        mov rdx, [rbp+poolsz]
        call memset

#:
#:  p = "char else enum if int return sizeof while "
#:      "open read close printf malloc free memset memcmp exit void main";
        mov qword ptr [p], offset keywords
#:  i = Char; while (i <= While) { next(); id[Tk] = i++; } // add keywords to symbol table
        mov qword ptr [rbp+i], Char
.Lm_kw_loop:
        cmp qword ptr [rbp+i], While
        jg .Lm_sys_init
        call next
        mov rax, [id]
        mov rcx, [rbp+i]
        mov [rax+Tk*8], rcx
        add qword ptr [rbp+i], 1
        jmp .Lm_kw_loop
#:  i = OPEN; while (i <= EXIT) { next(); id[Class] = Sys; id[Type] = INT; id[Val] = i++; } // add library to symbol table
.Lm_sys_init:
        mov qword ptr [rbp+i], OPEN
.Lm_sys_loop:
        cmp qword ptr [rbp+i], EXIT
        jg .Lm_void
        call next
        mov rax, [id]
        mov qword ptr [rax+Class*8], Sys
        mov qword ptr [rax+Type*8], INT
        mov rcx, [rbp+i]
        mov [rax+Val*8], rcx
        add qword ptr [rbp+i], 1
        jmp .Lm_sys_loop
#:  next(); id[Tk] = Char; // handle void type
.Lm_void:
        call next
        mov rax, [id]
        mov qword ptr [rax+Tk*8], Char
#:  next(); idmain = id; // keep track of main
        call next
        mov rax, [id]
        mov [rbp+idmain], rax

#:
#:  if (!(lp = p = malloc(poolsz))) { printf("could not malloc(%d) source area\n", poolsz); return -1; }
        mov rdi, [rbp+poolsz]
        call malloc
        mov [p], rax
        mov [lp], rax
        test rax, rax
        jne .Lm_read_src
        mov edi, offset msg_m_src
        mov rsi, [rbp+poolsz]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:  if ((i = read(fd, p, poolsz-1)) <= 0) { printf("read() returned %d\n", i); return -1; }
.Lm_read_src:
        mov rdi, [rbp+fd]
        mov rsi, [p]
        mov rdx, [rbp+poolsz]
        sub rdx, 1
        call read
        mov [rbp+i], rax
        cmp rax, 0
        jg .Lm_read_ok
        mov edi, offset msg_read
        mov rsi, [rbp+i]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:  p[i] = 0;
.Lm_read_ok:
        mov rax, [p]
        mov rcx, [rbp+i]
        mov byte ptr [rax+rcx], 0
#:  close(fd);
        mov rdi, [rbp+fd]
        call close

#:
#:  // parse declarations
#:  line = 1;
        mov qword ptr [line], 1
#:  next();
        call next
#:  while (tk) {
.Lm_decl_loop:
        cmp qword ptr [tk], 0
        je .Lm_run_setup
#:    bt = INT; // basetype
        mov qword ptr [rbp+bt], INT
#:    if (tk == Int) next();
        cmp qword ptr [tk], Int
        jne .Lm_decl_char
        call next
        jmp .Lm_decl_names
#:    else if (tk == Char) { next(); bt = CHAR; }
.Lm_decl_char:
        cmp qword ptr [tk], Char
        jne .Lm_decl_enum
        call next
        mov qword ptr [rbp+bt], CHAR
        jmp .Lm_decl_names
#:    else if (tk == Enum) {
.Lm_decl_enum:
        cmp qword ptr [tk], Enum
        jne .Lm_decl_names
#:      next();
        call next
#:      if (tk != '{') next();
        cmp qword ptr [tk], 123      # '{'
        je .Lm_enum_body
        call next
#:      if (tk == '{') {
.Lm_enum_body:
        cmp qword ptr [tk], 123      # '{'
        jne .Lm_decl_names
#:        next();
        call next
#:        i = 0;
        mov qword ptr [rbp+i], 0
#:        while (tk != '}') {
.Lm_enum_loop:
        cmp qword ptr [tk], 125      # '}'
        je .Lm_enum_done
#:          if (tk != Id) { printf("%d: bad enum identifier %d\n", line, tk); return -1; }
        cmp qword ptr [tk], Id
        je .Lm_enum_id
        mov edi, offset msg_enum_id
        mov rsi, [line]
        mov rdx, [tk]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:          next();
.Lm_enum_id:
        call next
#:          if (tk == Assign) {
        cmp qword ptr [tk], Assign
        jne .Lm_enum_set
#:            next();
        call next
#:            if (tk != Num) { printf("%d: bad enum initializer\n", line); return -1; }
        cmp qword ptr [tk], Num
        je .Lm_enum_val
        mov edi, offset msg_enum_init
        mov rsi, [line]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:            i = ival;
.Lm_enum_val:
        mov rax, [ival]
        mov [rbp+i], rax
#:            next();
        call next
#:          }
#:          id[Class] = Num; id[Type] = INT; id[Val] = i++;
.Lm_enum_set:
        mov rax, [id]
        mov qword ptr [rax+Class*8], Num
        mov qword ptr [rax+Type*8], INT
        mov rcx, [rbp+i]
        mov [rax+Val*8], rcx
        add qword ptr [rbp+i], 1
#:          if (tk == ',') next();
        cmp qword ptr [tk], 44       # ','
        jne .Lm_enum_loop
        call next
        jmp .Lm_enum_loop
#:        }
#:        next();
.Lm_enum_done:
        call next
#:      }
#:    }
#:    while (tk != ';' && tk != '}') {
.Lm_decl_names:
        cmp qword ptr [tk], 59       # ';'
        je .Lm_decl_next
        cmp qword ptr [tk], 125      # '}'
        je .Lm_decl_next
#:      ty = bt;
        mov rax, [rbp+bt]
        mov [rbp+ty_], rax
#:      while (tk == Mul) { next(); ty = ty + PTR; }
.Lm_gmul:
        cmp qword ptr [tk], Mul
        jne .Lm_gname
        call next
        add qword ptr [rbp+ty_], PTR
        jmp .Lm_gmul
#:      if (tk != Id) { printf("%d: bad global declaration\n", line); return -1; }
.Lm_gname:
        cmp qword ptr [tk], Id
        je .Lm_gdup
        mov edi, offset msg_bad_glo
        mov rsi, [line]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:      if (id[Class]) { printf("%d: duplicate global definition\n", line); return -1; }
.Lm_gdup:
        mov rax, [id]
        cmp qword ptr [rax+Class*8], 0
        je .Lm_gok
        mov edi, offset msg_dup_glo
        mov rsi, [line]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:      next();
.Lm_gok:
        call next
#:      id[Type] = ty;
        mov rax, [id]
        mov rcx, [rbp+ty_]
        mov [rax+Type*8], rcx
#:      if (tk == '(') { // function
        cmp qword ptr [tk], 40       # '('
        jne .Lm_gvar
#:        id[Class] = Fun;
        mov rax, [id]
        mov qword ptr [rax+Class*8], Fun
#:        id[Val] = (int)(e + 1);
        mov rcx, [e]
        add rcx, 8
        mov [rax+Val*8], rcx
#:        next(); i = 0;
        call next
        mov qword ptr [rbp+i], 0
#:        while (tk != ')') {
.Lm_param_loop:
        cmp qword ptr [tk], 41       # ')'
        je .Lm_param_done
#:          ty = INT;
        mov qword ptr [rbp+ty_], INT
#:          if (tk == Int) next();
        cmp qword ptr [tk], Int
        jne .Lm_param_char
        call next
        jmp .Lm_param_mul
#:          else if (tk == Char) { next(); ty = CHAR; }
.Lm_param_char:
        cmp qword ptr [tk], Char
        jne .Lm_param_mul
        call next
        mov qword ptr [rbp+ty_], CHAR
#:          while (tk == Mul) { next(); ty = ty + PTR; }
.Lm_param_mul:
        cmp qword ptr [tk], Mul
        jne .Lm_param_id
        call next
        add qword ptr [rbp+ty_], PTR
        jmp .Lm_param_mul
#:          if (tk != Id) { printf("%d: bad parameter declaration\n", line); return -1; }
.Lm_param_id:
        cmp qword ptr [tk], Id
        je .Lm_param_dup
        mov edi, offset msg_bad_param
        mov rsi, [line]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:          if (id[Class] == Loc) { printf("%d: duplicate parameter definition\n", line); return -1; }
.Lm_param_dup:
        mov rax, [id]
        cmp qword ptr [rax+Class*8], Loc
        jne .Lm_param_set
        mov edi, offset msg_dup_param
        mov rsi, [line]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:          id[HClass] = id[Class]; id[Class] = Loc;
.Lm_param_set:
        mov rax, [id]
        mov rcx, [rax+Class*8]
        mov [rax+HClass*8], rcx
        mov qword ptr [rax+Class*8], Loc
#:          id[HType]  = id[Type];  id[Type] = ty;
        mov rcx, [rax+Type*8]
        mov [rax+HType*8], rcx
        mov rcx, [rbp+ty_]
        mov [rax+Type*8], rcx
#:          id[HVal]   = id[Val];   id[Val] = i++;
        mov rcx, [rax+Val*8]
        mov [rax+HVal*8], rcx
        mov rcx, [rbp+i]
        mov [rax+Val*8], rcx
        add qword ptr [rbp+i], 1
#:          next();
        call next
#:          if (tk == ',') next();
        cmp qword ptr [tk], 44       # ','
        jne .Lm_param_loop
        call next
        jmp .Lm_param_loop
#:        }
#:        next();
.Lm_param_done:
        call next
#:        if (tk != '{') { printf("%d: bad function definition\n", line); return -1; }
        cmp qword ptr [tk], 123      # '{'
        je .Lm_fbody
        mov edi, offset msg_bad_func
        mov rsi, [line]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:        loc = ++i;
.Lm_fbody:
        add qword ptr [rbp+i], 1
        mov rax, [rbp+i]
        mov [loc], rax
#:        next();
        call next
#:        while (tk == Int || tk == Char) {
.Lm_local_loop:
        cmp qword ptr [tk], Int
        je .Lm_local_bt
        cmp qword ptr [tk], Char
        je .Lm_local_bt
        jmp .Lm_fbody_emit
#:          bt = (tk == Int) ? INT : CHAR;
.Lm_local_bt:
        mov rax, INT
        cmp qword ptr [tk], Int
        je .Lm_local_bts
        mov rax, CHAR
.Lm_local_bts:
        mov [rbp+bt], rax
#:          next();
        call next
#:          while (tk != ';') {
.Lm_local_names:
        cmp qword ptr [tk], 59       # ';'
        je .Lm_local_semi
#:            ty = bt;
        mov rax, [rbp+bt]
        mov [rbp+ty_], rax
#:            while (tk == Mul) { next(); ty = ty + PTR; }
.Lm_lmul:
        cmp qword ptr [tk], Mul
        jne .Lm_lid
        call next
        add qword ptr [rbp+ty_], PTR
        jmp .Lm_lmul
#:            if (tk != Id) { printf("%d: bad local declaration\n", line); return -1; }
.Lm_lid:
        cmp qword ptr [tk], Id
        je .Lm_ldup
        mov edi, offset msg_bad_loc
        mov rsi, [line]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:            if (id[Class] == Loc) { printf("%d: duplicate local definition\n", line); return -1; }
.Lm_ldup:
        mov rax, [id]
        cmp qword ptr [rax+Class*8], Loc
        jne .Lm_local_set
        mov edi, offset msg_dup_loc
        mov rsi, [line]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:            id[HClass] = id[Class]; id[Class] = Loc;
.Lm_local_set:
        mov rax, [id]
        mov rcx, [rax+Class*8]
        mov [rax+HClass*8], rcx
        mov qword ptr [rax+Class*8], Loc
#:            id[HType]  = id[Type];  id[Type] = ty;
        mov rcx, [rax+Type*8]
        mov [rax+HType*8], rcx
        mov rcx, [rbp+ty_]
        mov [rax+Type*8], rcx
#:            id[HVal]   = id[Val];   id[Val] = ++i;
        mov rcx, [rax+Val*8]
        mov [rax+HVal*8], rcx
        add qword ptr [rbp+i], 1
        mov rcx, [rbp+i]
        mov [rax+Val*8], rcx
#:            next();
        call next
#:            if (tk == ',') next();
        cmp qword ptr [tk], 44       # ','
        jne .Lm_local_names
        call next
        jmp .Lm_local_names
#:          }
#:          next();
.Lm_local_semi:
        call next
        jmp .Lm_local_loop
#:        }
#:        *++e = ENT; *++e = i - loc;
.Lm_fbody_emit:
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], ENT
        mov rax, [rbp+i]
        sub rax, [loc]
        add qword ptr [e], 8
        mov rcx, [e]
        mov [rcx], rax
#:        while (tk != '}') stmt();
.Lm_stmt_loop:
        cmp qword ptr [tk], 125      # '}'
        je .Lm_stmt_done
        call stmt
        jmp .Lm_stmt_loop
#:        *++e = LEV;
.Lm_stmt_done:
        add qword ptr [e], 8
        mov rax, [e]
        mov qword ptr [rax], LEV
#:        id = sym; // unwind symbol table locals
        mov rax, [sym]
        mov [id], rax
#:        while (id[Tk]) {
.Lm_unwind:
        mov rax, [id]
        cmp qword ptr [rax+Tk*8], 0
        je .Lm_gnext
#:          if (id[Class] == Loc) {
        cmp qword ptr [rax+Class*8], Loc
        jne .Lm_unwind_next
#:            id[Class] = id[HClass];
        mov rcx, [rax+HClass*8]
        mov [rax+Class*8], rcx
#:            id[Type] = id[HType];
        mov rcx, [rax+HType*8]
        mov [rax+Type*8], rcx
#:            id[Val] = id[HVal];
        mov rcx, [rax+HVal*8]
        mov [rax+Val*8], rcx
#:          }
#:          id = id + Idsz;
.Lm_unwind_next:
        add qword ptr [id], Idsz*8
        jmp .Lm_unwind
#:        }
#:      }
#:      else {
#:        id[Class] = Glo;
.Lm_gvar:
        mov rax, [id]
        mov qword ptr [rax+Class*8], Glo
#:        id[Val] = (int)data;
        mov rcx, [data]
        mov [rax+Val*8], rcx
#:        data = data + sizeof(int);
        add qword ptr [data], 8
#:      }
#:      if (tk == ',') next();
.Lm_gnext:
        cmp qword ptr [tk], 44       # ','
        jne .Lm_decl_names
        call next
        jmp .Lm_decl_names
#:    }
#:    next();
.Lm_decl_next:
        call next
        jmp .Lm_decl_loop
#:  }

#:
#:  if (!(pc = (int *)idmain[Val])) { printf("main() not defined\n"); return -1; }
.Lm_run_setup:
        mov rax, [rbp+idmain]
        mov rax, [rax+Val*8]
        mov [rbp+pc], rax
        test rax, rax
        jne .Lm_src_chk
        mov edi, offset msg_no_main
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:  if (src) return 0;
.Lm_src_chk:
        cmp qword ptr [src], 0
        je .Lm_stack
        mov eax, 0
        mov rsp, rbp
        pop rbp
        ret

#:
#:  // setup stack
#:  bp = sp = (int *)((int)sp + poolsz);
.Lm_stack:
        mov rax, [rbp+sp_]
        add rax, [rbp+poolsz]
        mov [rbp+sp_], rax
        mov [rbp+bp_], rax
#:  *--sp = EXIT; // call exit if main returns
        sub qword ptr [rbp+sp_], 8
        mov rax, [rbp+sp_]
        mov qword ptr [rax], EXIT
#:  *--sp = PSH; t = sp;
        sub qword ptr [rbp+sp_], 8
        mov rax, [rbp+sp_]
        mov qword ptr [rax], PSH
        mov [rbp+t], rax
#:  *--sp = argc;
        sub qword ptr [rbp+sp_], 8
        mov rax, [rbp+sp_]
        mov rcx, [rbp+argc]
        mov [rax], rcx
#:  *--sp = (int)argv;
        sub qword ptr [rbp+sp_], 8
        mov rax, [rbp+sp_]
        mov rcx, [rbp+argv]
        mov [rax], rcx
#:  *--sp = (int)t;
        sub qword ptr [rbp+sp_], 8
        mov rax, [rbp+sp_]
        mov rcx, [rbp+t]
        mov [rax], rcx

#:
#:  // run...
#:  cycle = 0;
        mov qword ptr [rbp+cycle], 0
#:  while (1) {
#:    i = *pc++; ++cycle;
.Lm_vm:
        mov rax, [rbp+pc]
        mov rcx, [rax]
        mov [rbp+i], rcx
        add qword ptr [rbp+pc], 8
        add qword ptr [rbp+cycle], 1
#:    if (debug) {
        cmp qword ptr [debug], 0
        je .Lm_op_lea
#:      printf("%d> %.4s", cycle,
#:        &"LEA ,IMM ,JMP ,JSR ,BZ  ,BNZ ,ENT ,ADJ ,LEV ,LI  ,LC  ,SI  ,SC  ,PSH ,"
#:         "OR  ,XOR ,AND ,EQ  ,NE  ,LT  ,GT  ,LE  ,GE  ,SHL ,SHR ,ADD ,SUB ,MUL ,DIV ,MOD ,"
#:         "OPEN,READ,CLOS,PRTF,MALC,FREE,MSET,MCMP,EXIT,"[i * 5]);
        mov edi, offset fmt_debug
        mov rsi, [rbp+cycle]
        mov rdx, [rbp+i]
        imul rdx, rdx, 5
        add rdx, offset ops
        xor eax, eax
        call printf
#:      if (i <= ADJ) printf(" %d\n", *pc); else printf("\n");
        cmp qword ptr [rbp+i], ADJ
        jg .Lm_dbg_nl
        mov edi, offset fmt_opval
        mov rax, [rbp+pc]
        mov rsi, [rax]
        xor eax, eax
        call printf
        jmp .Lm_op_lea
.Lm_dbg_nl:
        mov edi, offset fmt_nl
        xor eax, eax
        call printf
#:    }
#:    if      (i == LEA) a = (int)(bp + *pc++);                             // load local address
.Lm_op_lea:
        cmp qword ptr [rbp+i], LEA
        jne .Lm_op_imm
        mov rax, [rbp+pc]
        mov rax, [rax]
        imul rax, rax, 8             # (int *) arithmetic scales by 8
        add rax, [rbp+bp_]
        mov [rbp+a], rax
        add qword ptr [rbp+pc], 8
        jmp .Lm_vm
#:    else if (i == IMM) a = *pc++;                                         // load global address or immediate
.Lm_op_imm:
        cmp qword ptr [rbp+i], IMM
        jne .Lm_op_jmp
        mov rax, [rbp+pc]
        mov rax, [rax]
        mov [rbp+a], rax
        add qword ptr [rbp+pc], 8
        jmp .Lm_vm
#:    else if (i == JMP) pc = (int *)*pc;                                   // jump
.Lm_op_jmp:
        cmp qword ptr [rbp+i], JMP
        jne .Lm_op_jsr
        mov rax, [rbp+pc]
        mov rax, [rax]
        mov [rbp+pc], rax
        jmp .Lm_vm
#:    else if (i == JSR) { *--sp = (int)(pc + 1); pc = (int *)*pc; }        // jump to subroutine
.Lm_op_jsr:
        cmp qword ptr [rbp+i], JSR
        jne .Lm_op_bz
        sub qword ptr [rbp+sp_], 8
        mov rax, [rbp+pc]
        add rax, 8
        mov rcx, [rbp+sp_]
        mov [rcx], rax
        mov rax, [rbp+pc]
        mov rax, [rax]
        mov [rbp+pc], rax
        jmp .Lm_vm
#:    else if (i == BZ)  pc = a ? pc + 1 : (int *)*pc;                      // branch if zero
.Lm_op_bz:
        cmp qword ptr [rbp+i], BZ
        jne .Lm_op_bnz
        cmp qword ptr [rbp+a], 0
        je .Lm_bz_taken
        add qword ptr [rbp+pc], 8
        jmp .Lm_vm
.Lm_bz_taken:
        mov rax, [rbp+pc]
        mov rax, [rax]
        mov [rbp+pc], rax
        jmp .Lm_vm
#:    else if (i == BNZ) pc = a ? (int *)*pc : pc + 1;                      // branch if not zero
.Lm_op_bnz:
        cmp qword ptr [rbp+i], BNZ
        jne .Lm_op_ent
        cmp qword ptr [rbp+a], 0
        jne .Lm_bnz_taken
        add qword ptr [rbp+pc], 8
        jmp .Lm_vm
.Lm_bnz_taken:
        mov rax, [rbp+pc]
        mov rax, [rax]
        mov [rbp+pc], rax
        jmp .Lm_vm
#:    else if (i == ENT) { *--sp = (int)bp; bp = sp; sp = sp - *pc++; }     // enter subroutine
.Lm_op_ent:
        cmp qword ptr [rbp+i], ENT
        jne .Lm_op_adj
        sub qword ptr [rbp+sp_], 8
        mov rax, [rbp+sp_]
        mov rcx, [rbp+bp_]
        mov [rax], rcx
        mov rax, [rbp+sp_]
        mov [rbp+bp_], rax
        mov rax, [rbp+pc]
        mov rax, [rax]
        imul rax, rax, 8             # (int *) arithmetic scales by 8
        sub [rbp+sp_], rax
        add qword ptr [rbp+pc], 8
        jmp .Lm_vm
#:    else if (i == ADJ) sp = sp + *pc++;                                   // stack adjust
.Lm_op_adj:
        cmp qword ptr [rbp+i], ADJ
        jne .Lm_op_lev
        mov rax, [rbp+pc]
        mov rax, [rax]
        imul rax, rax, 8             # (int *) arithmetic scales by 8
        add [rbp+sp_], rax
        add qword ptr [rbp+pc], 8
        jmp .Lm_vm
#:    else if (i == LEV) { sp = bp; bp = (int *)*sp++; pc = (int *)*sp++; } // leave subroutine
.Lm_op_lev:
        cmp qword ptr [rbp+i], LEV
        jne .Lm_op_li
        mov rax, [rbp+bp_]
        mov [rbp+sp_], rax
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        mov [rbp+bp_], rcx
        add qword ptr [rbp+sp_], 8
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        mov [rbp+pc], rcx
        add qword ptr [rbp+sp_], 8
        jmp .Lm_vm
#:    else if (i == LI)  a = *(int *)a;                                     // load int
.Lm_op_li:
        cmp qword ptr [rbp+i], LI
        jne .Lm_op_lc
        mov rax, [rbp+a]
        mov rax, [rax]
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == LC)  a = *(char *)a;                                    // load char
.Lm_op_lc:
        cmp qword ptr [rbp+i], LC
        jne .Lm_op_si
        mov rax, [rbp+a]
        movsx rax, byte ptr [rax]
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == SI)  *(int *)*sp++ = a;                                 // store int
.Lm_op_si:
        cmp qword ptr [rbp+i], SI_
        jne .Lm_op_sc
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        mov rax, [rbp+a]
        mov [rcx], rax
        jmp .Lm_vm
#:    else if (i == SC)  a = *(char *)*sp++ = a;                            // store char
.Lm_op_sc:
        cmp qword ptr [rbp+i], SC
        jne .Lm_op_psh
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        mov rax, [rbp+a]
        mov byte ptr [rcx], al
        movsx rax, al                # value of the assignment is the stored char
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == PSH) *--sp = a;                                         // push
.Lm_op_psh:
        cmp qword ptr [rbp+i], PSH
        jne .Lm_op_or
        sub qword ptr [rbp+sp_], 8
        mov rax, [rbp+sp_]
        mov rcx, [rbp+a]
        mov [rax], rcx
        jmp .Lm_vm

#:
#:    else if (i == OR)  a = *sp++ |  a;
.Lm_op_or:
        cmp qword ptr [rbp+i], OR_
        jne .Lm_op_xor
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        or rcx, [rbp+a]
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == XOR) a = *sp++ ^  a;
.Lm_op_xor:
        cmp qword ptr [rbp+i], XOR_
        jne .Lm_op_and
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        xor rcx, [rbp+a]
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == AND) a = *sp++ &  a;
.Lm_op_and:
        cmp qword ptr [rbp+i], AND_
        jne .Lm_op_eq
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        and rcx, [rbp+a]
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == EQ)  a = *sp++ == a;
.Lm_op_eq:
        cmp qword ptr [rbp+i], EQ_
        jne .Lm_op_ne
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        cmp rcx, [rbp+a]
        sete cl
        movzx rcx, cl
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == NE)  a = *sp++ != a;
.Lm_op_ne:
        cmp qword ptr [rbp+i], NE_
        jne .Lm_op_lt
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        cmp rcx, [rbp+a]
        setne cl
        movzx rcx, cl
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == LT)  a = *sp++ <  a;
.Lm_op_lt:
        cmp qword ptr [rbp+i], LT_
        jne .Lm_op_gt
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        cmp rcx, [rbp+a]
        setl cl
        movzx rcx, cl
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == GT)  a = *sp++ >  a;
.Lm_op_gt:
        cmp qword ptr [rbp+i], GT_
        jne .Lm_op_le
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        cmp rcx, [rbp+a]
        setg cl
        movzx rcx, cl
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == LE)  a = *sp++ <= a;
.Lm_op_le:
        cmp qword ptr [rbp+i], LE_
        jne .Lm_op_ge
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        cmp rcx, [rbp+a]
        setle cl
        movzx rcx, cl
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == GE)  a = *sp++ >= a;
.Lm_op_ge:
        cmp qword ptr [rbp+i], GE_
        jne .Lm_op_shl
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        cmp rcx, [rbp+a]
        setge cl
        movzx rcx, cl
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == SHL) a = *sp++ << a;
.Lm_op_shl:
        cmp qword ptr [rbp+i], SHL_
        jne .Lm_op_shr
        mov rax, [rbp+sp_]
        mov rdx, [rax]
        add qword ptr [rbp+sp_], 8
        mov rcx, [rbp+a]
        shl rdx, cl
        mov [rbp+a], rdx
        jmp .Lm_vm
#:    else if (i == SHR) a = *sp++ >> a;
.Lm_op_shr:
        cmp qword ptr [rbp+i], SHR_
        jne .Lm_op_add
        mov rax, [rbp+sp_]
        mov rdx, [rax]
        add qword ptr [rbp+sp_], 8
        mov rcx, [rbp+a]
        sar rdx, cl                  # arithmetic shift: values are signed
        mov [rbp+a], rdx
        jmp .Lm_vm
#:    else if (i == ADD) a = *sp++ +  a;
.Lm_op_add:
        cmp qword ptr [rbp+i], ADD
        jne .Lm_op_sub
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        add rcx, [rbp+a]
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == SUB) a = *sp++ -  a;
.Lm_op_sub:
        cmp qword ptr [rbp+i], SUB
        jne .Lm_op_mul
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        sub rcx, [rbp+a]
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == MUL) a = *sp++ *  a;
.Lm_op_mul:
        cmp qword ptr [rbp+i], MUL
        jne .Lm_op_div
        mov rax, [rbp+sp_]
        mov rcx, [rax]
        add qword ptr [rbp+sp_], 8
        imul rcx, [rbp+a]
        mov [rbp+a], rcx
        jmp .Lm_vm
#:    else if (i == DIV) a = *sp++ /  a;
.Lm_op_div:
        cmp qword ptr [rbp+i], DIV
        jne .Lm_op_mod
        mov rcx, [rbp+sp_]
        mov rax, [rcx]
        add qword ptr [rbp+sp_], 8
        cqo
        idiv qword ptr [rbp+a]
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == MOD) a = *sp++ %  a;
.Lm_op_mod:
        cmp qword ptr [rbp+i], MOD_
        jne .Lm_op_open
        mov rcx, [rbp+sp_]
        mov rax, [rcx]
        add qword ptr [rbp+sp_], 8
        cqo
        idiv qword ptr [rbp+a]
        mov [rbp+a], rdx             # remainder is in rdx
        jmp .Lm_vm

#:
#:    else if (i == OPEN) a = open((char *)sp[1], *sp);
.Lm_op_open:
        cmp qword ptr [rbp+i], OPEN
        jne .Lm_op_read
        mov rax, [rbp+sp_]
        mov rdi, [rax+8]
        mov rsi, [rax]
        xor eax, eax
        call open
        cdqe
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == READ) a = read(sp[2], (char *)sp[1], *sp);
.Lm_op_read:
        cmp qword ptr [rbp+i], READ
        jne .Lm_op_clos
        mov rax, [rbp+sp_]
        mov rdi, [rax+16]
        mov rsi, [rax+8]
        mov rdx, [rax]
        call read
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == CLOS) a = close(*sp);
.Lm_op_clos:
        cmp qword ptr [rbp+i], CLOS
        jne .Lm_op_prtf
        mov rax, [rbp+sp_]
        mov rdi, [rax]
        call close
        cdqe
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == PRTF) { t = sp + pc[1]; a = printf((char *)t[-1], t[-2], t[-3], t[-4], t[-5], t[-6]); }
.Lm_op_prtf:
        cmp qword ptr [rbp+i], PRTF
        jne .Lm_op_malc
        mov rax, [rbp+pc]
        mov rax, [rax+8]
        imul rax, rax, 8             # (int *) arithmetic scales by 8
        add rax, [rbp+sp_]
        mov [rbp+t], rax
        mov rax, [rbp+t]
        mov rdi, [rax-8]
        mov rsi, [rax-16]
        mov rdx, [rax-24]
        mov rcx, [rax-32]
        mov r8,  [rax-40]
        mov r9,  [rax-48]
        xor eax, eax
        call printf
        cdqe
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == MALC) a = (int)malloc(*sp);
.Lm_op_malc:
        cmp qword ptr [rbp+i], MALC
        jne .Lm_op_free
        mov rax, [rbp+sp_]
        mov rdi, [rax]
        call malloc
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == FREE) free((void *)*sp);
.Lm_op_free:
        cmp qword ptr [rbp+i], FREE
        jne .Lm_op_mset
        mov rax, [rbp+sp_]
        mov rdi, [rax]
        call free
        jmp .Lm_vm
#:    else if (i == MSET) a = (int)memset((char *)sp[2], sp[1], *sp);
.Lm_op_mset:
        cmp qword ptr [rbp+i], MSET
        jne .Lm_op_mcmp
        mov rax, [rbp+sp_]
        mov rdi, [rax+16]
        mov rsi, [rax+8]
        mov rdx, [rax]
        call memset
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == MCMP) a = memcmp((char *)sp[2], (char *)sp[1], *sp);
.Lm_op_mcmp:
        cmp qword ptr [rbp+i], MCMP
        jne .Lm_op_exit
        mov rax, [rbp+sp_]
        mov rdi, [rax+16]
        mov rsi, [rax+8]
        mov rdx, [rax]
        call memcmp
        cdqe
        mov [rbp+a], rax
        jmp .Lm_vm
#:    else if (i == EXIT) { printf("exit(%d) cycle = %d\n", *sp, cycle); return *sp; }
.Lm_op_exit:
        cmp qword ptr [rbp+i], EXIT
        jne .Lm_op_unknown
        mov edi, offset msg_exit
        mov rax, [rbp+sp_]
        mov rsi, [rax]
        mov rdx, [rbp+cycle]
        xor eax, eax
        call printf
        mov rax, [rbp+sp_]
        mov rax, [rax]
        mov rsp, rbp
        pop rbp
        ret
#:    else { printf("unknown instruction = %d! cycle = %d\n", i, cycle); return -1; }
.Lm_op_unknown:
        mov edi, offset msg_unknown
        mov rsi, [rbp+i]
        mov rdx, [rbp+cycle]
        xor eax, eax
        call printf
        mov eax, -1
        mov rsp, rbp
        pop rbp
        ret
#:  }
#:}

# ----------------------------------------------------------------------
# Freestanding runtime.
#
# Everything below replaces libc and the C runtime so that the binary
# is self-contained: _start replaces crt0, and the nine functions c4.c
# uses (open, read, close, printf, malloc, free, memset, memcmp, exit)
# are implemented with direct Linux x86-64 syscalls.  The call sites
# above are unchanged: these functions keep the same names and the
# System V AMD64 calling convention.
#
# printf implements only the conversions c4 and the programs it runs
# need: %d, %s and %c, each with an optional decimal width and an
# optional precision ("." followed by digits or "*").  Any other
# character after '%' is output literally (which also handles "%%").
# Every byte is emitted the moment it is produced, one write syscall
# each, with no buffering anywhere; it returns the number of bytes
# written, like libc printf.  Two deviations from libc: %d prints the
# full 64-bit value (c4's "int" is long long), where glibc's %d would
# truncate the argument to 32 bits; and the field width is honored for
# %s and %c only, not %d (c4 never uses a width with %d, and honoring
# it would require knowing the digit count before emitting).
# ----------------------------------------------------------------------

.bss
.align 8
pf_count:       .space 8             # bytes written by the current printf
pf_char:        .space 1             # the byte pf_putc hands to write()

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

.globl free
free:                                # free(ptr): no-op (mappings are
        ret                          # reclaimed by the kernel on exit)

.globl memset
memset:                              # memset(s, c, n) -> s
        mov rax, rdi
.Lrt_ms_loop:
        test rdx, rdx
        je .Lrt_ms_done
        mov [rdi], sil
        add rdi, 1
        sub rdx, 1
        jmp .Lrt_ms_loop
.Lrt_ms_done:
        ret

.globl memcmp
memcmp:                              # memcmp(s1, s2, n) -> <0, 0, >0
        xor eax, eax
.Lrt_mc_loop:
        test rdx, rdx
        je .Lrt_mc_done
        movzx eax, byte ptr [rdi]
        movzx ecx, byte ptr [rsi]
        sub eax, ecx
        jne .Lrt_mc_done
        add rdi, 1
        add rsi, 1
        sub rdx, 1
        jmp .Lrt_mc_loop
.Lrt_mc_done:
        ret

# ---- printf ----------------------------------------------------------

# pf_putc(c): write the single byte c (in dil) to fd 1 and count it.
pf_putc:
        mov [pf_char], dil
        mov edi, 1                   # fd 1 (stdout)
        mov esi, offset pf_char
        mov edx, 1
        mov eax, 1                   # SYS_write
        syscall
        test rax, rax
        jle .Lrt_pc_done             # error: drop the byte silently
        add qword ptr [pf_count], 1
.Lrt_pc_done:
        ret

# pf_putu(n): print n as unsigned decimal.  Recursing on n/10 before
# emitting the digit n%10 yields the digits most significant first,
# so each one can be written the moment it is produced.
pf_putu:
        mov rax, rdi
        mov esi, 10
        xor edx, edx
        div rsi
        push rdx                     # remainder: the last digit
        test rax, rax
        je .Lrt_pu_digit
        mov rdi, rax
        call pf_putu
.Lrt_pu_digit:
        pop rdi
        add edi, 48                  # '0'
        call pf_putc
        ret

# printf(fmt, ...) -> bytes written.  The five possible value arguments
# arrive in rsi, rdx, rcx, r8, r9 (c4's PRTF opcode passes exactly
# these; al is ignored since there are never floating-point args) and
# are spilled to a stack array indexed by pf_argi.
.globl printf
printf:
        push rbp
        mov rbp, rsp
        sub rsp, 112
        pf_args  = -48               # spilled args: [rbp+pf_args+i*8]
        pf_fmt   = -56               # cursor into the format string
        pf_argi  = -64               # index of the next argument
        pf_width = -72               # field width; then the pad count
        pf_prec  = -80               # precision (-1 = none)
        pf_item  = -88               # bytes to emit for one conversion
        pf_len   = -96               # their length
        pf_buf   = -104              # one-byte home for %c and literals
        mov [rbp+pf_args], rsi
        mov [rbp+pf_args+8], rdx
        mov [rbp+pf_args+16], rcx
        mov [rbp+pf_args+24], r8
        mov [rbp+pf_args+32], r9
        mov [rbp+pf_fmt], rdi
        mov qword ptr [pf_count], 0
        mov qword ptr [rbp+pf_argi], 0

.Lrt_pf_loop:
        # emit literal characters until the next '%' or the final NUL
        mov rcx, [rbp+pf_fmt]
        movzx edx, byte ptr [rcx]
        test edx, edx
        je .Lrt_pf_end
        add rcx, 1
        mov [rbp+pf_fmt], rcx
        cmp edx, 37                  # '%'
        je .Lrt_pf_percent
        mov edi, edx
        call pf_putc
        jmp .Lrt_pf_loop

        # optional decimal field width
.Lrt_pf_percent:
        mov qword ptr [rbp+pf_width], 0
        mov qword ptr [rbp+pf_prec], -1
.Lrt_pf_width:
        movzx edx, byte ptr [rcx]
        cmp edx, 48                  # '0'
        jl .Lrt_pf_width_done
        cmp edx, 57                  # '9'
        jg .Lrt_pf_width_done
        mov rax, [rbp+pf_width]
        imul rax, rax, 10
        add rax, rdx
        sub rax, 48                  # '0'
        mov [rbp+pf_width], rax
        add rcx, 1
        jmp .Lrt_pf_width
.Lrt_pf_width_done:

        # optional precision: '.' then digits or '*'
        cmp edx, 46                  # '.'
        jne .Lrt_pf_conv
        add rcx, 1
        mov qword ptr [rbp+pf_prec], 0
        movzx edx, byte ptr [rcx]
        cmp edx, 42                  # '*'
        jne .Lrt_pf_prec
        mov rax, [rbp+pf_argi]       # '*': precision is the next arg
        mov rdx, [rbp+pf_args+rax*8]
        add rax, 1
        mov [rbp+pf_argi], rax
        mov [rbp+pf_prec], rdx
        add rcx, 1
        jmp .Lrt_pf_conv
.Lrt_pf_prec:
        movzx edx, byte ptr [rcx]
        cmp edx, 48                  # '0'
        jl .Lrt_pf_conv
        cmp edx, 57                  # '9'
        jg .Lrt_pf_conv
        mov rax, [rbp+pf_prec]
        imul rax, rax, 10
        add rax, rdx
        sub rax, 48                  # '0'
        mov [rbp+pf_prec], rax
        add rcx, 1
        jmp .Lrt_pf_prec

        # conversion character
.Lrt_pf_conv:
        movzx edx, byte ptr [rcx]
        add rcx, 1
        mov [rbp+pf_fmt], rcx
        test edx, edx                # format ends with a lone '%'
        je .Lrt_pf_end
        cmp edx, 100                 # 'd'
        je .Lrt_pf_d
        cmp edx, 115                 # 's'
        je .Lrt_pf_s
        cmp edx, 99                  # 'c'
        je .Lrt_pf_c
        mov [rbp+pf_buf], dl         # anything else: emit it literally
        lea rax, [rbp+pf_buf]
        mov [rbp+pf_item], rax
        mov qword ptr [rbp+pf_len], 1
        jmp .Lrt_pf_emit

.Lrt_pf_d:                           # signed decimal (width ignored)
        mov rax, [rbp+pf_argi]
        mov rdx, [rbp+pf_args+rax*8]
        add rax, 1
        mov [rbp+pf_argi], rax
        mov [rbp+pf_item], rdx
        test rdx, rdx
        jns .Lrt_pf_d_mag
        mov edi, 45                  # '-'
        call pf_putc
        neg qword ptr [rbp+pf_item]
.Lrt_pf_d_mag:
        mov rdi, [rbp+pf_item]
        call pf_putu
        jmp .Lrt_pf_loop

.Lrt_pf_s:                           # string, up to NUL or precision
        mov rax, [rbp+pf_argi]
        mov rdx, [rbp+pf_args+rax*8]
        add rax, 1
        mov [rbp+pf_argi], rax
        mov [rbp+pf_item], rdx
        xor ecx, ecx
.Lrt_pf_s_len:
        cmp rcx, [rbp+pf_prec]       # never true when prec is -1
        je .Lrt_pf_s_done
        cmp byte ptr [rdx+rcx], 0
        je .Lrt_pf_s_done
        add rcx, 1
        jmp .Lrt_pf_s_len
.Lrt_pf_s_done:
        mov [rbp+pf_len], rcx
        jmp .Lrt_pf_emit

.Lrt_pf_c:                           # single character
        mov rax, [rbp+pf_argi]
        mov rdx, [rbp+pf_args+rax*8]
        add rax, 1
        mov [rbp+pf_argi], rax
        mov [rbp+pf_buf], dl
        lea rax, [rbp+pf_buf]
        mov [rbp+pf_item], rax
        mov qword ptr [rbp+pf_len], 1

.Lrt_pf_emit:                        # space-pad to the field width,
        mov rax, [rbp+pf_width]      # then emit the conversion itself
        sub rax, [rbp+pf_len]
        mov [rbp+pf_width], rax      # width slot now holds pad count
.Lrt_pf_pad:
        cmp qword ptr [rbp+pf_width], 0
        jle .Lrt_pf_put
        mov edi, 32                  # ' '
        call pf_putc
        sub qword ptr [rbp+pf_width], 1
        jmp .Lrt_pf_pad
.Lrt_pf_put:
        cmp qword ptr [rbp+pf_len], 0
        je .Lrt_pf_loop
        mov rax, [rbp+pf_item]
        movzx edi, byte ptr [rax]
        add qword ptr [rbp+pf_item], 1
        sub qword ptr [rbp+pf_len], 1
        call pf_putc
        jmp .Lrt_pf_put

.Lrt_pf_end:
        mov rax, [pf_count]
        mov rsp, rbp
        pop rbp
        ret

.section .note.GNU-stack,"",@progbits

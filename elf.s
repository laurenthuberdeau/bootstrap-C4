# elf.s - hand-written ELF executable header
#
# Included by each arch/*.s file as the first bytes of .text, so that
# when the object is linked with
#
#     ld -n --oformat binary -Ttext 0x400000 -o c4 c4.o
#
# the output file *is* a valid ELF executable whose every byte comes
# from a directive in the assembly sources: this header, then the code,
# then the data.  The linker only resolves addresses; it contributes no
# bytes of its own (no linker-generated ELF header, section headers or
# symbol tables).
#
# The image is a single read/write/execute PT_LOAD segment mapping the
# whole file at ELF_LOAD (0x400000, matching -Ttext), followed by the
# zero-initialized globals (.bss), which exist only in p_memsz.  A
# PT_GNU_STACK header marks the stack non-executable.  There are no
# section headers (e_shoff = e_shnum = 0); tools like readelf -h/-l and
# objdump -D -b binary still work.
#
# The including arch file must define, before this file:
#     WORDSZ        8 or 4 (selects the ELF64 or ELF32 header layout)
#     ELF_MACHINE   e_machine value (x86-64 62, i386 3, aarch64 183,
#                   riscv 243)
#     ELF_FLAGS     e_flags value (0 everywhere except RISC-V, which
#                   records the C extension and float ABI here)
# and, after including runtime.s and c4.s, provide the two end-of-image
# labels ELF_fileend (end of .data, = end of the file) and ELF_memend
# (end of .bss).

ELF_LOAD = 0x400000

.text
ELF_ehdr:
        .byte   0x7f, 'E', 'L', 'F' /* magic */
.if WORDSZ == 8
        .byte   2                   /* EI_CLASS: ELFCLASS64 */
.else
        .byte   1                   /* EI_CLASS: ELFCLASS32 */
.endif
        .byte   1                   /* EI_DATA: little-endian */
        .byte   1                   /* EI_VERSION: current */
        .byte   0                   /* EI_OSABI: System V */
        .byte   0, 0, 0, 0, 0, 0, 0, 0     /* padding */
        .short  2                   /* e_type: ET_EXEC */
        .short  ELF_MACHINE         /* e_machine */
        .long   1                   /* e_version: current */

.if WORDSZ == 8

        .quad   _start              /* e_entry */
        .quad   ELF_phdr - ELF_ehdr /* e_phoff */
        .quad   0                   /* e_shoff: no sections */
        .long   ELF_FLAGS           /* e_flags */
        .short  64                  /* e_ehsize */
        .short  56                  /* e_phentsize */
        .short  2                   /* e_phnum */
        .short  0, 0, 0             /* e_shentsize/shnum/shstrndx */

ELF_phdr:
        .long   1                   /* p_type: PT_LOAD */
        .long   7                   /* p_flags: read+write+exec */
        .quad   0                   /* p_offset: whole file */
        .quad   ELF_LOAD            /* p_vaddr */
        .quad   ELF_LOAD            /* p_paddr */
        .quad   ELF_fileend - ELF_LOAD  /* p_filesz */
        .quad   ELF_memend - ELF_LOAD  /* p_memsz: file + .bss */
        .quad   0x1000              /* p_align: one page */

        .long   0x6474e551          /* p_type: PT_GNU_STACK */
        .long   6                   /* p_flags: read+write */
        .quad   0, 0, 0, 0, 0       /* offset/vaddr/paddr/sizes */
        .quad   0x10                /* p_align */

.else

        .long   _start              /* e_entry */
        .long   ELF_phdr - ELF_ehdr /* e_phoff */
        .long   0                   /* e_shoff: no sections */
        .long   ELF_FLAGS           /* e_flags */
        .short  52                  /* e_ehsize */
        .short  32                  /* e_phentsize */
        .short  2                   /* e_phnum */
        .short  0, 0, 0             /* e_shentsize/shnum/shstrndx */

ELF_phdr:
        .long   1                   /* p_type: PT_LOAD */
        .long   0                   /* p_offset: whole file */
        .long   ELF_LOAD            /* p_vaddr */
        .long   ELF_LOAD            /* p_paddr */
        .long   ELF_fileend - ELF_LOAD  /* p_filesz */
        .long   ELF_memend - ELF_LOAD  /* p_memsz: file + .bss */
        .long   7                   /* p_flags: read+write+exec */
        .long   0x1000              /* p_align: one page */

        .long   0x6474e551          /* p_type: PT_GNU_STACK */
        .long   0, 0, 0, 0, 0       /* offset/vaddr/paddr/sizes */
        .long   6                   /* p_flags: read+write */
        .long   0x10                /* p_align */
.endif

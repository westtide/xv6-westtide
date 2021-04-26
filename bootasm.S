#include "asm.h"
#include "memlayout.h"
#include "mmu.h"

# Start the first CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00. 
# %cs:代码段寄存器
# %ip:指令指针寄存器
# https://blog.csdn.net/SlowIsFastLemon/article/details/103756622

.code16                       # Assemble for 16-bit mode
.globl start
start:
  cli                         # BIOS enabled interrupts; disable  [i386-Page 284 of 421]

  # Zero data segment registers DS, ES, and SS.
  xorw    %ax,%ax             # Set %ax to zero,逻辑异或
  movw    %ax,%ds             # -> Data Segment,数据段=0,所有数据引用，相对于堆栈或字符串目标时除外。
  movw    %ax,%es             # -> Extra Segment,附加段=0,字符串指令的目的地。
  movw    %ax,%ss             # -> Stack Segment,堆栈段=0,所有堆栈推送和弹出。任何使用ESP或EBP作为基址寄存器的内存引用。

  # Physical address line A20 is tied to zero so that the first PCs 
  # with 2 MB would run software that assumed 1 MB.  Undo that.
seta20.1:
  inb     $0x64,%al               # Wait for not busy
  # A20地址线“A20” 用来指代第21位地址线（因为地址线是从零开始编号的）。这一位地址很特殊，在CPU启动之后默认总是0
  testb   $0x2,%al
  jnz     seta20.1

  movb    $0xd1,%al               # 0xd1 -> port 0x64
  outb    %al,$0x64
  # 上面除了 jmp 指令之外的代码，都是用来启用1MB以上的内存访问的
  # 对 0x64 和 0x60 这两个 port 的操作，就是使 A20 地址线生效
  # 历史原因,详见 https://blog.csdn.net/Great_Enterprise/article/details/104063004
seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al                # 根据两个操作数逐位逻辑“与”的结果来设置条件标志
  jnz     seta20.2                # 不等于0
  movb    $0xdf,%al               # 0xdf -> port 0x6
  outb    %al,$0x60

  # Switch from real to protected mode.  Use a bootstrap GDT that makes
  # virtual addresses map directly to physical addresses so that the
  # effective memory map doesn't change during the transition.
  # 从真实模式切换到保护模式。使用引导GDT，使虚拟地址直接映射到物理地址，以便有效的内存映射在转换过程中不会改变。
  lgdt    gdtdesc
  movl    %cr0, %eax
  orl     $CR0_PE, %eax
  movl    %eax, %cr0

//PAGEBREAK!
  # Complete the transition to 32-bit protected mode by using a long jmp
  # to reload %cs and %eip.  The segment descriptors are set up with no
  # translation, so that the mapping is still the identity mapping.
  ljmp    $(SEG_KCODE<<3), $start32

.code32  # Tell assembler to generate 32-bit code now.
start32:
  # Set up the protected-mode data segment registers
  movw    $(SEG_KDATA<<3), %ax    # Our data segment selector
  movw    %ax, %ds                # -> DS: Data Segment
  movw    %ax, %es                # -> ES: Extra Segment
  movw    %ax, %ss                # -> SS: Stack Segment
  movw    $0, %ax                 # Zero segments not ready for use
  movw    %ax, %fs                # -> FS
  movw    %ax, %gs                # -> GS

  # Set up the stack pointer and call into C.
  movl    $start, %esp
  call    bootmain

  # If bootmain returns (it shouldn't), trigger a Bochs
  # breakpoint if running under Bochs, then loop.
  movw    $0x8a00, %ax            # 0x8a00 -> port 0x8a00
  movw    %ax, %dx
  outw    %ax, %dx
  movw    $0x8ae0, %ax            # 0x8ae0 -> port 0x8a00
  outw    %ax, %dx
spin:
  jmp     spin

# Bootstrap GDT
.p2align 2                                # force 4 byte alignment
gdt:
  SEG_NULLASM                             # null seg
  SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)   # code seg
  SEG_ASM(STA_W, 0x0, 0xffffffff)         # data seg

gdtdesc:
  .word   (gdtdesc - gdt - 1)             # sizeof(gdt) - 1
  .long   gdt                             # address gdt


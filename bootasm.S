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
  lgdt    gdtdesc                 # 传入48位给GDTR, 使用平坦内存模型,0-4GB(需要计算?)
  movl    %cr0, %eax              # 控制寄存器CR0, i386-P88
  orl     $CR0_PE, %eax           # PE = 1 保证打开了保护模式的开关,PG = 0 表示只使用分段式，不使用分页
  movl    %eax, %cr0              # 切换到保护模式

//PAGEBREAK!
  # Complete the transition to 32-bit protected mode by using a long jmp
  # to reload %cs and %eip.  The segment descriptors are set up with no
  # translation, so that the mapping is still the identity mapping.
  # 基地址(SEG_KCODE=1)  +  偏移量
  # 在 GDT 中我们的代码段下标是 1 ，所以这里段选择子是 1 << 3 = 0000 0000 0000 1000
  # 在 16 位的段选择子中前 13 位是 GDT 段表下标，这里前 13 位值是 1 代表选择代码段
  # 而我们的代码段是从 0 开始到 4GB 结尾的，所以这里偏移量不用做转换，还是原偏移即可
  ljmp    $(SEG_K CODE<<3), $start32 

.code32  # Tell assembler to generate 32-bit code now.
start32:
  # Set up the protected-mode data segment registers
  # 像上面讲 ljmp 时所说的，这时候已经在保护模式下了
  # 数据段在 GDT 中的下标是 2，所以这里数据段的段选择子是 2 << 3 = 0000 0000 0001 0000
  # 这 16 位的段选择子中的前 13 位是 GDT 段表下标，这里前 13 位的值是 2 代表选择了数据段
  # 这里将 3 个数据段寄存器都赋值成数据段段选择子的值
  movw    $(SEG_KDATA<<3), %ax    # Our data segment selector  段选择子赋值给 ax 寄存器
  movw    %ax, %ds                # -> DS: Data Segment        初始化数据段寄存器
  movw    %ax, %es                # -> ES: Extra Segment       初始化扩展段寄存器
  movw    %ax, %ss                # -> SS: Stack Segment       初始化堆栈段寄存器
  movw    $0, %ax                 # Zero segments not ready for use  ax 寄存器清零
  movw    %ax, %fs                # -> FS                      辅助寄存器清零
  movw    %ax, %gs                # -> GS                      辅助寄存器清零

  # Set up the stack pointer and call into C.
  movl    $start, %esp            # 栈顶被设置为 0x7C00 处
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
  SEG_NULLASM                             # null seg:空
  SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)   # code seg:代码段
  SEG_ASM(STA_W, 0x0, 0xffffffff)         # data seg:数据段
  # \define in asm.h
  # \define SEG_ASM(type,base,lim)                                  
  #      .word (((lim) >> 12) & 0xffff), ((base) & 0xffff);      
  #      .byte (((base) >> 16) & 0xff), (0x90 | (type)),         
  #             (0xC0 | (((lim) >> 28) & 0xf)), (((base) >> 24) & 0xff)
  # STA_X     0x8       // Executable segment
  # STA_W     0x2       // Writeable (non-executable segments)
  # STA_R     0x2       // Readable (executable segments)
gdtdesc:
  .word   (gdtdesc - gdt - 1)             # sizeof(gdt) - 1 = 16 - 1
  .long   gdt                             # address gdt     = 32


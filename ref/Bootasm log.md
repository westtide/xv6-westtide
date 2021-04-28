# Bootasm.s

#### 1.寄存器布局:

<img src="image-20210426155038207.png" alt="image-20210426155038207" style="zoom:30%;" />

```
lin8: %cs=0 %ip=7c00. 
```

\# %cs:代码段寄存器(Code Segment)

\# %ip:指令指针寄存器

8086启动的整体流程:

8086处理器在启动或者重启的时候，会对寄存器执行一个初始化的操作。初始化后的寄存器信息:
`CS：FF FF，其它的寄存器：00 00`。

启动重启计算机，寄存器被初始化

```
CS：FFFF IP：0000
```

FFFF0—> jmp F000：005C

```
CS：F000 IP：005C
```

F005C—>依次执行BIOS中的指令

BIOS所做的最后一件事：将主引导扇区中（0面0道1扇区，最后两个字节为硬盘主引导扇区的有效标志，必须为0x55，0xaa）的内容加载到7C00的位置处。

BIOS的最后一条指令：

```
JMP 0000：7C00
CS：0000 IP：7C00
```

07C00—>执行主引导扇区中的指令
1)加载操作系统自举代码到内存中
2)通过一条跳转指令，使处理器去执行操作系统的自举代码

[8086的启动过程_木子皿--啥都不会的菜鸟-CSDN博客](https://blog.csdn.net/SlowIsFastLemon/article/details/103756622)

#### 2.cli

lin16:

```
  cli                         # BIOS enabled interrupts; disable
```

Page 86 of 421: ***i386***

![截屏2021-04-26 16.15.03](%E6%88%AA%E5%B1%8F2021-04-26%2016.15.03.png)

#### 3.Lin27:inb     $0x64,%al

```
  inb     $0x64,%al               # Wait for not busy,0b1100100
```

[inb $0x64, %al的原理_Great_Enterprise的博客-CSDN博客](https://blog.csdn.net/Great_Enterprise/article/details/104063004)

其实就是在检查和写入 0x64， 0x60 这两个 port ，而前面的文章原文是这样说的：The last code block of boot1 enables access to memory above 1MBand concludes with a jump to the starting point of the BTX server。
也就是说，***上面除了 jmp 指令之外的代码，都是用来启用1MB以上的内存访问的。***

但是， 0x64 和 0x60 不是连着键盘控制器 的吗和内存有什么关系？
***A20地址线“A20” 用来指代第21位地址线（因为地址线是从零开始编号的）。***

这一位地址很特殊，在CPU启动之后默认总是0. 也就是说，即便CPU给地址总线发送的物理地址是 0x101234 ，第21位地址也会被置成零，从而寻址到 0x1234这个内存单元。
上面对 0x64 和 0x60 这两个 port 的操作，就是使 A20 地址线生效，不要总是发个零出去……

***至于 A20 为什么会被禁用，又为什么是用键盘控制器的 port 启用呢？***

这就要从PC诞生之初说起了……A20的历史在PC刚出现的时候，CPU只有一款，那就是8086 ,因为它和后续的 8088既便宜又耐操，所以很快流行起来。

这颗CPU有16位的寄存器，但是却有20条地址线 ，所以 Intel 发明了臭名昭著的用段寄存器访问更多内存的方法。

举个例子， abcd:1234 这个地址（16进制），冒号前面的是段寄存器的值，后面的是程序中访问的地址，那么真正的物理地址计算方法是0xabcd * 0x10 + 0x1234 = 0xacf04 . 这是个20位的地址，刚好可以用在8086的地址总线上。这个计算方式有个很微妙的问题： ffff:ffff 这个最大的地址映射到物理地址 0x10ffef ，TMD都超过20位了…… Intel 的解决方法是装作没看见第21位，将这个地址当作 0xffef 去访问……所以，当时的程序是可以通过访问 1MB 以上的地址，来获得物理地址 0xffef之前的数据的；也真有程序利用了这一点，从而省掉载入段寄存器的操作。

接下来 Intel 与时俱进推出了80286，它还是16位的CPU，但是地址总线一下子扩展到24位，所以CPU不能再对第21位地址视而不见了。

当新的程序访问ffff:ffff 这个地址时，它有可能是真的想访问物理地址 0x10ffef ；但是当旧的程序访问 ffff:ffff 时，它肯定是想要访问 0xffef .由于兼容旧程序是抢占市场的重要手段 ， Intel 决定让80286默认以8086一样的行为工作，也就是对第21位地址视而不见，总是将 A20 置为零。当程序确定它想要访问 1MB 以上的内存时，再通过特定的方式打开 A20.而这个特定的方式——不知道当时 Intel 那帮人怎么想的——就是用键盘控制器上多出来的一个状态位据说原因就是，有人发现那一位刚好多出来了，于是就出现了 boot loader 里捣鼓 0x64 和 0x60 这两个 port 的代码。

地址线比寄存器位数多是个传统；有人知道几乎所有的32位 x86 CPU都有36条地址线么……不过貌似64位的CPU还没到要遵守这个传统的时候XD这也是个传统，AMD大获成功的64位架构也是和32位x86兼容的A20的。未来A20的特殊性估计还会随着x86架构继续存在一段时间，因为虽然已经没有程序会通过 ffff:ffff 地址去访问 0xffef 了，但是几乎所有现代操作系统都会在启动阶段特意去启用A20.由于启用 A20 这个操作实在太恶心了，其实也有人想过别的方法，像是用其他的专用 port ，或是将启用 A20 的操作内置到 BIOS 中。可惜的是这些方法最后都没有被统一，操作系统们也只好用最古老、最保守的 0x64 、 0x60 port了。
一个小细节前面说 80286 有24条地址线，但它还是16位CPU，那怎么访问 ffff:ffff 之后的内存？这个地址换算成物理地址是 0x10ffef ，也就1MB多一点，最高3位的地址线 A21 、 A22 、 A23 不就没用了？没错，在“实模式”下，即使有24条地址线， 80286 也只能访问1MB多一点的内存。Intel 在 80286 身上想要挽回 8086 时期使用段寄存器寻址的错误，推出了“保护模式”，在保护模式下，CPU可以通过页表 将16位虚拟内存地址映射到24位物理地址，所以可以利用所有24位的地址空间。基本上所有现代操作系统都工作在保护模式或者与其相似的“长模式” 下，当CPU地址线增加的时候操作系统只需要更改页表的格式，而且对非法地址的访问会被作为异常处理掉，所以自 80286 以来再也没有出现过类似 A20 的问题。

#### 4.Load Global/Interrupt Descriptor Table (lgdt, lidt)

```
	  lgdt    gdtdesc
```

​		从真实模式切换到保护模式。使用引导GDT，使虚拟地址直接映射到物理地址，以便有效的内存映射在转换过程中不会改变。		

[【学习xv6】从实模式到保护模式 - leenjewel Blog](http://leenjewel.github.io/blog/2014/07/29/[(xue-xi-xv6)]-cong-shi-mo-shi-dao-bao-hu-mo-shi/)

[全局描述符表（GDT） · 《x86汇编语言：从实模式到保护模式》读书笔记 · 看云 (kancloud.cn)](https://www.kancloud.cn/digest/protectedmode/121465)

保护模式下,内存的访问仍然使用<u>***段地址加偏移地址***</u>,对段的描述符有:

- 全局描述符表（Global Descriptor Table, 简称GDT）
- 局部描述符表（Local Descriptor Table,简称LDT）

进入保护模式之前,定义GDT,在CPU内部有一个48位的寄存器:**<u>*GDTR局描述符表寄存器*</u>**

![GDTR](2016-02-29_56d3a8fbd2ada.jpg)

```
- 32位的线性基地址：GDT在内存中的起始线性地址（我们还没有涉及到分页，所以这里的线性地址等同于物理地址，下同，以后同）；
- 16位的表界限：在数值上等于表的大小（总字节数）减去1；
```

注意：在处理器刚上电的时候，基地址默认为0，表界限默认为0xFFFF; 在保护模式初始化过程中，必须给GDTR加载一个新值。

因为表界限是16位的，最大值是0xFFFF，也就是十进制的65535，那么表的大小就是65535+1=65536.又因为一个描述符占用8个字节，所以65536字节相当于8192个描述符（65536/8=8192）.故理论上最多可以定义8192个描述符。实际上，不一定这么多，具体多少根据需要而定。

理论上，GDT可以放在内存中的任何地方。但是，我们必须在进入保护模式之前就定义GDT（不然就来不及了），所以GDT一般都定义在1MB以下的内存范围中。当然，允许在进入保护模式后换个位置重新定义GDT。

GDT:Global Descriptor Table,GDT 表里的每一项叫做“段描述符”，用来记录每个内存分段的一些属性信息，每个“段描述符”占 8 字节

![image-20210426192426047](/Users/xichao/Library/Application Support/typora-user-images/image-20210426192426047.png)

三块“基地址(8+8+16)”组装起来正好就是 32 位的段起始内存地址，两块 Limit 组成该内存分段的长度，接下来依次解释一下其他位所代表的意义：

- P:       0 本段不在内存中
- DPL:     访问该段内存所需权限等级 00 — 11，0为最大权限级别
- S:       1 代表数据段、代码段或堆栈段，0 代表系统段如中断门或调用门
- E:       1 代表代码段，可执行标记，0 代表数据段
- ED:      0 代表忽略特权级，1 代表遵守特权级
- RW:      如果是数据段（E=0）则1 代表可写入，0 代表只读；
           如果是代码段（E=1）则1 代表可读取，0 代表不可读取
- A:       1 表示该段内存访问过，0 表示没有被访问过
- G:       1 表示 20 位段界限单位是 4KB，最大长度 4GB；
           0 表示 20 位段界限单位是 1 字节，最大长度 1MB
- DB:      1 表示地址和操作数是 32 位，0 表示地址和操作数是 16 位
- XX:      保留位永远是 0
- AA:      给系统提供的保留位

```
gdt:
  SEG_NULLASM                             # 空
  SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)   # 代码段
  SEG_ASM(STA_W, 0x0, 0xffffffff)         # 数据（堆栈）段
```

```
宏定义 asm.h
#define SEG_ASM(type,base,lim)                                  \
        .word (((lim) >> 12) & 0xffff), ((base) & 0xffff);      \
        .byte (((base) >> 16) & 0xff), (0x90 | (type)),         \
                (0xC0 | (((lim) >> 28) & 0xf)), (((base) >> 24) & 0xff)

#define STA_X     0x8       // Executable segment
#define STA_W     0x2       // Writeable (non-executable segments)
#define STA_R     0x2       // Readable (executable segments)

```

存疑:

```
gdt:
  .word 0, 0;
  .byte 0, 0, 0, 0                             # 空
  .word 0xffff, 0x0000;
  .byte 0x00, 0x9a, 0xcf, 0x00                 # 代码段
  .word 0xffff, 0x0000;
  .byte 0x00, 0x92, 0xcf, 0x00                 # 数据段
```

#### 4. Control Registers(1386-P88)

![image-20210426200811053](image-20210426200811053.png)

CR0-系统内的控制寄存器

| 第0位PE: 保护允许位    | 0-实模式, 1-**保护模式** |
| :--------------------- | :----------------------- |
| 第1 位MP: 监控协处理位 |                          |
| 第2位EM: 模拟协处理位  | EM=1，不能使用协处理器   |
| 第3位TS: 任务转换位    | TS=1，不能使用协处理器   |
| 第4位ET: 扩展类型位    |                          |
| 第31位PG: 分页允许位   |                          |

CR1是未定义的控制寄存器，供将来的处理器使用。

CR2是页故障线性地址寄存器，保存最后一次出现页故障的全32位线性地址。

CR3是页目录基址寄存器，保存页目录表的物理地址，页目录表总是放在以4K字节为单位的存储器边界上，因此，它的地址的低12位总为0，不起作用，即使写上内容，也不会被理会。

#### 5. long jump

函数间跳转: 需要保存函数上下文

​	函数栈帧:栈桢指针BP、栈顶指针SP

​	PC: 跳转Label语句的地址

​	其他寄存器:GPRs
// Per-CPU state
struct cpu {
  uchar apicid;                // Local APIC ID
  struct context *scheduler;   // swtch() here to enter scheduler
  struct taskstate ts;         // Used by x86 to find stack for interrupt
  struct segdesc gdt[NSEGS];   // x86 global descriptor table
  volatile uint started;       // Has the CPU started?
  int ncli;                    // Depth of pushcli nesting.
  int intena;                  // Were interrupts enabled before pushcli?
  struct proc *proc;           // The process running on this cpu or null
};

extern struct cpu cpus[NCPU];
extern int ncpu;

//PAGEBREAK: 17
// Saved registers for kernel context switches.
// Don't need to save all the segment registers (%cs, etc),
// because they are constant across kernel contexts.
// Don't need to save %eax, %ecx, %edx, because the
// x86 convention is that the caller has saved them.
// Contexts are stored at the bottom of the stack they
// describe; the stack pointer is the address of the context.
// The layout of the context matches the layout of the stack in swtch.S
// at the "Switch stacks" comment. Switch doesn't save eip explicitly,
// but it is on the stack and allocproc() manipulates it.
struct context {
  uint edi;
  uint esi;
  uint ebx;
  uint ebp;
  uint eip;
};

enum procstate { UNUSED, EMBRYO, SLEEPING, RUNNABLE, RUNNING, ZOMBIE };
// 列举:程序的进程状态{新建、准备运行、运行、等待I/O、退出状态中}

// Per-process state: 维护一个进程的众多状态
struct proc {
  uint sz;                     // Size of process memory (bytes)
  pde_t* pgdir;                // Page table:页表,重要,uint,分页硬件在进程运行时使用p->pgdir,记录了保存进程内存的物理页地址
  char *kstack;                // Bottom of kernel stack for this process:内核栈,重要
  enum procstate state;        // Process state:进程状态,重要
  int pid;                     // Process ID
  struct proc *parent;         // Parent process
  struct trapframe *tf;        // Trap frame for current syscall
  struct context *context;     // swtch() here to run process
  void *chan;                  // If non-zero, sleeping on chan
  int killed;                  // If non-zero, have been killed
  struct file *ofile[NOFILE];  // Open files
  struct inode *cwd;           // Current directory
  char name[16];               // Process name (debugging)
};
// p->kstack 是内核栈
// 进程的用户指令运行在用户栈,内核栈为空,用户代码不能运行在内核栈.进程破坏用户栈,内核也能保持运行.
// 进程的系统调用or中断时,进入内核栈,内核代码在进程的内核栈中执行,用户栈数据保存,处于不活跃状态
// 进程的线程交替使用内核栈与用户栈,
// Process memory is laid out contiguously, low addresses first:
//   text
//   original data and bss
//   fixed-size stack
//   expandable heap

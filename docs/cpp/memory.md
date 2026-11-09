---
title: 内存模型、对象布局与内存管理
tags:
  - C++
  - 内存
  - 进阶
---

# 内存模型、对象布局与内存管理

C++ 把“对象在哪、活多久、占多大”交给程序员。面试里的内存题几乎都沿着一条链追问：**变量在哪个区 → 这个区怎么分配 → 对象在内存里长什么样 → 出错时怎么查**。本章沿着这条链走一遍。

## C++ 程序的内存分区

一个进程的虚拟地址空间通常划分为这些区域：

| 区域 | 存放内容 | 生命周期 | 典型大小 |
| --- | --- | --- | --- |
| 代码段 `.text` | 机器指令、只读函数体 | 程序运行期间 | 由代码量决定 |
| 只读数据 `.rodata` | 字符串字面量、`const` 全局、虚表 | 程序运行期间 | 较小 |
| 已初始化数据 `.data` | 初始化不为 0 的全局/静态变量 | 程序运行期间 | 较小 |
| 未初始化数据 `.bss` | 未初始化或初始化为 0 的全局/静态变量 | 程序运行期间 | 较小 |
| 堆 heap | `new` / `malloc` 动态分配 | 手动释放或进程结束 | 可增长，受限于内存 |
| 栈 stack | 局部变量、参数、返回地址 | 函数调用到返回 | 通常 1–8 MB |
| 内存映射区 | `mmap`、共享库、文件映射 | 由映射决定 | 灵活 |

```cpp
#include <cstdio>

int g_init = 1;              // .data
int g_zero;                  // .bss
const char* msg = "literal"; // 指针在 .data，字面量在 .rodata

int main() {
    int local = 0;           // 栈
    int* heap = new int(1);  // 堆
    std::printf("%p %p %p %p\n", (void*)&g_init, (void*)msg, (void*)&local, (void*)heap);
    delete heap;
}
```

!!! warning "分区是链接器/OS 的概念"
    标准只规定对象的 **存储期**（automatic/static/thread/dynamic），不规定“堆在低地址、栈在高地址”。具体布局由平台 ABI 决定，面试时说明这是常见实现即可。

## 栈帧：函数调用发生了什么

每次函数调用会在栈上压入一个 **栈帧（stack frame）**，通常包含：传递给寄存器的溢出参数、返回地址、调用者的栈基址、保存的寄存器、局部变量，以及对齐填充。

```cpp
int deep(int n) {
    return n == 0 ? 0 : 1 + deep(n - 1);   // 每次调用都占一个栈帧
}

int main() {
    // deep(1'000'000);   // 栈溢出：默认栈通常只有几 MB
}
```

- 函数返回时栈指针回退，局部对象的析构函数被调用（若有），栈帧整体失效。
- 栈的生长方向、参数传递方式（寄存器/栈）、红区等由 ABI 决定，x86-64 SysV 与 Windows x64 就不同。
- 线程有独立栈；主线程栈通常 8 MB，子线程默认 1–2 MB（可用 `pthread_attr_setstacksize` 调整）。
- 递归过深、超大局部数组（如 `int a[10'000'000]`）是栈溢出的常见原因；大缓冲区应放堆上或用 `std::vector`。

!!! danger "栈溢出不是“内存不够”"
    栈溢出通常表现为段错误（SIGSEGV）或栈保护触发（`*** stack smashing detected ***`）。它和堆的 `bad_alloc` 是两类问题。

## 堆：malloc/free 与 new/delete

### malloc 的完整流程

`malloc(size)` 只负责分配 **原始字节**，不调用构造函数：

1. 计算所需大小并对齐，向上取整到 chunk。
2. 先查线程缓存（tcache）和 bins 里的空闲 chunk，命中则直接返回。
3. 未命中则从堆顶扩展（`brk`）或向 OS 申请新的内存映射（`mmap`，大块分配常用）。
4. 返回用户区指针；chunk 头部保存大小、前后 chunk 状态等元数据。

`free(ptr)` 根据头部元数据找到 chunk，合并相邻空闲块，放回 bin；不一定立刻还给 OS。

```cpp
#include <cstdlib>

void* mem = std::malloc(64);   // 64 字节，未初始化
// ...
std::free(mem);                // 只释放，不调用析构
```

### new/delete 的完整流程

`new T(args)` 是两步：**分配内存 + 构造对象**；`delete p` 是 **析构 + 释放内存**。

```cpp
struct Point { int x, y; };

Point* p = new Point{1, 2};    // operator new(sizeof(Point)) 后 placement new 构造
delete p;                      // 调用 ~Point()，再 operator delete

int* q = new int(42);          // 内建类型也会“构造”（初始化）
delete q;
```

可以重载 `operator new` / `operator delete` 来接管分配，但一般不要动全局版本：

```cpp
void* operator new(std::size_t n) {
    if (void* p = std::malloc(n)) return p;
    throw std::bad_alloc{};     // 默认行为：失败抛异常
}
```

### placement new

placement new 在 **已有内存** 上构造对象，不分配空间。它常用于内存池、容器和需要手动管理生命周期的场景：

```cpp
#include <new>

struct Point { int x, y; };

void* raw = ::operator new(sizeof(Point));   // 只分配原始内存
Point* p = new (raw) Point{1, 2};            // 在 raw 上构造
p->~Point();                                 // 必须显式析构
::operator delete(raw);                      // 再释放内存
```

!!! warning "placement new 的配对"
    placement new 不分配内存，所以不能用 `delete p`（会去释放一块并非由 `operator new` 分配的内存）。正确顺序是显式调用析构函数，再释放原始缓冲区。

### 为什么 new 失败抛 bad_alloc

标准规定 `new` 分配失败时抛出 `std::bad_alloc`，而不是返回 `nullptr`。这允许构造函数和表达式保持“要么成功、要么异常”的语义。需要“失败返回空”的 C 风格行为时用 `new (std::nothrow)`：

```cpp
#include <new>

int* p = new (std::nothrow) int[1'000'000'000];
if (!p) { /* 分配失败，p 为 nullptr */ }
delete[] p;
```

## new/delete 与 malloc/free 对比

| 维度 | `new` / `delete` | `malloc` / `free` |
| --- | --- | --- |
| 是否调用构造/析构 | 是 | 否 |
| 返回类型 | 类型化指针 | `void*`，需转换 |
| 大小 | 编译器推导 | 手动传字节数 |
| 失败行为 | 默认抛 `bad_alloc` | 返回 `nullptr` |
| 是否可重载 | 可重载 `operator new` | 不可 |
| 数组 | `new[]` / `delete[]` | 自行计算总大小 |
| 与另一组混用 | **UB** | **UB** |

```cpp
int* a = new int[10];
// delete a;       // UB：数组 cookie 与元素析构都会出问题
delete[] a;

std::string* ss = new std::string[3];
delete[] ss;       // 每个元素都被析构，然后释放整块内存
```

`new[]` 对类类型可能额外保存元素个数（array cookie），`delete` 不会按数组方式读取它；对非平凡析构类型，`delete` 只析构第一个元素，其余元素泄漏。

!!! danger "不要混用"
    `new` 配 `free`、`malloc` 配 `delete` 都是 UB。它们的元数据布局和分配器可能完全不同，ASan 会直接报 alloc-dealloc-mismatch。

## 内存对齐

CPU 访问对齐地址通常更快，某些架构（ARM、部分 RISC）访问未对齐地址会直接 fault。因此编译器会在成员之间插入 **padding**，保证每个成员的地址满足其 `alignof`。

对齐规则（简化）：成员偏移必须是自身对齐值的整数倍；结构体总大小必须是最大成员对齐值的整数倍；结构体对齐值等于成员的最大对齐值。

```cpp
struct A { char c; int i; short s; };  // 常见布局：c(1)+pad(3)+i(4)+s(2)+pad(2) = 12
struct B { int i; short s; char c; };  // i(4)+s(2)+c(1)+pad(1) = 8

// 调整成员顺序，从大到小排，通常能减少 padding
```

```cpp
#include <cstddef>

struct alignas(16) Vec4 { float x, y, z, w; };
static_assert(alignof(Vec4) == 16);
static_assert(sizeof(Vec4) == 16);

struct Packed { char c; int i; };
#pragma pack(push, 1)
struct Packed1 { char c; int i; };
#pragma pack(pop)
static_assert(sizeof(Packed1) == 5);   // 取消填充，但可能引发未对齐访问
```

!!! warning "`#pragma pack` 的代价"
    压缩布局能省网络协议/文件格式的空间，但成员可能未对齐，访问变慢甚至在严格对齐平台崩溃。跨平台协议优先手动序列化，而不是直接 `memcpy` 结构体。

## 对象内存布局

### 空类与成员

空类 `sizeof` 为 1：标准要求同类型的不同对象地址不同，必须占至少一个字节。空基类优化（EBO）允许空基类在派生类中不额外占空间。

```cpp
struct Empty {};
static_assert(sizeof(Empty) == 1);   // 保证 &a != &b

struct Base {
    virtual ~Base() = default;       // 引入 vptr
    int b = 0;
};
struct Derived : Base {
    int d = 0;
};
// x86-64 常见布局：vptr(8) + b(4) + d(4)，通常 16 或 24 字节（尾部 padding 是否复用由 ABI 决定）
```

有虚函数时，对象里通常有一个 **vptr** 指向该类的虚函数表。Itanium ABI 把 vptr 放在偏移 0；MSVC 也类似，但标准不保证位置，不要依赖。

### 继承与对象切片

单继承通常把基类子对象放在派生类对象的起始位置，因此基类指针指向派生类对象时地址不变；多继承中非首个基类子对象有偏移，`static_cast`/`dynamic_cast` 会自动调整指针值。

```cpp
struct Base2 { virtual ~Base2() = default; };
struct Derived2 : Base2 { int extra = 1; };

void take(Base2 b) {}     // 按值传递：对象切片
Derived2 d;
take(d);                  // 只拷贝 Base2 部分，extra 丢失，虚函数也不再是 Derived2 版本
```

!!! danger "切片"
    用基类 **值** 接收派生类对象会切片；用 `Base&` 或 `Base*` 才能保留动态类型和多态。容器 `std::vector<Base>` 存放派生类对象同样会切片。

## sizeof 专题

| 表达式 | 典型结果 | 说明 |
| --- | --- | --- |
| `sizeof(char)` | 1 | 标准保证 |
| `sizeof(Empty)` | 1 | 空类至少 1 字节 |
| `sizeof(含虚函数类)` | 指针大小 | 通常只多一个 vptr，可能还有 padding |
| `sizeof(数组)` | 元素大小 × 个数 | 数组名未退化时 |
| `sizeof(指针)` | 4 或 8 | 与平台有关 |
| `sizeof(引用)` | 被引用类型的大小 | 引用不是对象 |
| `sizeof(std::string)` | 实现相关 | libstdc++ 通常 32，MSVC 也可能 32，不可假设 |

虚继承会引入虚基类表指针/偏移，布局更复杂，`sizeof` 因实现而异，不要背具体数字。仅含一个虚函数的类，常见实现下 `sizeof` 等于一个指针，但标准不保证。

## 内存问题与 RAII

| 问题 | 表现 | 解决 |
| --- | --- | --- |
| 内存泄漏 | 进程 RSS 持续增长 | RAII、智能指针、Valgrind |
| 内存溢出 | 越界写破坏相邻数据 | 边界检查、容器、ASan |
| 野指针 | 未初始化就解引用 | 初始化为 `nullptr` |
| double free | 同一指针释放两次 | 释放后置空、明确所有权 |
| use-after-free | 释放后继续访问 | 智能指针、生命周期审查 |

RAII 的核心：**把资源生命周期绑定到对象生命周期**，析构函数负责释放，异常路径也不会漏。

```cpp
#include <memory>
#include <vector>

void safe() {
    auto p = std::make_unique<int>(42);   // 独占所有权
    std::vector<int> v(100);              // 自动管理缓冲区
    // 即使这里抛异常，p 和 v 也会被正确析构
}   // 离开作用域：v 先析构，p 后析构（逆序）
```

## 内存池与 arena

频繁 `new`/`delete` 小对象的开销来自：分配器加锁、元数据、碎片、缓存不友好。内存池一次申请大块，再切成固定大小的小块，把分配变成指针递增或空闲链表弹出。

```cpp
#include <cstddef>
#include <new>

class Arena {
public:
    explicit Arena(std::size_t bytes)
        : buf_(new char[bytes]), size_(bytes), offset_(0) {}
    ~Arena() { delete[] buf_; }

    void* alloc(std::size_t n) {
        if (offset_ + n > size_) throw std::bad_alloc{};
        void* p = buf_ + offset_;
        offset_ += n;
        return p;
    }

    void reset() { offset_ = 0; }   // 整体回收，不逐个释放

private:
    char* buf_;
    std::size_t size_;
    std::size_t offset_;
};
```

这个简化版未处理对齐和析构，只演示思路。真实的内存池还要考虑：按大小分级、空闲链表、线程本地缓存、对齐向上取整、对象析构。

!!! tip "适用场景"
    生命周期相近、频繁创建销毁、大小固定的小对象（连接、事件、语法树节点）最适合池化。池化会推迟内存归还，内存峰值可能变高，要配合监控。

## 排查工具

| 工具 | 用途 | 特点 |
| --- | --- | --- |
| AddressSanitizer（ASan） | 越界、UAF、double free、泄漏 | 编译期插桩，开销约 2 倍，首选 |
| Valgrind Memcheck | 内存错误与泄漏 | 不需要重编译，慢 10–30 倍 |
| Massif | 堆内存峰值与调用栈 | Valgrind 工具，适合定位内存增长 |
| `/proc/<pid>/status` | `VmRSS`、`VmSize` | Linux 实时观察，不能定位到代码 |
| core dump + gdb | 崩溃现场 | 需要开启 core，查看栈和寄存器 |

```bash
g++ -std=c++17 -g -fsanitize=address,undefined demo.cpp -o demo
./demo
```

ASan 报告会给出出错地址、读写大小、分配与释放的调用栈，是定位 use-after-free 最快的方式。生产环境可用其低开销版本或开启采样。

## 面试追问

???+ question "面试追问：static 变量在哪个区？"
    已初始化且非 0 的全局/静态变量在 `.data`；未初始化或初始化为 0 的在 `.bss`；函数内的 `static` 局部变量也在 `.data`/`.bss`（不在栈上），第一次执行到定义处时初始化，C++11 起线程安全。`thread_local` 则在线程局部存储区。

???+ question "面试追问：字符串字面量存在哪？"
    通常存在只读数据段 `.rodata`，程序运行期间一直有效。相同字面量是否合并由实现决定；修改它是 UB。`char a[] = "hi";` 会把字面量拷贝到栈上的数组，修改 `a` 合法。

???+ question "面试追问：malloc 返回的是虚拟地址还是物理地址？"
    返回进程虚拟地址空间中的地址。物理页由操作系统在首次访问时按需映射（demand paging），`malloc` 本身通常不触碰物理内存。因此“分配成功”不等于“物理内存已就绪”，大块分配可能直到写入才 OOM。

???+ question "面试追问：堆和栈谁更快？"
    栈分配只是移动栈指针，几乎零开销，且内存连续、缓存友好，通常更快；堆分配要走分配器、可能加锁、维护元数据，还可能有缺页和碎片。但“堆一定慢”是过度简化：成熟分配器的 tcache 命中很快，而巨大栈对象会引发栈扩容/溢出。

???+ question "面试追问：`delete this` 合法吗？"
    在对象由 `new` 创建、且删除后不再访问任何成员的前提下，语法上可行，常见于引用计数对象自减到 0 时。但它是极危险的设计：调用后不能访问成员、不能返回后继续使用对象，也不能用于栈对象或数组元素。现代 C++ 用 `shared_ptr` 的 deleter 替代。

???+ question "面试追问：为什么空类大小是 1 而不是 0？"
    标准要求同一类型的两个不同对象必须有不同地址。若 `sizeof(Empty) == 0`，数组元素会重叠，`&a == &b` 无法区分。空基类优化允许空基类子对象占 0 字节，但完整对象至少 1 字节。

## 下一步

- 指针与引用的语义和陷阱：[指针与引用](pointers.md)
- 构造、析构、拷贝与移动如何管理资源：[类与对象](classes.md)
- 虚函数表与多态下的对象布局：[继承与多态](oop.md)
- 分配器、缓存与性能优化：[性能与调试](performance.md)

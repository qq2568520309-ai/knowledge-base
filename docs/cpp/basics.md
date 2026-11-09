---
title: 基础语法与类型系统
tags:
  - C++
  - 基础
---

# 基础语法与类型系统

这一章把 C++ 的“地基”一次铺平：一个源文件如何变成程序、类型到底占多少字节、变量怎样初始化、转换何时发生、关键字各自解决什么问题。每个知识点都按 **怎么用 → 底层发生了什么 → 面试怎么追问** 展开。

## 从源码到程序的最小认知

一个 `.cpp` 文件加上它 `#include` 进来的所有头文件，构成一个 **translation unit（编译单元）**。编译器独立编译每个 TU 生成目标文件，链接器再把它们拼成可执行文件。

- **声明（declaration）**：告诉编译器“有这么个名字，类型是什么”，可以重复出现。
- **定义（definition）**：真正分配存储或给出函数体，全程序只能有一份（`inline` 变量/函数例外）。

```cpp
// math.hpp：只放声明，被多个 .cpp 包含
#pragma once
int add(int a, int b);

// math.cpp：给出定义
#include "math.hpp"
int add(int a, int b) { return a + b; }
```

!!! tip "头文件里能放什么"
    能放：类定义、模板、`inline` 函数、`constexpr` 函数、`extern` 声明、类型别名。
    不能放：非 `inline` 的普通函数定义、非 `extern` 的全局变量定义——否则多个 TU 包含它就会重复定义。

!!! warning "ODR 一句话"
    **One Definition Rule**：同一个实体在全程序内最多一个定义；类、模板、`inline` 函数允许多个 TU 各有一份，但必须逐 token 相同。违反 ODR 往往不报错，只在链接期或运行期以奇怪方式爆炸。

## 基本数据类型与大小

C++ 只规定 **最小保证** 和相对大小，不规定 `int` 一定是 4 字节。工程上需要确定宽度时用 `<cstdint>` 的定宽整数。

| 类型 | 常见大小（64 位） | 标准保证 |
| --- | --- | --- |
| `char` | 1 | 恰好 1 字节，`sizeof(char) == 1` |
| `short` | 2 | 至少 16 位，且不宽于 `int` |
| `int` | 4 | 至少 16 位，通常是最自然的字长 |
| `long` | Linux 8 / Windows 4 | 至少 32 位，且不窄于 `int` |
| `long long` | 8 | 至少 64 位 |
| `float` / `double` | 4 / 8 | 通常 IEEE-754，但标准未强制 |
| `bool` | 1 | 取值 `true` / `false` |
| 指针 | 8（64 位） | 与地址空间宽度相关 |

```cpp
#include <cstdint>
#include <climits>

static_assert(sizeof(char) == 1);
static_assert(sizeof(int) >= 2);
static_assert(sizeof(std::int32_t) == 4);   // 定宽类型：宽度写死
static_assert(sizeof(std::intptr_t) == sizeof(void*));
```

`sizeof` 是 **编译期运算符**，不是函数：`sizeof(int)`、`sizeof x` 都合法，结果是 `std::size_t`；标准 C++ 中操作数不会被求值，C 的 VLA 也不属于标准 C++。

!!! danger "不要假设平台"
    `long` 在 Windows 是 4 字节、在 64 位 Linux 是 8 字节；`char` 是否有符号由实现决定。跨平台序列化、哈希、网络协议一律用 `std::int32_t` / `std::uint64_t`。

## 变量初始化

C++ 的初始化方式多，规则也不同：

```cpp
int a;          // 默认初始化：块作用域内值未定义（indeterminate）
int b{};        // 值初始化：b == 0
int c = 42;     // 拷贝初始化
int d(42);      // 直接初始化
int e{42};      // 列表初始化（uniform initialization）
// int f{3.14}; // 编译错误：double -> int 是窄化转换

static int g;   // 静态存储期：零初始化，g == 0
```

列表初始化用 `{}`，禁止窄化转换，也避免了“最令人烦恼的解析”（most vexing parse）：`Widget w2();` 声明的是函数而不是对象，`Widget w3{};` 才是值初始化。

`std::initializer_list` 会让 `{}` 优先匹配列表构造函数，这是 `vector` 的经典坑：

```cpp
#include <vector>
std::vector<int> v1(3, 7);   // 3 个元素，每个是 7
std::vector<int> v2{3, 7};   // 2 个元素：3 和 7
```

全局/静态变量先零初始化，再执行动态初始化；**不同 TU 之间的动态初始化顺序未定义**，这就是 static initialization order fiasco：

```cpp
// a.cpp
int compute(); int g = compute();   // 动态初始化
// b.cpp
extern int g;
int h = g * 2;   // g 可能还没动态初始化，h 可能是 0
```

!!! tip "解决初始化顺序"
    用 function-local static 延迟初始化（C++11 起初始化线程安全），或改成 `constexpr` 常量。

???+ question "面试追问：`int x;` 和 `int x{};` 有什么区别？"
    `int x;` 在函数内是默认初始化，值不确定，读它是未定义行为；`int x{};` 是值初始化，保证为 0。在全局/静态作用域，两者都会先零初始化，此时没有区别。

## 类型转换

隐式转换发生在赋值、传参、算术运算和返回值处。小整数类型会先做 **整型提升（integral promotion）** 到 `int`，这经常导致重载决议和 `printf` 的意外。

C++ 有四种显式转换：

| 转换 | 用途 | 风险 |
| --- | --- | --- |
| `static_cast` | 相关类型间转换：数值、上行/下行转换、`void*` 转回 | 下行转换不做运行期检查 |
| `dynamic_cast` | 多态类型的安全下行/交叉转换 | 需要 RTTI，有运行期开销，失败返回空/抛异常 |
| `const_cast` | 去掉或加上 `const`/`volatile` | 修改原本就 const 的对象是 UB |
| `reinterpret_cast` | 按位重新解释，指针与整数互转 | 最危险，平台相关，几乎无法移植 |

```cpp
#include <cstdint>

double d = 3.9;
int i = d;                                  // 隐式转换：截断为 3
auto p = static_cast<void*>(&i);            // 指针类型转换
auto addr = reinterpret_cast<std::uintptr_t>(p);

const int ci = 1;
int* bad = const_cast<int*>(&ci);           // 能编译
// *bad = 2;                                // UB：ci 本身就是 const 对象
```

`dynamic_cast` 要求基类至少有一个虚函数：

```cpp
struct Base { virtual ~Base() = default; };
struct Derived : Base { void hello() const {} };

void f(Base* b) {
    if (auto* p = dynamic_cast<Derived*>(b)) p->hello();  // 失败时 p 为 nullptr
}
```

!!! warning "C 风格转换"
    `(int)x`、`int(x)` 会依次尝试 `const_cast`、`static_cast`、`reinterpret_cast`，你无法从代码看出实际用了哪种。新代码一律用四种具名转换，便于搜索和审查。

## 关键字专题

### const：只读承诺

`const` 修饰对象表示“不通过这个名字修改”。在指针上有 **顶层 const**（指针本身不可变）和 **底层 const**（指向的对象不可变）之分，详见 [指针与引用](pointers.md)。

```cpp
const int k = 10;          // 对象只读
int x = 1;
const int* p = &x;         // 底层 const：不能通过 p 改 x
int* const q = &x;         // 顶层 const：q 不能改指向
```

`const` 成员函数承诺不修改对象的非 `mutable` 成员，也是重载的依据：

```cpp
class Buffer {
public:
    int& at(int i) { return data_[i]; }
    const int& at(int i) const { return data_[i]; }   // const 重载
private:
    int data_[16]{};
};
```

### static：一词四义

| 位置 | 含义 |
| --- | --- |
| 全局变量/函数 | 内部链接，仅当前 TU 可见 |
| 局部变量 | 静态存储期，只初始化一次，函数退出不销毁 |
| 类成员变量 | 属于类而非对象，所有对象共享，需类外定义（C++17 `inline static` 除外） |
| 类成员函数 | 没有 `this`，不能访问非静态成员，不能是 `virtual` |

```cpp
void counter() { static int calls = 0; ++calls; }   // 首次初始化线程安全

struct Widget {
    static int count;                  // 声明
    static constexpr int kMax = 10;    // C++17 起隐式 inline，无需类外定义
};
int Widget::count = 0;                 // 定义
```

### volatile、extern、inline

- `volatile`：禁止编译器把每次读写优化掉，用于内存映射 I/O、信号处理。**它不提供原子性，也不建立线程间同步**，不要拿它当锁。
- `extern`：声明“定义在别处”，常用于全局变量跨 TU 共享；`extern "C"` 则关闭 C++ 名字修饰，供 C 调用。
- `inline`：现代语义是“允许多个 TU 定义同一函数/变量，链接器合并”，优化器是否内联与它无关。

### constexpr 与 consteval

```cpp
constexpr int square(int x) { return x * x; }   // 可用于编译期，也可运行期
static_assert(square(5) == 25);

consteval int twice(int x) { return x * 2; }    // C++20：必须编译期求值
// int n = 3; twice(n);                         // 错误：n 不是常量表达式
```

`const` 表示运行期只读，`constexpr` 表示“可以出现在常量表达式里”。C++20 的 `consteval` 更严格，函数只能在编译期调用。

### mutable、explicit、register

- `mutable`：允许在 `const` 成员函数里修改该成员，用于缓存、互斥量、引用计数。
- `explicit`：禁止单参数构造函数的隐式转换（C++11 起也作用于转换运算符）。
- `register`：C++17 起已移除，不要再使用。

```cpp
struct Meter {
    explicit Meter(int v) : value(v) {}
    int value;
};

// Meter m = 42;      // 错误：explicit 阻止隐式转换
Meter m{42};          // 正确
```
## auto 与 decltype

`auto` 按模板实参推导规则工作：**丢弃顶层 const 和引用**；要保留就写 `auto&`、`const auto&`。

```cpp
int x = 0;
int& rx = x;
const int cx = 1;

auto a = rx;          // int：引用被丢弃
auto b = cx;          // int：顶层 const 被丢弃
auto& c = cx;         // const int&
decltype(rx) d = x;   // int&：decltype 保留引用
decltype(x) e = x;    // int
decltype((x)) f = x;  // int&：带括号是表达式，x 是左值
```

!!! warning "`decltype((x))` 的括号"
    `decltype(x)` 看的是名字的声明类型；`decltype((x))` 看的是表达式的值类别。加一层括号，左值就变成引用类型。这是模板转发和返回值推导的常见考点。

C++14 起函数返回类型可写 `auto`，用 `decltype(auto)` 才能保留引用：

```cpp
auto add(int a, int b) { return a + b; }              // int
decltype(auto) first(std::vector<int>& v) { return v[0]; }  // int&
```

## 运算符与表达式

优先级只需记住几个高频坑：`*p++` 是 `*(p++)`；`a = b = c` 从右结合；`&` 的优先级低于 `==`，所以 `if (x & 1 == 0)` 实际是 `x & (1 == 0)`。

```cpp
int i = 0;
int j = i++ + ++i;   // UB：同一表达式内对 i 多次无序列修改，不要写

unsigned flags = 0b1010u;
flags |= (1u << 2);                       // 置位
bool has_bit1 = (flags & (1u << 1)) != 0; // 判断某位，务必加 != 0
```

`&&` 和 `||` 有短路求值，常用来保护空指针：`if (p != nullptr && p->value > 0)`，右侧只在左侧为真时求值。

整数溢出分两种：**有符号溢出是 UB**，编译器可以假设它不发生并做激进的优化；**无符号溢出按 2^n 回绕**，有定义但常是逻辑错误。

```cpp
#include <climits>
int max = INT_MAX;
// max + 1;          // UB，可能被优化成任意结果
unsigned u = 0u;
--u;                 // UINT_MAX，定义良好
```

C++17 收紧了求值顺序（如赋值右侧先于左侧），但同一表达式中对同一对象的多次无序列修改仍然是 UB。面试中遇到 `i++ + ++i`，正确回答是“未定义行为”，而不是某个具体数字。

## 作用域与生命周期

| 存储期 | 例子 | 生命周期 |
| --- | --- | --- |
| automatic | 局部变量 | 进入作用域构造，离开析构 |
| static | 全局、`static` 局部、类静态成员 | 程序启动到结束 |
| thread | `thread_local` | 线程开始到结束，每线程一份 |
| dynamic | `new` 出来的对象 | 从 `new` 到 `delete` |

内层作用域的同名变量会 **遮蔽（shadow）** 外层，名字查找从内向外，找到即停：

```cpp
int x = 1;
void f() {
    int x = 2;        // 遮蔽全局 x
    {
        int x = 3;    // 再遮蔽
    }
}
thread_local int tls = 0;   // 每个线程独立一份
```

## 预处理

预处理器在真正编译前做文本替换，不理解类型和作用域，因此宏很容易出问题：

```cpp
#define SQUARE(x) ((x) * (x))
int a = SQUARE(i++);   // 展开为 ((i++) * (i++))：自增两次，UB

inline int square(int x) { return x * x; }   // 优先用函数或 constexpr
```

头文件保护两种写法，`#pragma once` 简洁但非标准，include guard 可移植：

```cpp
#ifndef PROJECT_MATH_HPP
#define PROJECT_MATH_HPP
// 声明与 inline 定义
#endif
```

条件编译与预定义宏常用于平台适配：

```cpp
#if defined(_WIN32)
  #define PLATFORM "Windows"
#elif defined(__linux__)
  #define PLATFORM "Linux"
#endif
static_assert(__cplusplus >= 201703L, "需要 C++17");
```

!!! tip "调试宏"
    `__FILE__`、`__LINE__`、`__func__` 可用于日志；`#x` 把参数变成字符串，`x##y` 拼接 token。但能用 `constexpr`、模板、`if constexpr` 解决的，不要用宏。

## 常见面试题小结

| 问题 | 关键结论 |
| --- | --- |
| `sizeof` 和 `strlen` 区别 | `sizeof` 编译期算字节数（含 `\0`）；`strlen` 运行期数到 `\0`，不含 `\0` |
| `i++ + ++i` 的结果 | 未定义行为，没有可移植答案 |
| `const` 和 `constexpr` | 前者运行期只读，后者可用于常量表达式 |
| `static` 的四种含义 | 内部链接、静态存储期、类共享、无 `this` |
| `auto` 为什么丢引用 | 按模板实参推导，顶层 cv 和引用被剥离 |
| 有符号和无符号溢出 | 有符号 UB；无符号按模回绕 |
| `NULL` 和 `nullptr` | `NULL` 常是整型 0，`nullptr` 是 `std::nullptr_t`，类型安全 |

## 下一步

- 指针、引用与 `const` 的组合规则：[指针与引用](pointers.md)
- 这些类型在内存里究竟怎么排布：[内存模型](memory.md)
- 编译、链接与 ODR 的完整细节：[编译与链接](build.md)

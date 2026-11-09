---
title: 指针、引用、数组与 const
tags:
  - C++
  - 基础
  - 指针
---

# 指针、引用、数组与 const

指针和引用是 C++ 面试的第一道分水岭：能说出“指针存地址、引用是别名”只是入门，能讲清引用在底层是否占空间、数组名什么时候退化、`const` 修饰的到底是哪一层，才算过关。本章按“本质 → 组合规则 → 常见陷阱”推进。

## 指针本质

指针是一个保存地址的对象，它同时有 **地址值** 和 **所指类型** 两个属性。类型决定解引用时读多少字节、如何解释，以及指针运算的步长。

```cpp
int x = 42;
int* p = &x;       // p 保存 x 的地址
*p = 43;           // 解引用，等价于 x = 43
static_assert(sizeof(p) == sizeof(void*));

void* raw = p;                      // void* 只保留地址，丢失类型
auto back = static_cast<int*>(raw); // 转回来必须自己保证类型正确
```

`void*` 不能解引用，也不能做算术；它主要用于内存分配、C 接口和类型擦除的边界。

### nullptr 与 NULL

```cpp
int* p1 = nullptr;   // std::nullptr_t，类型安全
int* p2 = NULL;      // 通常是 0 或编译器内建的 __null
```

`NULL` 在 C++ 里往往就是整型常量 `0`，在重载决议时可能选错版本：

```cpp
void f(int);
void f(char*);
// f(NULL);          // 可能调用 f(int)，与直觉不符
f(nullptr);          // 明确调用 f(char*)
```

!!! tip "现代写法"
    一律用 `nullptr`。它到任意指针类型的转换是唯一的，不会退化成整数，也不会和 `bool` 之外的类型产生歧义。

## 指针与引用

引用是已存在对象的别名，**必须初始化，且不能重新绑定**；指针可以为空、可以改指向、可以多级。

```cpp
int a = 0, b = 1;
int& r = a;      // r 绑定 a，之后 r 永远是 a 的别名
r = 5;           // a == 5
r = b;           // 仍是给 a 赋值，不是让 r 改绑到 b

int* p = &a;
p = &b;          // 指针可以改指向
```

### 引用的底层实现

大多数编译器把引用实现为“自动解引用的常量指针”，但这只是实现细节，标准不保证：

```cpp
int x = 1;
int& r = x;
// 常见实现：r 的地址就是 &x；sizeof(r) == sizeof(int)；&r == &x
```

作为类成员或函数参数时，引用通常占一个指针大小的空间；作为局部变量且被完全优化掉时，可能不占任何存储。所以“引用占不占内存”要分语境回答。

| 维度 | 指针 | 引用 |
| --- | --- | --- |
| 是否可为空 | 可以 | 不可以（合法程序内） |
| 是否可重绑定 | 可以 | 不可以 |
| 是否必须初始化 | 不必须（但强烈建议） | 必须 |
| `sizeof` | 指针本身大小 | 被引用对象的大小 |
| 多级 | 支持 `int**` | 不支持“引用的引用”，会折叠 |
| 数组 | 支持指针数组 | 不支持引用数组 |
| 自增含义 | 移动到下一个元素 | 修改被引用对象的值 |

函数传参的选择原则：

```cpp
void byValue(int x)   { x = 1; }              // 小对象、只读拷贝
void byPtr(int* x)    { if (x) *x = 1; }      // 需要表达“可空”
void byRef(int& x)    { x = 1; }              // 需要修改且不可空
void byConstRef(const std::string& s);        // 大对象只读，避免拷贝

int a = 0;
byValue(a); byPtr(&a); byRef(a);
```

!!! note "何时用指针参数"
    需要“没有值”这一语义时用指针（如 `f(const Config* cfg)` 允许传 `nullptr`）；其余情况优先 `T&` 或 `const T&`。输出参数用引用比二级指针清晰。

## const 与指针的三种写法

从变量名开始 **从右向左读**，`const` 修饰它左边最近的东西（若左边没有类型，则修饰右边）：

```cpp
int x = 1, y = 2;

const int* p1 = &x;         // p1 指向 const int：不能通过 p1 改 x
int const* p2 = &x;         // 同上，写法等价
int* const p3 = &x;         // p3 是 const 指针：不能改指向
const int* const p4 = &x;   // 两者都 const

// *p1 = 3;   // 错误
p1 = &y;      // 正确
// p3 = &y;   // 错误
*p3 = 3;      // 正确
```

| 写法 | 能否改指向 | 能否改所指对象 |
| --- | --- | --- |
| `const int*` / `int const*` | 能 | 不能 |
| `int* const` | 不能 | 能 |
| `const int* const` | 不能 | 不能 |

!!! warning "顶层 const 与函数签名"
    函数参数里的 **顶层 const 会被忽略**：`void f(int*)` 和 `void f(int* const)` 是同一个函数，不能重载。底层 const 不同则是不同的重载。

## 数组与指针

数组名在大多数表达式里会 **退化（decay）** 为指向首元素的指针，但并非所有场景：

```cpp
int arr[5] = {1, 2, 3, 4, 5};
int* p = arr;            // 退化为 &arr[0]
int (*pa)[5] = &arr;     // 指向整个数组的指针，类型是 int(*)[5]

static_assert(sizeof(arr) == 5 * sizeof(int));  // 未退化
static_assert(sizeof(p) == sizeof(void*));
static_assert(sizeof(*pa) == sizeof(arr));
```

`arr` 与 `&arr` 的值相同，但类型不同：前者退化为 `int*`，后者是 `int(*)[5]`；`arr + 1` 前进一个 `int`，`&arr + 1` 前进整个数组。

### 二维数组、指针数组与数组指针

```cpp
int m[2][3] = {{1, 2, 3}, {4, 5, 6}};
int (*row)[3] = m;       // 指向一行，row + 1 跳过 3 个 int
int* flat = &m[0][0];    // 二维数组内存连续，可扁平访问

int* a[3];               // 指针数组：3 个 int*
int (*b)[3];             // 数组指针：1 个指向 int[3] 的指针
```

`int* a[3]` 先看 `a[3]`，说明是数组，元素类型 `int*`；`int (*b)[3]` 括号让 `b` 先与 `*` 结合，说明是指针，指向 `int[3]`。

### 字符串字面量

```cpp
const char* s = "hello";   // 字面量在只读区，不能修改
char t[] = "hello";        // 拷贝到栈上，可以修改
static_assert(sizeof("hello") == 6);  // 含结尾 '\0'
```

C++11 起字符串字面量的类型是 `const char[N]`，用 `char*` 接收属于 ill-formed（旧代码可能靠编译器扩展通过）。修改字面量是未定义行为。

## 指针运算与越界

指针算术只在同一个数组对象（含 one-past-the-end）内有定义：

```cpp
#include <cstddef>

int a[5] = {};
int* begin = a;
int* end = a + 5;              // one-past-the-end：可比较，不可解引用
std::ptrdiff_t n = end - begin;  // 5

// int* bad = a + 6;            // UB，即使不解引用
```

两个指针相减得到 `std::ptrdiff_t`，单位是元素个数而不是字节数。迭代器就是指针的泛化：随机访问迭代器支持 `+`、`-`、`<`，本质规则与指针一致。

!!! danger "越界不是“多读一点”"
    越界写可能破坏栈帧、堆元数据或相邻对象；越界读可能读到敏感数据。编译器还会假设越界不发生，据此做优化。用 `std::vector::at`、迭代器和 sanitizer 兜底。

## 函数指针与回调

函数指针保存函数的入口地址，类型由返回值和参数列表决定：

```cpp
int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }

using BinOp = int (*)(int, int);          // C++11 别名，比 typedef 直观
int apply(int a, int b, BinOp op) { return op(a, b); }

int main() {
    BinOp op = &add;                      // 函数名可隐式转成指针
    return apply(3, 4, op) == 7 ? 0 : 1;
}
```

`std::function` 能装函数指针、lambda、函数对象，代价是类型擦除和可能的堆分配：

```cpp
#include <functional>

std::function<int(int, int)> f = add;
f = [](int a, int b) { return a * b; };   // 可携带捕获
```

| 方式 | 开销 | 适用 |
| --- | --- | --- |
| 函数指针 | 一次间接调用，无堆分配 | C 接口、简单回调 |
| `std::function` | 类型擦除，可能堆分配 | 需要保存任意可调用对象 |
| 模板参数 | 可内联，零开销 | 性能敏感的泛型代码 |

成员函数指针需要绑定对象才能调用：

```cpp
struct Widget {
    int value = 7;
    int get() const { return value; }
};

int Widget::* pm = &Widget::value;
int (Widget::* pf)() const = &Widget::get;

Widget w;
int v = w.*pm;          // 7
int g = (w.*pf)();      // 7
```

## 二级指针、指针引用与动态数组

要在函数内修改“指针本身”，需要传指针的指针或指针的引用：

```cpp
void allocate(int** out)  { *out = new int(42); }
void allocate2(int*& out) { out = new int(42); }   // 更清晰

int* p = nullptr;
allocate(&p);
delete p;
allocate2(p);
delete p;
```

动态数组必须 `new[]` / `delete[]` 配对：

```cpp
int* arr = new int[10]();   // 值初始化，10 个 0
delete[] arr;               // 不能写 delete arr

std::string* ss = new std::string[3];
delete[] ss;                // 每个元素都会析构
```

`new[]` 可能额外保存元素个数（array cookie），`delete` 与 `delete[]` 混用是 UB；对类类型还会导致只析构第一个元素。

## 字符与字符串

```cpp
#include <cstring>
#include <string>

char buf[] = "hello";
const char* p = buf;
std::size_t n1 = std::strlen(p);   // 5：数到 '\0'
std::size_t n2 = sizeof(buf);      // 6：含 '\0'

std::string s = buf;
const char* c = s.c_str();         // 只读视图，s 修改后可能失效
```

C 字符串函数的风险：`strcpy`/`strcat` 不检查目标容量；`strlen` 遇到缺失的 `\0` 会越界读；`sprintf` 可能溢出。现代 C++ 优先 `std::string`、`std::string_view`（C++17）。

!!! warning "`c_str()` 的生命周期"
    `c_str()` 返回的指针归 `std::string` 所有，字符串扩容、修改或析构后失效。需要长期保存时拷贝成 `std::string`。

## 野指针、悬空指针与重复释放

| 问题 | 成因 | 规避 |
| --- | --- | --- |
| 野指针 | 未初始化 | 定义时置 `nullptr` |
| 悬空指针 | 指向的对象已销毁 | 释放后置空；用智能指针 |
| 重复释放 | 同一块内存 `delete` 两次 | 释放后置空；明确所有权 |
| use-after-free | 释放后继续访问 | RAII、ASan、代码审查 |

```cpp
int* p = new int(1);
delete p;
// *p = 2;       // use-after-free
// delete p;     // double free
p = nullptr;     // 降低再次误用概率

int& bad() {
    int x = 1;
    return x;    // 返回局部变量的引用：悬空
}
```

!!! danger "返回局部变量的指针/引用"
    函数返回后栈帧失效，返回的地址指向已销毁对象。返回 `std::string`、`std::vector` 等值类型，或由调用方传入缓冲区/使用智能指针。

## 智能指针：所有权才是解法

裸指针只表达“地址”，不表达“谁负责释放”。现代 C++ 用智能指针表达所有权：

```cpp
#include <memory>

std::unique_ptr<int> up = std::make_unique<int>(42);   // 独占所有权
std::shared_ptr<int> sp = std::make_shared<int>(42);   // 共享所有权，引用计数
std::weak_ptr<int> wp = sp;                            // 不增加计数，打破循环引用
```

函数参数若只是观察、不涉及所有权，仍用 `T*` 或 `T&`；需要转移所有权才用 `std::unique_ptr<T>`。详细规则见 [现代 C++](modern-cpp.md)。

## 面试追问

???+ question "面试追问：引用到底占不占内存？"
    标准没有规定。实现上通常等价于常量指针，作为成员、参数或未优化时占一个指针大小；作为局部别名且被编译器看穿时可能完全消除。回答“通常占一个指针大小，但可被优化掉”最稳妥。

???+ question "面试追问：常量引用能绑定临时对象吗？"
    能。`const int& r = 42;` 会把临时对象的生命周期延长到 `r` 的生命周期。非 const 引用 `int& r = 42;` 非法，因为临时对象是右值，且修改它没有意义。C++11 起右值引用 `int&&` 也能绑定临时对象。

???+ question "面试追问：返回局部变量的引用会怎样？"
    悬空引用，行为未定义。函数返回后栈帧被回收，引用指向已失效的存储；可能“看起来正常”，也可能被下一次函数调用覆盖。编译器通常会给出警告，但不要依赖警告。

???+ question "面试追问：指针和数组等价吗？"
    不等价。数组是类型 `T[N]` 的对象，有确定大小；指针是保存地址的标量。数组名在多数表达式中退化为首元素指针，导致 `a[i] == *(a + i)`；但 `sizeof`、`&`、引用绑定、函数传参时行为不同，函数参数里的 `T a[]` 实际就是 `T*`。

???+ question "面试追问：`const int*` 和 `int const*` 有区别吗？"
    没有，完全等价。`const` 修饰的是它左边最近的类型；左边没有类型时修饰右边。区别只在 `int* const`（const 指针）和 `const int* const`（两者都 const）。

## 下一步

- `const`、`static` 等关键字的完整语义：[基础语法](basics.md)
- 指针指向的栈、堆与对象布局：[内存模型](memory.md)
- 所有权与智能指针的现代写法：[现代 C++](modern-cpp.md)

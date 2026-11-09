---
title: 编译、链接与工程构建
tags:
  - C++
  - 编译链接
  - 构建系统
---

# 编译、链接与工程构建

源码到可执行文件要过四步：预处理 → 编译 → 汇编 → 链接。
前三步是**翻译单元（TU）内部**的事，链接是**跨 TU 拼接**的事——工程上那些"莫名其妙"的问题多半发生在第四步。

!!! tip "本章主线"
    每一步都问：**输入是什么、输出是什么、符号此刻还存在吗？**
    预处理输出文本，编译输出汇编，汇编输出可重定位目标文件，链接输出可执行文件。
    `.o` 里的跨 TU 地址全是占位符，链接器的任务就是把这些坑填上。

## 从源码到可执行文件

| 阶段 | 工具动作 | 输入 | 输出 | 命令 |
| --- | --- | --- | --- | --- |
| 预处理 | 展开宏与 `#include`、裁剪条件编译 | `.cpp` | `.i`（纯文本） | `g++ -E` |
| 编译 | 词法/语法/语义分析、优化、生成汇编 | `.i` | `.s` | `g++ -S` |
| 汇编 | 汇编翻机器码，生成符号表与重定位项 | `.s` | `.o`（ELF 可重定位） | `g++ -c` |
| 链接 | 符号解析 + 重定位，合并段 | `.o`/`.a`/`.so` | 可执行文件 / 共享库 | `g++` |

```bash
g++ -E main.cpp -o main.i     # 预处理：文本，可以直接 grep 宏
g++ -S main.i  -o main.s      # 生成汇编，-masm=intel 更易读
g++ -c main.s  -o main.o      # 汇编成目标文件
g++ main.o util.o -o app      # 链接
g++ -std=c++17 -O2 -g main.cpp util.cpp -o app   # 一步到位
```

???+ question "面试追问：编译期和运行期怎么区分？"
    编译期是**翻译单元可见信息**就能确定的时刻：类型检查、模板实例化、`constexpr` 求值、`sizeof`、重载决议。
    运行期是必须等真实内存或输入的时刻：虚函数分派目标、`new` 的地址、栈布局。
    一句话：编译期决定"能不能编过"，运行期决定"跑起来对不对"。

## 预处理：文本替换

预处理器不理解类型，只做三件事：包含文件、替换宏、裁剪条件分支。

```cpp
#include <cstdio>

#define SQUARE(x) ((x) * (x))        // 括号必须加，SQUARE(a+1) 否则算错
#define STR(x)    #x                 // # 把实参变成字符串字面量
#define CAT(a, b) a##b               // ## 拼接标识符
#define LOG(fmt, ...) std::printf("[%s] " fmt "\n", __func__, ##__VA_ARGS__)
// ##__VA_ARGS__ 是 GNU 扩展（空参时吃掉逗号）；标准做法是 C++20 的 __VA_OPT__

int CAT(var, 1) = 42;                // 展开为 int var1 = 42;
```

| 宏 | 含义 | 用途 |
| --- | --- | --- |
| `__cplusplus` | 标准版本号（C++17 为 `201703L`） | 条件编译 |
| `__FILE__` / `__LINE__` | 文件 / 行号 | 日志、断言 |
| `__func__` | 函数名（不是宏，是语言特性） | 日志 |
| `NDEBUG` | 定义后关闭 `assert` | Release 构建 |

```bash
g++ -E -P main.cpp                  # -P 去掉行号标记
g++ -DDEBUG=1 -DLOG_LEVEL=2 ...     # 命令行定义宏
g++ -I./include -isystem ./3rd ...  # -I 项目头；-isystem 第三方头（抑制其警告）
g++ -MMD -MP -c x.cpp               # 生成 x.d 依赖文件，供增量构建
```

!!! danger "宏的三个经典坑"
    1. **多次求值**：`MAX(i++, 0)` 会自增两次。改用 `std::max` / `constexpr` 函数。
    2. **无作用域**：宏会污染之后所有代码，不受 namespace 与访问控制约束。
    3. **逗号陷阱**：`std::map<int,int>` 作为宏实参会被拆成两个参数，用 `using` 别名绕开。

## 编译：从 AST 到机器码

内部流程：**词法分析 → 语法分析（AST）→ 语义分析（类型检查、重载决议）→ 中间表示（GIMPLE/LLVM IR）→ 优化 → 指令选择与寄存器分配 → 汇编**。

| 选项 | 作用 | 备注 |
| --- | --- | --- |
| `-std=c++17` | 语言标准 | 工程里必须显式指定 |
| `-O0 / -O2 / -O3 / -Os` | 优化级别 | `-O2` 是生产默认；`-O3` 可能膨胀代码 |
| `-g` / `-g3` | 调试信息（DWARF） | `-g3` 含宏信息，gdb 可 `macro expand` |
| `-Wall -Wextra -Werror` | 警告与警告即错误 | 新项目建议全开 |
| `-fPIC` | 位置无关代码 | 共享库必需 |
| `-flto` | 链接时优化 | 链接阶段也必须带 `-flto` |

## 目标文件与 ELF

`.o` 是 ELF 的**可重定位文件**：代码已编好，但跨 TU 地址是占位符。

| 段 | 内容 | 占文件空间 |
| --- | --- | --- |
| `.text` | 机器指令 | 是 |
| `.rodata` | 只读常量、字符串字面量 | 是 |
| `.data` | 已初始化的非零全局/静态变量 | 是 |
| `.bss` | 未初始化或零初始化变量 | **否**，只记大小 |
| `.symtab` | 符号表（名字、地址、类型、绑定） | 是，`strip` 可删 |
| `.rela.text` | 重定位表：哪些位置要链接器改写 | 是 |

```bash
readelf -S main.o     # 段表
readelf -s main.o     # 符号表：GLOBAL/WEAK/LOCAL，Ndx=UND 即未定义
readelf -r main.o     # 重定位项
nm -C main.o          # -C 反解修饰名
objdump -d -M intel app   # 反汇编
size app              # text/data/bss 占用
```

**强符号与弱符号**：

- 普通函数定义、已初始化全局变量 → 强符号。
- `inline` 函数、模板实例化、类内定义的成员函数 → 弱符号（WEAK / COMDAT），多 TU 各一份，链接器任选。
- 规则：强符号不能重名（重复定义报错）；强符号覆盖弱符号；多个弱符号取其一。

!!! note "重定位到底在做什么"
    编译 `call foo` 时不知道 `foo` 最终地址，于是生成一条 `R_X86_64_PLT32` 重定位，先填占位偏移。
    链接器解析出地址后回填指令操作数。**符号解析（找地址）+ 重定位（改字节）就是链接的全部核心。**

## 链接：符号解析与重定位

| 维度 | 静态链接 | 动态链接 |
| --- | --- | --- |
| 产物 | 代码复制进可执行文件 | 只记依赖，运行时加载 |
| 体积 | 大（每程序一份） | 小（多程序共享） |
| 升级 | 需重新链接 | 换 `.so` 即可（ABI 兼容前提） |
| 常见问题 | 库顺序、重复符号 | 找不到库、符号冲突 |

### PLT / GOT 与延迟绑定

动态库函数地址编译期未知，于是两层跳转：**GOT** 是数据段里的指针表，存外部符号真实地址；**PLT** 是代码段跳板，首次调用跳 `_dl_runtime_resolve` 完成绑定，之后 GOT 被改写、直接跳目标（lazy binding）。

```bash
LD_BIND_NOW=1 ./app            # 关闭延迟绑定，启动时全部解析
LD_DEBUG=libs,bindings ./app   # 观察加载与符号绑定
objdump -d -j .plt app         # 查看 PLT 桩
```

### 静态库 vs 动态库

```bash
# 静态库：.o 的归档，链接时按未解析符号按需抽取成员
g++ -c util.cpp -o util.o && ar rcs libutil.a util.o
g++ main.o -L. -lutil -o app

# 动态库：必须 -fPIC + -shared
g++ -fPIC -c util.cpp -o util.o
g++ -shared -Wl,-soname,libutil.so.1 -o libutil.so.1 util.o && ln -s libutil.so.1 libutil.so
g++ main.o -L. -lutil -Wl,-rpath,'$ORIGIN/../lib' -o app
```

!!! danger "链接顺序是有意义的"
    链接器**从左到右**扫描，遇到 `.a` 只抽取"当前尚未解析的符号"。
    若 `libA` 依赖 `libB`，必须 `-lA -lB`；写反了就 undefined reference。
    循环依赖用 `-Wl,--start-group -lA -lB -Wl,--end-group`，代价是反复扫描。

### `undefined reference` 常见原因

1. 忘了链库：`-lpthread`（旧 GCC）、`-lm`、`-ldl`。
2. 链接顺序错。
3. C/C++ 混编缺 `extern "C"`：C 侧符号是 `foo`，C++ 找的是 `_Z3foov`。
4. 只有声明没有定义。
5. 模板定义不可见（放进了 `.cpp`）。
6. 架构或 ABI 不匹配：32/64 位库混链、`_GLIBCXX_USE_CXX11_ABI` 不一致。

???+ question "面试追问：动态库运行时找不到怎么办？"
    查找顺序：`DT_RPATH`（未设 RUNPATH 时）→ `LD_LIBRARY_PATH` → `DT_RUNPATH` → `ld.so.cache` → 默认路径。
    工程上优先用 `-Wl,-rpath,'$ORIGIN/../lib'` 写进 ELF，而非要求用户设环境变量。
    排查三件套：`ldd ./app`、`readelf -d ./app | grep -E 'RPATH|RUNPATH|NEEDED'`、`LD_DEBUG=libs ./app`。

## 声明、定义与 ODR

- **声明**：告诉编译器有这么个东西，可以出现无数次。
- **定义**：分配存储或给出函数体，**全程序只能一次**（ODR）。

```cpp
extern int g_count;              // 声明，可以放头文件
int g_count = 0;                 // 唯一一处定义（放 .cpp；放头文件 → 每个 TU 各定义一次 → 重复定义）

inline int g_count = 0;          // 替代方案：C++17 inline 变量，多 TU 定义由链接器合并
```

| 写法 | 链接属性 | 说明 |
| --- | --- | --- |
| `int g;` | 外部链接 | 全程序唯一 |
| `static int g;` | 内部链接 | 每 TU 一份 |
| `namespace { int g; }` | 内部链接 | 匿名 namespace，C++ 推荐 |
| `inline int g;` | 外部 + 可合并 | 头文件定义变量的正确方式 |
| `constexpr int g;` | 隐式 inline（C++17） | 可放头文件 |
| `const int g = 1;` | 隐式内部链接 | 每 TU 一份，取地址可能不同 |

!!! warning "`static` 全局变量与普通全局变量的区别"
    两者都在静态存储区、生命周期都是整个程序；差别在**链接属性**：`static` 内部链接（TU 私有、不冲突），普通全局外部链接（可被 `extern` 引用、重名冲突）。
    追问初始化顺序：不同 TU 的全局对象初始化顺序**未定义**（static initialization order fiasco），常用 Meyers Singleton（函数内 `static`，C++11 起线程安全）规避。

## `extern "C"` 与 name mangling

C++ 为支持重载，把参数类型编码进符号名（Itanium ABI）：

```bash
$ g++ -c t.cpp && nm t.cpp.o
0000000000000000 T _Z3addii
0000000000000000 T _Z3adddd
$ c++filt _Z3addii      # add(int, int)
```

对外导出 C 接口：

```cpp
// c_api.h —— C 与 C++ 都能包含
#ifdef __cplusplus
extern "C" {
#endif

int compute(int x);      // 符号名就是 compute

#ifdef __cplusplus
}
#endif
```

## 头文件工程实践

```cpp
#pragma once              // 非标准，但主流编译器都支持，同一文件多次包含去重更快

#ifndef PROJECT_UTIL_H_   // 标准做法：按路径取名避免撞车
#define PROJECT_UTIL_H_
// ... 声明、内联定义
#endif
```

| 方案 | 优点 | 缺点 |
| --- | --- | --- |
| include guard | 标准、可移植 | 宏名可能冲突；每个 TU 仍要打开文件判断 |
| `#pragma once` | 快、不撞名 | 非标准；依赖路径唯一（符号链接可能失效） |

**前向声明**能大幅减少编译依赖，但有硬限制：不能用于继承基类、值语义成员、`sizeof`、需要完整类型的模板实参。

包含顺序：自身头文件 → C 系统头 → C++ 标准库 → 第三方 → 项目内；循环依赖靠前向声明 + 在 `.cpp` 中 include 打破，或直接上 PIMPL。

```cpp
class Impl;                    // 前向声明
class Widget {
public:
    Widget();
    ~Widget();                 // 必须定义在 .cpp：此处 Impl 不完整
private:
    std::unique_ptr<Impl> p_;  // PIMPL：编译防火墙
};
```

## ABI：二进制兼容的边界

ABI 规定符号命名、调用约定、对象布局、异常传播与 `std` 类型的内存布局。

- **名字修饰**：编译器与版本不同，规则可能不同。
- **vtable 布局**：Itanium ABI 下虚表指针在对象起始处，表项顺序与声明顺序相关。
- **结构体传参**：大小与字段类型决定走寄存器还是栈（System V AMD64 与 Windows x64 规则不同）。
- **`std::string`**：libstdc++ 的 SSO 缓冲 16 字节，libc++ 不同；GCC 5 起还有 `_GLIBCXX_USE_CXX11_ABI` 新旧两种布局。

!!! danger "不要跨编译器边界传 STL 对象"
    在 `.so` 接口上传 `std::string` / `std::vector` / `std::function`，等于把内存布局写进 ABI 契约。
    对方用不同标准库、不同 `-D_GLIBCXX_USE_CXX11_ABI`，轻则乱码，重则堆损坏。
    稳定接口应传 C 风格 POD、指针 + 长度，或不透明句柄。

## 模板与链接

模板不是代码，是**生成代码的配方**。被实例化时才产生符号，且通常是**弱符号（COMDAT）**，多个 TU 各生成一份由链接器去重——这解释了为什么模板定义必须放头文件。

```cpp
// stack.h
template <typename T>
class Stack {
public:
    void push(const T& v) { data_.push_back(v); }   // 类内定义 → 隐式 inline → 弱符号
private:
    std::vector<T> data_;
};

extern template class Stack<int>;   // 声明：此处不要实例化
// stack.cpp
template class Stack<int>;          // 显式实例化：只生成一份
```

!!! warning "模板分离编译为什么失败"
    定义放进 `.cpp` 后，使用方 TU 只看到声明，无法为 `Stack<int>` 生成代码；定义所在 TU 又不知道有人要它——谁都没生成，于是 undefined reference。
    解法：定义放头文件；或显式实例化 + `extern template`（减少重复实例化、加快编译）。

## 构建工具

```makefile
CXX      := g++
CXXFLAGS := -std=c++17 -O2 -g -Wall -Wextra -MMD -MP
SRCS     := main.cpp util.cpp
OBJS     := $(SRCS:.cpp=.o)
TARGET   := app

$(TARGET): $(OBJS)
	$(CXX) $^ -o $@

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

-include $(OBJS:.o=.d)     # 自动依赖：头文件改动也会触发重编译
```

```cmake
cmake_minimum_required(VERSION 3.16)
project(demo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(util STATIC src/util.cpp)
target_include_directories(util PUBLIC include)   # PUBLIC：使用者也能看到
target_compile_options(util PRIVATE -Wall -Wextra)

add_executable(app src/main.cpp)
target_link_libraries(app PRIVATE util)           # 传递依赖与包含目录
```

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -G Ninja
cmake --build build -j
```

!!! tip "增量构建加速"
    - **ccache**：按预处理结果 + 编译参数做哈希缓存，命中直接复用 `.o`；CMake 里 `-DCMAKE_CXX_COMPILER_LAUNCHER=ccache`。
    - **Ninja** 比 Make 更快发现可并行任务；**distcc / icecc** 做分布式编译（要求工具链一致）。

## 调试信息与发布

```bash
g++ -g3 -O2 app.cpp -o app                 # 带调试信息，仍可开优化
strip --strip-debug app                    # 去掉 .debug_*，保留符号表
strip --strip-all app                      # 连符号表也去掉（体积最小，无法回溯函数名）
objcopy --only-keep-debug app app.debug    # 分离调试信息
addr2line -e app -f -C 0x401136            # 地址反查 文件:行号
```

```bash
ulimit -c unlimited                        # 允许生成 core
cat /proc/sys/kernel/core_pattern          # core 落点（可能被 systemd-coredump 接管）
gdb ./app core -ex 'bt full' -ex 'info registers' -ex quit
```

## 面试速查

| 问题 | 一句话答案 |
| --- | --- |
| 编译期 vs 运行期 | 编译期做类型检查、模板实例化、常量折叠；运行期做虚分派、动态分配、真实 IO |
| 头文件能否定义函数 | 只能 `inline`、模板、类内成员函数；否则多 TU 重复定义 |
| LTO 是什么 | 链接阶段拿到所有 TU 的 IR 做整体优化，可跨 TU 内联、去虚化；代价是链接慢、内存高 |

!!! tip "下一步"
    编译链接解决"能跑起来"，[性能优化与调试](performance.md) 解决"跑得好不好"；
    对象布局见 [内存模型](memory.md)，虚函数与 vtable 见 [继承与多态](oop.md)。

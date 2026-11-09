---
title: C++ 知识集
tags:
  - C++
  - 索引
---

# C++ 知识集

从语法基础一路走到对象模型、STL、模板、现代 C++、并发与性能优化，最后落到面试八股和手撕代码。
每一章都按同一条线索组织：**怎么用 → 底层发生了什么 → 面试会怎么追问**。

!!! tip "怎么读"
    不要从第一页顺序刷到底。先看下面的「学习路线」确定自己在哪一层，
    再挑对应的章节；面试前两周直接进「面试冲刺」分区，遇到答不上来的点再回正文补。

## 学习路线

```mermaid
flowchart LR
    A[基础语法<br/>类型 / 关键字] --> B[指针与内存<br/>栈堆 / 对齐 / 布局]
    B --> C[类与对象<br/>构造 / 拷贝 / 移动]
    C --> D[继承与多态<br/>虚函数 / 对象模型]
    D --> E[STL 容器与算法]
    E --> F[模板与泛型]
    F --> G[现代 C++<br/>智能指针 / 移动语义]
    G --> H[并发编程]
    H --> I[编译链接与性能]
    I --> J[面试八股 + 手撕]
```

| 阶段 | 目标 | 对应章节 |
| --- | --- | --- |
| 入门 | 写得出正确、现代的 C++，知道常见坑 | [基础语法](basics.md)、[指针与引用](pointers.md) |
| 进阶 | 讲得清对象从创建到销毁发生了什么 | [内存模型](memory.md)、[类与对象](classes.md)、[继承与多态](oop.md) |
| 熟练 | 能选对容器、看懂模板报错、用对移动语义 | [STL 容器](stl-containers.md)、[STL 算法](stl-algorithms.md)、[模板](templates.md)、[现代 C++](modern-cpp.md) |
| 工程 | 能定位链接错误、内存问题和性能瓶颈 | [编译链接](build.md)、[性能与调试](performance.md)、[并发](concurrency.md) |
| 面试 | 高频题张口就来，手撕题一次写对 | [八股·基础](interview-basics.md)、[八股·进阶](interview-advanced.md)、[手撕代码](handwritten.md) |

## 章节导航

<div class="grid cards" markdown>

-   :material-language-cpp:{ .lg .middle } **基础语法与类型系统**

    ---

    数据类型、初始化、四种 cast、`const`/`static`/`volatile`、`auto` 与 `decltype`。

    [:octicons-arrow-right-24: 开始阅读](basics.md)

-   :material-pointer:{ .lg .middle } **指针、引用与 const**

    ---

    指针与引用的本质区别、三种 const 指针、数组退化、函数指针、野指针。

    [:octicons-arrow-right-24: 开始阅读](pointers.md)

-   :material-memory:{ .lg .middle } **内存模型与对象布局**

    ---

    内存分区、栈帧、`new`/`malloc` 底层、内存对齐、空类与虚表指针、`sizeof`。

    [:octicons-arrow-right-24: 开始阅读](memory.md)

-   :material-cube-outline:{ .lg .middle } **类与对象**

    ---

    构造/析构、拷贝与移动、Rule of 3/5/0、运算符重载、`static` 成员、单例。

    [:octicons-arrow-right-24: 开始阅读](classes.md)

-   :material-family-tree:{ .lg .middle } **继承与多态**

    ---

    虚函数表、虚析构、多重继承与虚继承、RTTI、对象切片、设计原则。

    [:octicons-arrow-right-24: 开始阅读](oop.md)

-   :material-database-outline:{ .lg .middle } **STL 容器**

    ---

    `vector` 扩容、红黑树、哈希表、`deque` 分段连续、复杂度与选型。

    [:octicons-arrow-right-24: 开始阅读](stl-containers.md)

-   :material-function-variant:{ .lg .middle } **STL 算法与 lambda**

    ---

    迭代器分类、`sort` 内省排序、remove-erase、严格弱序、闭包与 `std::function`。

    [:octicons-arrow-right-24: 开始阅读](stl-algorithms.md)

-   :material-code-braces:{ .lg .middle } **模板与泛型编程**

    ---

    特化与偏特化、可变参数、SFINAE、concepts、CRTP、编译期计算。

    [:octicons-arrow-right-24: 开始阅读](templates.md)

-   :material-rocket-launch-outline:{ .lg .middle } **现代 C++**

    ---

    右值引用、移动语义、完美转发、智能指针、`optional`/`variant`、协程、ranges。

    [:octicons-arrow-right-24: 开始阅读](modern-cpp.md)

-   :material-thread:{ .lg .middle } **并发编程**

    ---

    线程与锁、条件变量、原子操作与内存序、线程池、无锁与 false sharing。

    [:octicons-arrow-right-24: 开始阅读](concurrency.md)

-   :material-hammer-wrench:{ .lg .middle } **编译、链接与工程**

    ---

    预处理到链接、ELF 与符号、静态/动态库、ODR、`extern "C"`、ABI、CMake。

    [:octicons-arrow-right-24: 开始阅读](build.md)

-   :material-speedometer:{ .lg .middle } **性能优化与调试**

    ---

    缓存友好、拷贝消除、内存池、perf/ASan/Valgrind、core dump、UB 与优化。

    [:octicons-arrow-right-24: 开始阅读](performance.md)

-   :material-format-list-checks:{ .lg .middle } **面试八股 · 基础篇**

    ---

    语言基础、指针内存、类与对象、继承多态、STL、现代 C++，约 60 题。

    [:octicons-arrow-right-24: 开始自测](interview-basics.md)

-   :material-school-outline:{ .lg .middle } **面试八股 · 进阶篇**

    ---

    对象模型、移动语义、智能指针、模板、并发、性能与工程，约 50 题。

    [:octicons-arrow-right-24: 开始自测](interview-advanced.md)

-   :material-keyboard-outline:{ .lg .middle } **手撕代码题库**

    ---

    `memcpy`、`String`、`shared_ptr`、`vector`、单例、线程池、LRU、对象池。

    [:octicons-arrow-right-24: 开始练习](handwritten.md)

</div>

## 面试优先级

时间不够时，按这个顺序复习（也是大厂 C++ 岗出现频率的顺序）：

1. **内存管理**：内存分区、`new`/`malloc`、内存对齐、`sizeof`、内存泄漏排查
2. **虚函数与多态**：vtable/vptr、虚析构、构造/析构中调用虚函数、多重继承
3. **智能指针与 RAII**：`unique_ptr`/`shared_ptr`/`weak_ptr`、控制块、循环引用
4. **STL 底层**：`vector` 扩容与失效、红黑树、哈希表、`sort`
5. **移动语义**：左值右值、`std::move`、完美转发、RVO
6. **并发**：锁、条件变量、原子与内存序、线程池

!!! warning "只背结论是不够的"
    八股的追问通常分三层：**是什么 → 底层怎么实现 → 什么情况下会出问题**。
    比如虚函数，能答出"通过虚表实现"只是第一层；能画出对象布局、说清 vptr 何时初始化、
    再解释"构造函数里调用虚函数为什么不触发多态"，才算过关。

## 标准版本速查

| 标准 | 代表特性 | 状态 |
| --- | --- | --- |
| C++11 | 右值引用、移动语义、`auto`、lambda、智能指针、`thread`、`constexpr` | 现代 C++ 起点，必须掌握 |
| C++14 | 泛型 lambda、返回类型推导、`make_unique`、变量模板 | 常用 |
| C++17 | 结构化绑定、`if constexpr`、`optional`/`variant`/`any`、`string_view`、折叠表达式、复制消除 | 当前工程基线 |
| C++20 | concepts、ranges、协程、`<=>`、`format`、`jthread`、modules | 新项目逐步采用 |
| C++23 | `expected`、`print`、`mdspan`、deducing this、`flat_map` | 前沿 |

!!! note "本书约定"
    正文默认以 **C++17** 为基线；涉及 C++20/23 的特性会显式标注版本。
    代码示例省略了部分 `#include`，面试手写时记得补齐。

## 参考与延伸

- [cppreference](https://en.cppreference.com/)：查标准行为的第一选择
- [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/)：工程实践规范
- 《Effective Modern C++》：移动语义、智能指针、lambda 的权威解释
- 《深度探索 C++ 对象模型》：虚表、对象布局、构造语义
- 《C++ Concurrency in Action》：内存模型与并发实践

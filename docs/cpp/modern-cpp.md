---
title: 现代 C++
tags:
  - C++
  - 现代C++
  - 移动语义
  - 智能指针
---

# 现代 C++

C++11 是分水岭：它把「手写资源管理」变成了「用类型系统表达所有权」。之后的 14/17/20/23 更多是在补短板、提表达力。面试里的现代 C++ 问题通常只有两类：**值类别与移动**、**所有权与生命周期**。把这两条主线吃透，其余特性都能挂上去。

!!! tip "阅读顺序"
    先看「值类别」和「移动语义」，它们是所有性能话题的地基；再看智能指针，最后扫一遍 C++17/20 的词汇类型。并发相关见[多线程与并发](concurrency.md)。

## 版本演进脉络

| 标准 | 定位 | 代表特性 | 工程现状 |
| --- | --- | --- | --- |
| C++11 | 现代 C++ 起点 | 右值引用、移动语义、`auto`、lambda、`constexpr`、智能指针、`thread`、`unordered_*` | 必须掌握 |
| C++14 | 补全与放松 | 泛型 lambda、函数返回类型推导、`make_unique`、变量模板、二进制字面量 | 日常使用 |
| C++17 | 工程基线 | 结构化绑定、`if constexpr`、`optional`/`variant`/`any`、`string_view`、折叠表达式、**强制复制消除**、`scoped_lock` | 默认目标 |
| C++20 | 表达力跃迁 | concepts、ranges、协程、`<=>`、`format`、`jthread`、`span`、modules | 新项目逐步采用 |
| C++23 | 实用主义 | `expected`、`print`、`mdspan`、deducing this、`flat_map`、`stacktrace` | 前沿 |

!!! note "基线约定"
    本文代码默认按 **C++17** 编写；C++20/23 的特性会显式标注版本，避免在旧编译器上踩坑。

## 类型推导与基础改良

### auto、decltype 与返回类型推导

`auto` 使用模板实参推导规则：**顶层 `const` 和引用会被丢弃**，数组和函数会退化为指针。想要保留引用必须写 `auto&` / `const auto&`。

```cpp
int x = 0;
const int cx = x;
const int& rx = x;

auto a = cx;        // int：const 被丢弃
auto& b = cx;       // const int&：引用 + const 保留
auto c = rx;        // int：引用被丢弃
decltype(rx) d = x; // const int&：decltype 保留完整类型
decltype((x)) e = x;// int&：带括号的 lvalue 表达式推导为引用
```

C++14 起函数返回类型可写 `auto` 由 `return` 推导；`decltype(auto)` 按 `decltype` 规则推导，能保留引用，常用于转发返回值。
!!! warning "auto 的经典坑"
    `auto s = v[0];` 对 `std::vector<bool>` 得到的是代理对象而不是 `bool`；对 `std::map` 遍历写 `auto kv : m` 会拷贝整个 `pair`，应写 `auto& [k, v] : m` 或 `const auto&`。

### 统一初始化与 initializer_list

花括号初始化 `{}` 禁止窄化转换，能统一标量、数组、容器；但 `initializer_list` 构造函数的优先级极高：`Widget w2{10, 3.14}` 会优先匹配 `initializer_list<int>` 并因窄化报错，而不是调用 `Widget(int, double)`。空花括号 `{}` 则调用默认构造。

### nullptr、范围 for、using、enum class

```cpp
enum class Color : std::uint8_t { Red, Green, Blue }; // 强类型、可指定底层类型
Color c = Color::Red;
int i = static_cast<int>(c);       // 不会隐式转 int，必须显式转换
using IntVec = std::vector<int>;   // typedef 不支持模板别名
template <typename T> using Vec = std::vector<T>;
```

`nullptr` 的类型是 `std::nullptr_t`，解决 `f(NULL)` 二义性和 `NULL` 被定义为 `0` 的问题；`long long` 至少 64 位，跨平台定宽整数优先 `<cstdint>` 的 `int64_t`。范围 for 本质是 `begin()`/`end()` 的语法糖，遍历时**不要修改容器结构**（迭代器失效）。

## 值类别：lvalue、xvalue、prvalue

- **lvalue（左值）**：有名字、可取地址，如变量、`*p`、`++i`。
- **prvalue（纯右值）**：临时对象、字面量、返回非引用的函数调用结果，如 `42`、`a + b`。
- **xvalue（将亡值）**：资源可被复用的对象，如 `std::move(x)`、`static_cast<T&&>(x)`。

合起来：glvalue = lvalue + xvalue；rvalue = prvalue + xvalue。**右值引用只能绑定右值**，`T&&` 在模板中经引用折叠后可能变成左值引用，这就是「万能引用」。

```cpp
template <typename T>
void f(T&& param);   // 万能引用（forwarding reference）

int x = 1;
f(x);                // T = int&，param 类型 int&
f(1);                // T = int，param 类型 int&&
```

引用折叠规则只有一条：**只要有一个 `&`，结果就是 `&`**；`&& + &&` 才是 `&&`。

???+ question "面试追问：为什么 `T&&` 不是右值引用？"
    因为它可能是万能引用。判别标准：形如 `T&&` 且 `T` 需要推导（函数模板参数、`auto&&`），才是万能引用；`std::vector<T>&&`、`void f(int&&)` 是确定的右值引用。万能引用能同时接左值和右值，代价是必须配合 `std::forward` 才能保持值类别。

## 移动语义

### 为什么需要移动

拷贝构造对持有堆内存的对象意味着「重新分配 + 逐元素复制」。如果源对象马上就要销毁，直接**偷走它的指针**显然更划算。移动构造就是所有权的转移，复杂度从 O(n) 降到 O(1)。

```cpp
class Buffer {
public:
    explicit Buffer(std::size_t n) : data_(new int[n]), size_(n) {}
    ~Buffer() { delete[] data_; }

    Buffer(const Buffer& other)                       // 拷贝：深拷贝
        : data_(new int[other.size_]), size_(other.size_) {
        std::copy(other.data_, other.data_ + size_, data_);
    }

    Buffer(Buffer&& other) noexcept                   // 移动：偷指针并置空源
        : data_(other.data_), size_(other.size_) {
        other.data_ = nullptr;
        other.size_ = 0;
    }

    Buffer& operator=(Buffer&& other) noexcept {
        if (this != &other) {
            delete[] data_;
            data_ = std::exchange(other.data_, nullptr);
            size_ = std::exchange(other.size_, 0);
        }
        return *this;
    }
private:
    int* data_;
    std::size_t size_;
};
```

### std::move 的本质

`std::move` 不做任何移动，它只是 `static_cast<T&&>(x)`，把表达式强制转换成 xvalue，**让重载决议选中移动构造**。真正的资源转移发生在移动构造函数体内。

!!! danger "移动后对象处于「有效但未指定」状态"
    标准只保证对象可析构、可赋值，不保证内容。不要对已移动对象做「值」的假设；实践中应把它当作空对象，并在移动构造/赋值里显式置空，避免二次释放。

### noexcept 与 vector 扩容

`std::vector` 扩容时要把旧元素搬到新缓冲区。若移动构造不是 `noexcept`，而拷贝构造可用，标准库会选择**拷贝**，因为移动抛异常会破坏强异常安全保证。因此移动构造、移动赋值应尽量标记 `noexcept`。

```cpp
std::vector<Buffer> v;
v.reserve(10);
v.push_back(Buffer(10));   // 若 Buffer 移动构造抛异常，扩容会退化为拷贝
```

???+ question "面试追问：移动语义到底省了哪次拷贝？"
    省的是「源对象即将销毁时的深拷贝」。以 `return local;` 为例，若没有移动，临时对象要复制堆内存；有了移动，只复制指针。但要注意：编译器可能直接做 RVO 连移动都省掉，所以**不要为了性能写 `return std::move(local);`**。

## 完美转发

`std::forward<T>(arg)` 在 `T` 为左值引用时返回左值，否则返回右值，从而把参数**原封不动**传给下一层。没有它，函数内部的具名参数永远是 lvalue，右值属性会丢失。

```cpp
template <typename T, typename... Args>
std::unique_ptr<T> make_unique_impl(Args&&... args) {
    return std::unique_ptr<T>(new T(std::forward<Args>(args)...));
}

void sink(int&)  { std::cout << "lvalue\n"; }
void sink(int&&) { std::cout << "rvalue\n"; }

template <typename T>
void relay(T&& x) {
    sink(std::forward<T>(x));   // 保持值类别
}
```

!!! warning "常见误用"
    同一个参数**只能 forward 一次**。第一次 forward 后，若被调函数移动了资源，第二次 forward 会转发一个已被掏空的对象，属于未定义行为的温床。也不要对局部变量 `std::forward`，局部变量是 lvalue，应直接传或 `std::move`。

## 返回值优化：RVO 与复制消除

- **RVO（Return Value Optimization）**：返回纯右值临时对象时直接在调用方空间构造。
- **NRVO（Named RVO）**：返回具名局部变量时省略拷贝，属于可选优化。
- **C++17 强制复制消除**：返回 prvalue（如 `return T{};`）时，语言保证不产生临时对象，即使拷贝构造被删除也能编译。

```cpp
struct NonCopyable {
    NonCopyable() = default;
    NonCopyable(const NonCopyable&) = delete;
    NonCopyable(NonCopyable&&) = default;
};
NonCopyable make() { return NonCopyable{}; } // C++17 保证不调用拷贝/移动
NonCopyable make_bad() {
    NonCopyable x;
    return std::move(x);  // 阻止 NRVO，反而多一次移动
}
```

???+ question "面试追问：为什么 C++17 要强制复制消除？"
    因为它让「返回值」在语义上就是对象本身，而不是「先构造再拷贝」。这使 `std::mutex`、`std::atomic` 这类不可移动类型可以按值返回，也让工厂函数和 `optional`/`variant` 的实现更自然。强制消除只针对 prvalue，NRVO 仍是可选优化。

## 智能指针

### unique_ptr：独占所有权

`unique_ptr` 禁止拷贝、允许移动，默认删除器 `std::default_delete<T>` 是空类，经空基类优化后**大小通常等于一个裸指针**。优先用 `std::make_unique`（C++14），异常安全且不暴露 `new`。

```cpp
auto p = std::make_unique<int>(42);
auto arr = std::make_unique<int[]>(10);        // 数组特化，析构调用 delete[]
// auto q = p;                                 // 错误：不可拷贝
auto q = std::move(p);                         // 转移所有权，p 变为 nullptr

// 自定义删除器：函数指针会让 unique_ptr 变大
auto deleter = [](FILE* f) { if (f) std::fclose(f); };
std::unique_ptr<FILE, decltype(deleter)> fp(std::fopen("a.txt", "r"), deleter);
```

### shared_ptr：共享所有权与控制块

`shared_ptr` 内部有两个指针：**对象指针**和**控制块指针**。控制块保存强引用计数、弱引用计数、删除器、分配器。拷贝/析构对计数做原子加减，因此控制块是线程安全的，但**被管理对象的读写不是**。

```cpp
auto sp = std::make_shared<Widget>(1, 2);  // 一次分配：对象 + 控制块
std::shared_ptr<Widget> sp2 = sp;          // 强计数 +1
std::weak_ptr<Widget> wp = sp;             // 弱计数 +1，不影响生命周期
```

| 维度 | `make_shared<T>` | `shared_ptr<T>(new T)` |
| --- | --- | --- |
| 内存分配 | 一次（对象与控制块同块） | 两次 |
| 异常安全 | 强 | 参数求值顺序下可能泄漏 |
| 自定义删除器 | 不支持 | 支持 |
| 内存释放 | 强弱引用都归零才释放整块 | 强引用归零即释放对象 |

**别名构造** `shared_ptr<int> pa(owner, &owner->a)` 让指针指向成员，却共享原控制块，从而延长整个对象的生命周期。

### weak_ptr：观察者与破环

`weak_ptr` 不增加强引用计数，用 `lock()` 提升为 `shared_ptr`，用 `expired()` 判断是否已销毁。

```cpp
struct Node {
    std::shared_ptr<Node> next;
    std::weak_ptr<Node> prev;   // 反向用 weak_ptr 打破循环
};

auto a = std::make_shared<Node>();
auto b = std::make_shared<Node>();
a->next = b;
b->prev = a;   // 若这里也用 shared_ptr，两个节点永远不释放
```

### enable_shared_from_this

类内部需要返回自身的 `shared_ptr` 时，直接 `shared_ptr<T>(this)` 会创建**第二个控制块**，导致二次析构。继承 `std::enable_shared_from_this<T>` 后调用 `shared_from_this()`，它内部持有指向原控制块的 `weak_ptr`。

```cpp
class Session : public std::enable_shared_from_this<Session> {
public:
    void start() {
        auto self = shared_from_this(); // 延长生命周期，避免回调期间被销毁
        async_op([self] { self->handle(); });
    }
private:
    void handle() {}
};
```

!!! danger "shared_ptr 的线程安全边界"
    多个线程同时拷贝/销毁**同一个 shared_ptr 对象**仍需同步（`shared_ptr` 对象本身不是原子的）；不同 `shared_ptr` 实例指向同一对象时，引用计数操作是安全的。对象成员的读写必须由业务锁保护。需要原子操作整个指针时用 `std::atomic<std::shared_ptr<T>>`（C++20）。

???+ question "面试追问：unique_ptr 的大小是多少？"
    默认删除器下通常是一个指针大小（8 字节）；若删除器有状态（如函数指针、捕获 lambda），大小会增加。`shared_ptr` 通常是两个指针大小（对象指针 + 控制块指针），`make_shared` 不改变 `shared_ptr` 本身大小，只减少分配次数。

## lambda 进阶

```cpp
int base = 10;
auto add = [base](int x) { return base + x; };       // 按值捕获
auto add2 = [&base](int x) { return base + x; };     // 按引用捕获，注意悬空
auto gen = [](auto a, auto b) { return a + b; };     // C++14 泛型 lambda
auto p = std::make_unique<int>(1);
auto own = [ptr = std::move(p)] { return *ptr; };    // C++14 初始化捕获，支持 move-only
auto c = [] (int x) constexpr { return x * 2; };     // C++17 constexpr lambda
```

!!! warning "捕获 this 的生命周期"
    `[=]` 在成员函数中捕获的是 `this` 指针，不是对象副本。若 lambda 存到异步任务里、对象已析构，调用即悬空。C++17 可写 `[*this]` 按值捕获整个对象（需对象可拷贝）；更常见的做法是用 `weak_ptr` 检测对象是否还活着。

## constexpr 与编译期计算

`constexpr` 函数在 C++14 起允许循环、局部变量、多返回；`if constexpr`（C++17）在编译期丢弃分支，是模板元编程的降维打击。C++20 的 `consteval` 强制立即求值，`constinit` 保证静态初始化顺序安全。

```cpp
constexpr int factorial(int n) {
    int r = 1;
    for (int i = 2; i <= n; ++i) r *= i;
    return r;
}
static_assert(factorial(5) == 120);
template <typename T>
std::string describe(const T& v) {
    if constexpr (std::is_integral_v<T>) {
        return "integer: " + std::to_string(v);
    } else {
        return "other";
    }
}

consteval int square(int x) { return x * x; }  // C++20：只能编译期调用
constinit int global = factorial(4);           // C++20：常量初始化，无静态初始化顺序问题
```

## 词汇类型：optional、variant、any、tuple

```cpp
std::optional<int> parse(std::string_view s) {
    try { return std::stoi(std::string(s)); } catch (...) { return std::nullopt; }
}
std::variant<int, std::string> v = 42;
v = "hello";
std::visit([](const auto& x) { std::cout << x; }, v);
std::any a = 3.14;
double d = std::any_cast<double>(a);
auto t = std::make_tuple(1, std::string("a"), 2.0);
auto [i, s, d2] = t;
std::apply([](auto... xs) { (std::cout << ... << xs); }, t); // C++17 折叠表达式
```

!!! warning "variant 的 valueless 状态"
    当 `variant` 赋值过程中抛异常，可能进入 `valueless_by_exception()` 状态（无值可访问）。访问前应检查，或改用 `std::expected`（C++23）表达错误。

## string_view、span 与 mdspan

`std::string_view` 是「指针 + 长度」的非拥有视图，构造零拷贝，但**不保证以 `\0` 结尾**，也不能延长原字符串生命周期。`std::span<T>`（C++20）是连续内存的视图，`std::mdspan`（C++23）是多维视图。

```cpp
std::string_view sv = "hello world";
sv.remove_prefix(6);             // "world"，不分配内存
void process(std::span<const int> data); // 同时接受数组、vector、C 数组
std::string_view bad() {         // 危险：返回指向局部字符串的 view
    std::string s = "temp";
    return s;                    // 悬空！
}
```

!!! danger "视图的生命周期"
    `string_view`/`span` 只借用不拥有。函数参数用它们是安全的（调用期间原对象存活）；作为返回值或成员变量时必须确保底层存储活得更久。不要把 `string_view` 传给需要 `const char*` 的 C API（可能没有结尾符）。

## C++20 及以后

### 三向比较 <=>

在类内写 `auto operator<=>(const Point&) const = default;` 一行即可生成 `==`、`<`、`<=`、`>`、`>=`，按字典序比较成员。返回类型为 `std::strong_ordering`、`weak_ordering` 或 `partial_ordering`，分别表示可互换、等价但不可互换、不可全序。

### concepts 与 ranges

```cpp
template <typename T>
concept Addable = requires(T a, T b) { { a + b } -> std::convertible_to<T>; };
template <Addable T>
T sum(T a, T b) { return a + b; }

auto evens = std::views::iota(1, 100)
           | std::views::filter([](int x) { return x % 2 == 0; })
           | std::views::transform([](int x) { return x * x; });
```

ranges 是惰性视图，`views::filter` 不立即计算；把 view 存起来时同样要小心底层容器生命周期。

### 协程与 modules

协程把函数变成可暂停的状态机，`co_await` 挂起、`co_yield` 产出、`co_return` 返回。C++20 只提供语言机制，标准库的 `generator`/`task` 要 C++23 或第三方库。典型场景：异步 I/O、惰性序列、状态机。modules 用 `import` 替代 `#include`，消除宏污染、加快编译，但工具链支持仍不均衡。

## 标准库设施概览

`<chrono>` 提供三种时钟：计时用 `steady_clock`，墙上时间用 `system_clock`，高精度用 `high_resolution_clock`；配合 `std::this_thread::sleep_for(100ms)` 与 `duration_cast` 使用。`<filesystem>` 的 `path`、`directory_iterator`、`exists`、`create_directories` 覆盖大部分文件操作，错误处理优先选 `error_code` 重载。`<thread>` 的细节见[并发章节](concurrency.md)。

## 常见避坑清单

| 坑 | 现象 | 正确做法 |
| --- | --- | --- |
| `auto` 丢引用 | 修改副本，原对象不变 | `auto&` / `const auto&` |
| `string_view` 悬空 | 访问已释放内存 | 确保底层字符串存活，或返回 `std::string` |
| `variant` valueless | `bad_variant_access` | 赋值前检查，或改用 `expected` |
| `shared_ptr` 循环引用 | 内存泄漏 | 反向边改 `weak_ptr` |
| `return std::move(x)` | 阻止 NRVO | 直接 `return x;` |
| 移动构造未 `noexcept` | vector 扩容退化为拷贝 | 标记 `noexcept` |
| lambda 捕获 `this` | 异步回调悬空 | `weak_ptr` 或 `[*this]` |

## 面试追问

???+ question "面试追问：std::move 到底做了什么？"
    `std::move` 只是一个类型转换：`static_cast<T&&>(x)`，把左值变成 xvalue，本身不移动任何内存。真正的移动发生在被调用的移动构造/移动赋值里，省掉的是深拷贝（如 vector 的堆内存分配与逐元素复制），而不是「拷贝」本身。移动后源对象处于「有效但未指定」状态，只能析构或重新赋值。

???+ question "面试追问：make_shared 和 shared_ptr(new T) 怎么选？"
    优先 `make_shared`：一次分配、缓存局部性好、异常安全。但若需要自定义删除器、需要把对象指针交给 C API、或对象很大而 weak_ptr 长期存活（控制块与对象同块，弱引用未清零则整块不释放），则用 `shared_ptr(new T)`。

???+ question "面试追问：shared_ptr 是线程安全的吗？"
    引用计数的增减是原子的，多个线程持有**不同 shared_ptr 实例**指向同一对象时安全。但同一个 shared_ptr 实例被多线程读写需要加锁；被管理对象的读写也需要业务同步。一句话：**控制块线程安全，对象不安全**。

???+ question "面试追问：为什么移动构造要 noexcept？"
    vector 扩容需要把元素搬到新内存。若移动构造可能抛异常，搬到一半失败会导致旧缓冲区状态不一致；为了强异常安全，标准库在「移动非 noexcept 且拷贝可用」时选择拷贝。标记 noexcept 才能让容器走移动路径。

???+ question "面试追问：C++17 强制复制消除解决了什么？"
    它让 prvalue 直接构造在目标位置，不产生中间临时对象。因此不可拷贝、不可移动的类型也能按值返回；同时消除了「返回大对象一定昂贵」的误解。注意 NRVO 对具名变量仍是可选优化，不要依赖。

## 小结

现代 C++ 的核心不是「用了多少新语法」，而是**用类型表达所有权和生命周期**：`unique_ptr` 表达独占，`shared_ptr` 表达共享，`weak_ptr` 表达观察，移动语义表达「资源可转移」，`string_view`/`span` 表达「只借用不拥有」。面试时把每个特性的「是什么 → 底层 → 什么时候出错」讲完整，比背特性列表有效得多。

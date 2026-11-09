---
title: 模板与泛型编程
tags:
  - C++
  - 模板
  - 泛型编程
---

# 模板与泛型编程

模板是 C++ 实现**零开销抽象**的核心：同一份源码在编译期为不同类型生成特化代码，
运行期没有虚表、没有装箱。代价是编译时间、错误信息，以及一套必须理解的推导与查找规则。

## 为什么需要模板

```cpp
int max_int(int a, int b) { return a > b ? a : b; }   // 每种类型写一遍？
double max_double(double a, double b) { return a > b ? a : b; }

template <class T>
T max(T a, T b) { return a > b ? a : b; }            // 一份代码，编译期实例化
```

| 方案 | 类型安全 | 运行开销 | 多态时机 |
| --- | --- | --- | --- |
| 宏 | 无 | 无 | 文本替换 |
| `void*` + 函数指针 | 弱 | 间接调用 | 运行期 |
| 继承 + 虚函数 | 强 | 虚调用、对象膨胀 | 运行期 |
| 模板 | 强 | 零（可内联） | 编译期 |

!!! tip "编译期多态 vs 运行期多态"
    模板在编译期确定调用目标，可内联、可常量折叠；虚函数在运行期查表。
    需要"同一接口、运行时替换实现"用虚函数；需要"同一算法、适配不同类型"用模板。

## 函数模板

```cpp
template <class T>
T max(T a, T b) { return a > b ? a : b; }

max(1, 2);          // T = int，实参推导
max<double>(1, 2);  // 显式指定 T，1 和 2 转为 double
// max(1, 2.0);     // 错误：T 同时推导为 int 和 double
```

- 推导只看实参，**不做隐式转换**（除 `const`/引用/数组退化等少数情况）；
- 返回类型不参与推导，需要时用 `auto` + 尾置返回 `-> decltype(expr)` 或 `std::common_type_t`；
- 显式指定部分模板参数后，其余仍可推导。

### 重载决议

非模板函数与模板同名时：两者都能精确匹配则**优先非模板**；模板匹配更精确（如引用绑定）则选模板；
`show<>(42)` 可强制选模板。

```cpp
void show(int)                  { std::puts("non-template"); }
template <class T> void show(T) { std::puts("template"); }
show(42);    // non-template
show<>(42);  // template
```

!!! warning "函数模板只能全特化"
    `template<class T> void f(T*)` 是对指针形态的**重载**，不是偏特化。
    C++ 不允许函数模板偏特化；想对 `T*` 特判，写重载或用 `enable_if` 约束。

## 类模板

```cpp
template <class T, std::size_t N>
class Stack {
public:
    void push(const T& v) { data_[size_++] = v; }
    T pop() { return data_[--size_]; }
    bool empty() const { return size_ == 0; }
private:
    T data_[N]{};
    std::size_t size_ = 0;
};

template <class T, std::size_t N>
void Stack<T, N>::push(const T& v) { /* 类外定义要重复模板头 */ }
```

### 依赖名：typename 与 template

模板内的名字分**非依赖名**（定义时确定）与**依赖名**（依赖模板参数）。编译器默认把依赖限定名当非类型：

```cpp
template <class T>
void use(T& c) {
    typename T::value_type x{};            // 依赖类型，必须 typename
    typename T::iterator it = c.begin();
    T::template rebind<int> other;         // 依赖模板名，必须 template
    c.template push_back<int>(1);
}
```

漏写 `typename` 在 GCC/Clang 立即报错，在 MSVC 可能延迟到实例化。

### CTAD（C++17）

```cpp
std::pair p{1, 2.5};        // pair<int, double>
std::vector v{1, 2, 3};     // vector<int>
std::lock_guard lk(mtx);    // 不必写 <std::mutex>
```

C++17 前要写 `std::make_pair`、`std::vector<int>`。CTAD 不适用于无构造函数的聚合类模板（C++20 改进）。

## 非类型、模板模板、默认参数

```cpp
template <class T, std::size_t N>            // 非类型参数：编译期常量
struct Array { T data[N]; };

template <int N>
constexpr int factorial = N <= 1 ? 1 : N * factorial<N - 1>;   // 变量模板

template <template <class> class Container>  // 模板模板参数
struct Adapter { Container<int> c; };
Adapter<std::vector> a;                       // C++17 起可匹配 vector<T, Alloc>

template <class T = int, class Compare = std::less<T>>   // 默认模板参数
class Heap { /* ... */ };
```

非类型参数支持整型、枚举、指针、引用、`nullptr`；C++20 起支持浮点与满足结构类型的类。
`std::array` 长度、`std::integral_constant` 都依赖它。

## 实例化与分离编译

模板本身不是代码，**实例化**才生成具体类型/函数。触发点：使用该类型（定义变量、调用、取地址）、
需要完整类型（`sizeof`、继承、成员访问）、显式实例化。

```cpp
template class Stack<int, 10>;         // 显式实例化定义：本 TU 生成代码
extern template class Stack<int, 10>;  // 声明：抑制本 TU 重复生成
```

### 为什么模板不能分离编译

编译器在**使用点**必须看到完整定义才能实例化。定义放进 `.cpp` 后，另一个 TU 只有声明，
链接时找不到实例化符号。历史上 `export template` 试图解决，因实现复杂且效果差在 C++11 被移除。

因此采用**包含模型**：定义放头文件，或放 `.tpp`/`.ipp` 再由头文件包含。C++20 modules 是另一条路。

!!! warning "代码膨胀"
    每个 TU、每种类型都生成一份实例化代码，增大二进制、拖慢编译。
    缓解：显式实例化集中到少数 TU、`extern template` 抑制重复、把非依赖代码抽成普通函数。

## 特化与偏特化

```cpp
template <class T> struct TypeName { static const char* get() { return "unknown"; } };

template <> struct TypeName<int> { static const char* get() { return "int"; } };  // 全特化

template <class T> struct TypeName<T*> {                                          // 偏特化
    static const char* get() { return "pointer"; }
};
```

- 全特化：所有参数都指定，本质是普通类；偏特化：只指定部分参数或对形态加约束（指针、引用、`const`）；
- **函数模板不能偏特化**，用重载或 `enable_if` 模拟；
- 特化必须在使用前声明，否则可能实例化主模板，导致 ODR 冲突。

!!! danger "特化声明顺序"
    若某 TU 已隐式实例化主模板，之后才出现特化，行为未定义（不同 TU 可能生成不同代码）。
    所有特化应紧跟主模板、在首次使用之前。

## 可变参数模板

```cpp
template <class... Ts>
void print(const Ts&... args) {
    ((std::cout << args << ' '), ...);   // C++17 折叠表达式（逗号运算符）
    std::cout << '\n';
}

template <class... Ts>
constexpr std::size_t count() { return sizeof...(Ts); }   // 包内元素个数

print(1, "two", 3.0);   // 每个实参类型独立推导
```

C++11 风格用递归展开：`print(first, rest...)` 每次剥掉一个参数，直到空包重载终止。
C++17 的折叠表达式 `(expr op ...)`、`(init op ... op pack)` 可替代大部分递归。

### 完美转发工厂

```cpp
template <class T, class... Args>
std::unique_ptr<T> make(Args&&... args) {
    return std::unique_ptr<T>(new T(std::forward<Args>(args)...));
}
auto p = make<std::string>(3, 'x');   // string(3, 'x')
```

`Args&&` 是**转发引用**：左值推导为 `T&`，右值推导为 `T`，配合 `std::forward` 保持值类别。
这是 `make_unique`、`emplace_back`、`std::thread` 的共同基础。

## SFINAE 与 concepts

### 替换失败不是错误

SFINAE：模板参数替换阶段若产生无效类型/表达式，**不报错**，只把该候选从重载集移除，从而按能力选择重载。

```cpp
template <class T, class = std::enable_if_t<std::is_integral_v<T>>>
T twice(T x) { return x * 2; }

// 检测成员是否存在
template <class T, class = void> struct has_size : std::false_type {};
template <class T>
struct has_size<T, std::void_t<decltype(std::declval<T>().size())>> : std::true_type {};

static_assert(has_size<std::vector<int>>::value);
static_assert(!has_size<int>::value);
```

`void_t<...>` 把任意合法表达式序列映射为 `void`；表达式非法时偏特化被移除，回落到主模板。

### C++20 concepts

```cpp
template <class T> concept Integral = std::is_integral_v<T>;

template <class T> concept Sized = requires(T t) {
    { t.size() } -> std::convertible_to<std::size_t>;
};

template <Integral T> T add(T a, T b) { return a + b; }   // 约束直接写在参数上
template <Sized T> void report(const T& t) { std::cout << t.size(); }
```

| 维度 | SFINAE | concepts |
| --- | --- | --- |
| 约束位置 | 模板参数、返回类型、`enable_if` | `requires` 子句 / concept |
| 错误信息 | 长，指向替换失败细节 | 直接指出不满足的约束 |
| 重载选择 | `enable_if` 优先级技巧 | 按约束偏序，更直观 |
| 可读性 | 低 | 高 |
| 标准 | C++11/14/17 | C++20 |

简写形式 `void f(Integral auto x)` 适合短约束；concepts 不改变零开销本质，只是把技巧变成语言特性。

## type_traits 与 if constexpr

```cpp
static_assert(std::is_same_v<int, std::remove_reference_t<int&>>);
static_assert(std::is_same_v<int, std::decay_t<const int&>>);   // 去引用 + 去 cv
using U = std::conditional_t<sizeof(void*) == 8, std::uint64_t, std::uint32_t>;
using I = std::integral_constant<int, 42>;
```

`if constexpr`（C++17）在编译期丢弃不成立的分支，替代 tag dispatch：

```cpp
template <class T>
std::string describe(const T& v) {
    if constexpr (std::is_pointer_v<T>) return v ? "pointer" : "null";
    else if constexpr (std::is_integral_v<T>) return "integer: " + std::to_string(v);
    else return "other";
}
```

被丢弃的分支仍须**语法合法**（不要求语义有效）。先归一化类型（`decay`/`remove_cvref`）再分支，
是写泛型组件的标准套路。

## CRTP：静态多态

```cpp
template <class Derived>
class Shape {
public:
    void draw() const { static_cast<const Derived*>(this)->draw_impl(); }  // 编译期绑定
};

class Circle : public Shape<Circle> {
public:
    void draw_impl() const { std::cout << "circle\n"; }
};
```

| 维度 | 虚函数 | CRTP |
| --- | --- | --- |
| 绑定时机 | 运行期（vtable） | 编译期 |
| 开销 | vptr + 间接调用 | 零，可内联 |
| 灵活性 | 可运行时替换、异构容器 | 类型必须编译期确定 |
| 代码体积 | 一份实现 | 每种 Derived 一份 |

CRTP 还用于混入（mixin）：对象计数、`enable_shared_from_this`、自动生成比较运算符。

## 模板元编程

```cpp
template <unsigned N> struct Fact { static constexpr unsigned value = N * Fact<N - 1>::value; };
template <> struct Fact<0> { static constexpr unsigned value = 1; };
static_assert(Fact<5>::value == 120);

constexpr unsigned fact(unsigned n) { return n <= 1 ? 1 : n * fact(n - 1); }  // C++14 起优先
static_assert(fact(5) == 120);
```

- 编译期计算可用于数组大小、`static_assert`、类型选择；编译期容器用 `std::array` + `constexpr`；
- **不要炫技**：TMP 拖慢编译、恶化错误信息。能用 `constexpr` 函数就不写递归模板，
  能用 `if constexpr` 就不写 SFINAE 嵌套。

## 模板与继承

### 空基类优化（EBO）

```cpp
struct Empty {};
struct A : Empty { int x; };   // sizeof(A) == sizeof(int)，空基类被优化掉
struct B { Empty e; int x; };  // sizeof(B) > sizeof(int)，成员必须占位
```

标准库用 EBO 让无状态分配器/比较器不增加容器体积（`std::vector` 通常 24 字节）。

### 策略模式（policy-based design）

把行为拆成模板参数，编译期组合，避免虚函数：

```cpp
struct NoCheck    { static void check(std::size_t) {} };
struct BoundCheck { static void check(std::size_t i) { if (i >= 10) throw std::out_of_range("idx"); } };

template <class T, class Check = NoCheck>
class FixedArray {
    T data_[10]{};
public:
    T& operator[](std::size_t i) { Check::check(i); return data_[i]; }
};
FixedArray<int, BoundCheck> safe;
```

## 常见坑

!!! warning "两阶段查找"
    模板定义时检查非依赖名，实例化时检查依赖名。依赖调用 `f(x)` 可能通过 ADL 在实例化点找到 `f`，
    而非依赖名必须在定义处可见——这解释了很多"换个命名空间就编译不过"。

!!! danger "依赖名消歧"
    `obj.template foo<int>()` 的 `template` 不能省，否则 `<` 被解析为小于号；
    依赖类型前必须加 `typename`。这两个关键字是模板代码最常见的语法错误来源。

其他易错点：模板友元需在类内首次声明，跨实例化访问写 `friend class Other<T>;`；
特化必须在使用前可见；成员函数模板不能是 `virtual`（vtable 槽位在类定义时固定）；
读报错从最后几行开始，前面往往是推导失败的连锁反应。

## 面试追问

???+ question "面试追问：模板在什么时候实例化？"
    函数模板在**使用点**（调用、取地址）隐式实例化；类模板在需要**完整类型**时实例化声明，
    成员函数只在使用时实例化。`template class X<int>;` 可强制提前生成。
    多个 TU 生成相同实例时，链接器按 COMDAT/弱符号合并。

???+ question "面试追问：模板特化和函数重载怎么选？"
    类模板用全特化/偏特化定制类型行为；函数模板不能偏特化，用重载更自然，
    重载参与正常重载决议，行为可预测。需要按类型特征约束时用 `enable_if`/concepts。

???+ question "面试追问：SFINAE 的原理？"
    模板实参替换发生在重载决议的候选生成阶段；替换产生非法类型或表达式时，
    该候选被静默移除而非报错。`enable_if` 制造"条件失败"，`void_t` 探测表达式合法性，
    从而实现按能力选择重载。

???+ question "面试追问：concepts 解决了 SFINAE 的什么问题？"
    错误信息可读（直接指出不满足的约束）、约束表达直观（`requires` 表达式）、
    按约束偏序选择重载而非优先级技巧，并让约束成为接口文档的一部分。

???+ question "面试追问：为什么模板不能定义虚函数？"
    vtable 在类定义时就要确定槽位，而成员函数模板会随实例化产生任意多个版本，
    无法为每个实例预留槽。模板类里的普通（非模板）成员函数仍可以是 `virtual`。

## 相关章节

- [STL 容器](stl-containers.md)：容器作为类模板、`allocator` 与 traits
- [STL 算法与 lambda](stl-algorithms.md)：`iterator_traits`、泛型 lambda、`std::function`
- [现代 C++](modern-cpp.md)：完美转发、`if constexpr`、concepts、ranges
- [面试八股 · 进阶篇](interview-advanced.md)：模板与对象模型的高频追问

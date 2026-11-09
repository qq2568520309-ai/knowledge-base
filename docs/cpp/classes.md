---
title: 类与对象
tags:
  - C++
  - 面向对象
---

# 类与对象

类把「状态」和「行为」绑在一起。C++ 的类真正特殊的地方在于**生命周期**：对象何时构造、拷贝、移动、销毁都有明确语义和可观测代价。本章按「定义 → 构造 → 析构 → 拷贝 → 移动 → 运算符 → 布局」推进。

延伸：[内存模型](memory.md)、[继承与多态](oop.md)、[现代 C++](modern-cpp.md)。

## 类的定义与访问控制

```cpp
class Account {
public:
    explicit Account(double b) : balance_(b) {}
    double balance() const { return balance_; }
protected:
    void audit() const {}
private:
    double balance_{0.0};
};
```

| 说明符 | 本类 | 派生类 | 外部 |
| --- | --- | --- | --- |
| `public` | ✅ | ✅ | ✅ |
| `protected` | ✅ | ✅ | ❌ |
| `private` | ✅ | ❌ | ❌ |

`struct` 与 `class` 只有两个区别：

| | 默认成员访问 | 默认继承 |
| --- | --- | --- |
| `struct` | `public` | `public` |
| `class` | `private` | `private` |

!!! tip "选用惯例"
    纯数据聚合用 `struct`，要维护不变量的类型用 `class`。这是给读者的信号，不是语法要求。

!!! warning "`private` 不是安全边界"
    访问控制是编译期检查，`reinterpret_cast`、指针偏移都能绕过。安全边界是进程与权限。

???+ question "面试追问：protected 和 private 差在哪？"
    `private` 对派生类也不可见；`protected` 直接暴露给派生类，但把实现细节写进了对所有派生类的契约——
    改一个 protected 成员，全部派生类可能编译失败。工程上倾向「数据 private + protected 虚函数」。

## 构造函数

构造函数把原始内存变成合法对象：获取资源、建立不变量。它没有返回值，不能被继承（C++11 可用 `using Base::Base;`），不能是虚函数。

### 初始化列表 vs 函数体内赋值

```cpp
class Buffer {
public:
    Buffer(std::size_t n, int v)
        : data_(new int[n]), size_(n), value_(v)   // ① 直接初始化
    {
        // data_ = new int[n];                     // ② 先构造再赋值，原指针还会泄漏
    }
private:
    int* data_;
    std::size_t size_;
    const int value_;                              // const / 引用成员只能靠列表
};
```

| 场景 | 函数体内赋值 | 初始化列表 |
| --- | --- | --- |
| `const` 成员 | 编译错误 | 必须 |
| 引用成员 | 编译错误 | 必须 |
| 无默认构造的成员 | 编译错误 | 必须 |
| 有默认构造的成员 | 先默认构造再赋值，多一次开销 | 直接构造 |

!!! danger "初始化顺序按声明顺序"
    `Bad() : a_(1), b_(a_) {}` 若 `b_` 声明在 `a_` 之前，`b_` 先用未初始化的 `a_`，是 UB。开 `-Wreorder` 检查。

### 委托构造、explicit 与 = default

```cpp
class Widget {
public:
    Widget() : Widget(0, 0) {}              // 委托构造（C++11）
    Widget(int w, int h) : w_(w), h_(h) {}
private:
    int w_, h_;
};

class Meters {
public:
    explicit Meters(double v) : v_(v) {}    // 禁止 double 隐式转换
    double v_;
};

class NonCopyable {
public:
    NonCopyable() = default;
    NonCopyable(const NonCopyable&) = delete;
    NonCopyable& operator=(const NonCopyable&) = delete;
};
```

!!! tip "explicit 该加就加"
    所有可单参调用的构造函数都是隐式转换入口；`explicit operator bool()` 让 `if (x)` 合法而 `int n = x;` 非法。

!!! note "`= default` 的位置有区别"
    类内 `= default` 是 inline 且保持 trivial；类外 `= default` 属于 user-provided，类型不再是 trivially copyable。

## 析构函数

生命周期结束时自动调用。析构顺序与构造严格相反：函数体 → 成员（声明逆序）→ 基类 → 虚基类。

```cpp
struct A { ~A() { std::puts("A"); } };
struct B { ~B() { std::puts("B"); } };
struct D : A { B b; ~D() { std::puts("D"); } };
// D d; 析构输出：D → B → A
```

!!! danger "析构函数里不要抛异常"
    栈展开时析构再抛异常会直接 `std::terminate`；C++11 起析构默认 `noexcept(true)`。要报错就给显式 `close()`。

## 拷贝控制

```cpp
class String {
public:
    String(const char* s = "") : data_(new char[std::strlen(s) + 1]) { std::strcpy(data_, s); }
    String(const String& o) : data_(new char[std::strlen(o.data_) + 1]) {   // 拷贝构造
        std::strcpy(data_, o.data_);
    }
    String& operator=(const String& o) {                                  // 拷贝赋值
        if (this != &o) {
            String tmp(o);      // 先拷贝：失败时 *this 不变（异常安全）
            swap(tmp);          // 再交换：不抛异常
        }
        return *this;
    }
    ~String() { delete[] data_; }
    void swap(String& o) noexcept { std::swap(data_, o.data_); }
private:
    char* data_;
};
```

| 写法 | 调用 |
| --- | --- |
| `String b = a;` / `String b(a);` | 拷贝构造 |
| `b = a;` | 拷贝赋值（对象已存在） |
| `void f(String s); f(a);` | 实参 → 形参，拷贝构造 |
| `return a;` | 通常被 RVO / 移动消除 |

!!! note "参数必须是引用"
    按值传参要拷贝实参 → 又调拷贝构造 → 无限递归；标准规定首参必须是引用。

!!! warning "默认拷贝是浅拷贝"
    逐成员拷贝，裸指针只复制地址，两个对象析构时 double free —— Rule of Three 的由来。

`operator=` 必须处理**自赋值**（`a = a`），否则先释放 `data_` 再读 `other.data_`。copy-and-swap 同时解决自赋值和异常安全。

## 移动语义

```cpp
class String {
public:
    String(String&& o) noexcept : data_(o.data_) { o.data_ = nullptr; }   // 移动构造：偷指针
    String& operator=(String&& o) noexcept {
        if (this != &o) { delete[] data_; data_ = o.data_; o.data_ = nullptr; }
        return *this;
    }
};
```

!!! danger "`noexcept` 不是装饰"
    `vector` 扩容时用 `std::move_if_noexcept` 选择：移动可能抛异常且拷贝可用时，标准库**退回拷贝**以维持强异常安全。
    移动构造不标 `noexcept`，等于让 vector 永远走拷贝路径。

移动后对象处于「有效但未指定」状态：可析构、可重新赋值，但别读它的值。自定义类应主动置空。

| 规则 | 内容 | 适用 |
| --- | --- | --- |
| Rule of Three | 析构 + 拷贝构造 + 拷贝赋值 | C++98 式资源管理类 |
| Rule of Five | 再加移动构造、移动赋值 | 需要移动优化的资源类 |
| Rule of Zero | 全交给 RAII 成员，一个都不写 | 现代 C++ 默认 |

## 特殊成员函数的生成规则

| 用户声明了 | 默认构造 | 拷贝构造 | 拷贝赋值 | 移动构造 | 移动赋值 |
| --- | --- | --- | --- | --- | --- |
| 任意构造函数 | ❌ | ✅ | ✅ | ✅ | ✅ |
| 析构函数 | ✅ | ✅ | ✅ | ❌ | ❌ |
| 拷贝构造 | ✅ | 用户 | ✅ | ❌ | ❌ |
| 拷贝赋值 | ✅ | ✅ | 用户 | ❌ | ❌ |
| 移动构造 | ✅ | ❌ | ❌ | 用户 | ❌ |
| 移动赋值 | ✅ | ❌ | ❌ | ❌ | 用户 |

写了析构函数（哪怕空实现），移动操作就悄悄消失，后续「移动」全部退化成拷贝；写了移动操作，拷贝被 `delete`，对象变成 move-only。用 `= default` 显式恢复需要的部分。

## 运算符重载

| 运算符 | 建议形式 | 理由 |
| --- | --- | --- |
| `= [] () ->` | 必须是成员 | 标准规定 |
| `+= -= *=` | 成员 | 修改自身，返回 `*this` |
| `+ - * /` | 非成员（可 `friend`） | 允许左操作数隐式转换 |
| `== != <` | 非成员（C++20 可成员 `= default`） | 对称性 |
| `<< >>` | 非成员 `friend` | 左操作数是 `ostream` |
| `++ --` | 成员 | 前置返回引用，后置多一个 `int` 形参 |

```cpp
class Counter {
public:
    Counter& operator++() { ++v_; return *this; }        // 前置：返回引用
    Counter operator++(int) {                             // 后置：返回旧值
        Counter old = *this;
        ++v_;
        return old;
    }
    bool operator==(const Counter& o) const { return v_ == o.v_; }
    friend std::ostream& operator<<(std::ostream& os, const Counter& c) {
        return os << c.v_;                                // 返回流引用以支持链式
    }
private:
    int v_{0};
};
```

???+ question "面试追问：前置 ++ 与后置 ++ 差在哪？"
    前置返回引用，后置返回值（要交出旧副本）。后置多一个 `int` 占位参数用于区分重载，调用时编译器自动传 0。
    自定义类型优先用前置——少一次拷贝，且 `++++c` 只有前置能成立。

!!! danger "不要重载的运算符"
    `&&`、`||`、`,`：重载后失去短路求值与顺序保证。`&`（取地址）也别碰。`new`/`delete` 只在内存池或调试时重载。

## static 成员

```cpp
class Counter {
public:
    Counter() { ++count_; }
    static int count() { return count_; }     // 没有 this
private:
    static int count_;                        // C++17 可写 inline static int count_ = 0;
};
int Counter::count_ = 0;                      // 定义：全程序唯一
```

- 属于类不属于对象，在静态存储区，不计入 `sizeof`；类外定义只能出现一次，放头文件需 C++17 `inline static`。
- 静态成员函数无 `this`，不能访问非静态成员，不能加 `const` 限定。
- 跨 TU 的静态对象初始化顺序未定义；依赖它时改用函数内局部静态（C++11 起线程安全，magic statics）。

## const 成员函数、mutable 与 this

`const` 成员函数不修改逻辑状态，`const` 对象只能调用它；此时 `this` 的类型是 `const X*`。`mutable` 允许在 const 函数里修改「不影响可观察状态」的成员。

```cpp
class Cache {
public:
    int get(int k) const { ++hits_; return data_.at(k); }   // 别写 data_[k]：operator[] 非 const
    int& get(int k) { return data_[k]; }                    // 非 const 重载
private:
    std::map<int, int> data_;
    mutable int hits_{0};
};
```

`return *this;` 支持链式调用（`b.width(3).height(4)`），但别把引用存到临时对象上，临时对象在完整表达式结束就销毁。

## friend 友元

```cpp
class Matrix {
    friend Matrix operator*(const Matrix&, const Matrix&);
    friend class MatrixTest;
    friend std::ostream& operator<<(std::ostream&, const Matrix&);
private:
    std::vector<double> d_;
};
```

- 不是成员、没有 `this`，关系单向：A 是 B 的友元，B 不是 A 的友元；不能继承、不能传递。
- 利：`operator<<`、测试类、紧耦合组件；弊：扩大接口面、提高耦合。
- 友元声明写在类内部，是作者主动授予的接口，比「返回内部指针的 getter」可控；真正破坏封装的是后者。

## 嵌套类、局部类与临时对象

```cpp
class LinkedList {
    struct Node { int v; Node* next; };   // 嵌套类：不占外围类空间
public:
    class Iterator { /* ... */ };
};
```

- 嵌套类只是名字在作用域内，`sizeof(LinkedList)` 不含 `Node`；C++11 起可访问外围类 private（需外围对象）。
- 匿名对象 `Foo()` 的生命周期到**完整表达式**结束；`const Foo& r = Foo();` 会延长到 `r` 的作用域，但 `Foo().member()` 不延长。
- `return std::string("x").c_str();` 返回悬垂指针；`for (auto& x : getVec().items())` 同理，被延长的只有 `getVec()` 的返回值。

## 限制对象创建方式与单例

```cpp
class HeapOnly {                          // 禁止栈上创建：析构私有
public:
    static HeapOnly* create() { return new HeapOnly(); }
    void destroy() { delete this; }       // 唯一销毁入口
private:
    HeapOnly() = default;
    ~HeapOnly() = default;
};

class StackOnly {                         // 禁止堆上创建：私有 operator new
public:
    StackOnly() = default;
private:
    static void* operator new(std::size_t) = delete;
    static void operator delete(void*) = delete;
};
```

```cpp
class Config {
public:
    static Config& instance() {
        static Config inst;                // C++11 magic static：初始化线程安全
        return inst;
    }
    Config(const Config&) = delete;
    Config& operator=(const Config&) = delete;
private:
    Config() = default;
};
```

| 单例写法 | 线程安全 | 评价 |
| --- | --- | --- |
| 局部静态 | ✅（C++11 起） | 首选：无锁、简洁、异常安全 |
| 饿汉 | ✅（main 前） | 简单，但拖慢启动、有跨 TU 顺序问题 |
| 双检锁 | 需 `atomic` + acquire/release | 容易写错，C++11 前有内存序缺陷 |

!!! warning "双检锁必须配内存序"
    `new` 与指针发布之间的重排会让别的线程看到「非空但未构造完」的对象；要么用 `atomic` 的 acquire/release，要么直接用局部静态。

## 对象大小与内存布局

| 类型 | `sizeof`（x86-64） | 说明 |
| --- | --- | --- |
| `struct Empty {};` | 1 | 空类也要能取唯一地址 |
| `struct { char c; int i; };` | 8 | 3 字节填充 |
| 含一个虚函数的类 | 8 | 多一个 vptr（32 位下 4） |
| 空类作基类 | 0（EBO） | 空基类优化 |

- 成员按声明顺序排列，编译器插填充满足对齐；`alignas`、`#pragma pack` 可调整。
- 有虚函数 → 多 vptr；有虚基类 → 可能再多一个偏移/虚基类表指针。
- 访问权限不影响布局；`static` 成员不在对象内；成员函数不占空间。

## 面试追问速查

???+ question "面试追问：构造函数可以是虚函数吗？"
    不能。虚调用需要 vptr 已就位，而构造函数正是建立 vptr 的过程。按类型创建用工厂或虚 `clone()`。

???+ question "面试追问：拷贝构造的参数为什么必须是引用？"
    按值传参要先拷贝实参，而拷贝就要调用拷贝构造本身，无限递归；标准直接规定首参为引用。

???+ question "面试追问：RVO 是什么？`return std::move(x)` 好不好？"
    RVO 让编译器在调用方预留空间直接构造返回值；C++17 起纯右值返回是**强制**复制消除。
    `return std::move(x)` 会阻止 NRVO，是常见负优化。

???+ question "面试追问：为什么 `operator=` 返回 `X&`？"
    支持连续赋值 `a = b = c`，与内置类型一致；返回引用还省一次拷贝。

???+ question "面试追问：`mutable` 用在什么场景？"
    只用于不改变可观察状态的成员：缓存、命中计数、惰性求值、`mutable std::mutex`。它是逻辑 const 的工具，不是绕过 const 的后门。

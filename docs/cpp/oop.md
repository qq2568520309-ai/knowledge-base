---
title: 继承、多态与对象模型
tags:
  - C++
  - 面向对象
---

# 继承、多态与对象模型

面试里「C++ 面向对象」真正的分水岭不是背出三大特性，而是能画出一张对象内存布局图：vptr 在哪、虚表在哪、基类子对象偏移多少、析构时先调谁。本章从继承的访问规则一路讲到 vtable、多重继承、RTTI 与对象切片。

前置知识：[类与对象](classes.md)、[内存模型与对象布局](memory.md)。相关章节：[模板与泛型编程](templates.md)、[面试八股 · 进阶篇](interview-advanced.md)。

## 三大特性与 C++ 的实现方式

| 特性 | 含义 | C++ 的落地手段 |
| --- | --- | --- |
| 封装 | 隐藏实现、只暴露契约 | `class` + 访问控制 + 编译期检查（非安全边界） |
| 继承 | 复用并扩展已有类型 | `public` 继承表达 is-a，`private` 继承表达「用基类实现」 |
| 多态 | 同一接口，多种实现 | 虚函数（运行期）+ 重载/模板/CRTP（编译期） |

!!! note "多态不等于虚函数"
    C++ 有四种多态：重载（ad-hoc，编译期）、模板（参数化，编译期）、虚函数（子类型，运行期）、
    强制转换（coercion）。面试说「多态」时默认指运行期子类型多态，但要能补一句「模板是编译期多态」。

## 继承基础

### 三种继承方式的访问变化

| 基类中的成员 | `public` 继承 | `protected` 继承 | `private` 继承 |
| --- | --- | --- | --- |
| `public` | `public` | `protected` | `private` |
| `protected` | `protected` | `protected` | `private` |
| `private` | 不可访问 | 不可访问 | 不可访问 |

规则可以记成：继承方式决定「基类成员的可见性上限」——`public` 继承不降级，`protected` 继承最高到 protected，`private` 继承全部压到 private（且外部无法把派生类当基类用）。

!!! warning "private 继承不是 is-a"
    `class Stack : private std::vector<int>` 表达的是「用 vector 实现 Stack」，外部不能把 `Stack*` 转成
    `std::vector<int>*`。同样的语义用「成员变量」表达更清楚，所以工程上 private 继承极少用，主要出现在
    EBO（空基类优化）和需要覆写虚函数的场景。

### is-a 与 has-a

| 关系 | 表达方式 | 例子 |
| --- | --- | --- |
| is-a | public 继承 | `Circle` is-a `Shape` |
| has-a | 成员变量（组合） | `Car` has-a `Engine` |
| is-implemented-in-terms-of | 组合或 private 继承 | `Stack` 用 `vector` 实现 |

!!! tip "组合优于继承"
    继承把派生类绑死在基类的实现细节上（脆弱的基类问题：基类改一个非虚函数，派生类行为可能被悄悄改变）。
    组合只依赖被组合类型的公开接口，耦合更低、更容易测试和替换。只有在「确实需要被基类指针统一处理」
    或「需要覆写虚函数」时才用 public 继承。

### 构造与析构顺序

```cpp
struct Base   { Base()   { std::puts("Base"); }   ~Base()   { std::puts("~Base"); } };
struct Member { Member() { std::puts("Member"); } ~Member() { std::puts("~Member"); } };

struct Derived : Base {
    Member m;
    Derived()  { std::puts("Derived"); }
    ~Derived() { std::puts("~Derived"); }
};
// 构造：Base → Member → Derived
// 析构：~Derived → ~Member → ~Base
```

顺序规则：**基类 → 成员（按声明顺序）→ 派生类构造函数体**；析构完全反向。若有虚基类，虚基类子对象**最先**构造、**最后**析构，且由最派生类负责构造。

!!! danger "派生类构造失败时，已构造的基类会被析构"
    派生类构造函数体抛异常，已完成的基类与成员子对象会按逆序销毁，但派生类自己的析构函数**不会**执行。
    所以资源获取要放在成员初始化里（RAII），而不是构造函数体里。

## 多态：静态与动态

| | 静态多态 | 动态多态 |
| --- | --- | --- |
| 实现 | 重载、模板、CRTP | 虚函数 |
| 绑定时机 | 编译期 | 运行期 |
| 开销 | 零运行时开销，可内联 | 一次间接跳转，通常无法内联 |
| 灵活性 | 类型在编译期确定 | 运行期可替换实现 |
| 代码体积 | 每个实例化一份，可能膨胀 | 一份代码 |

运行时多态的**三要素**：① 有继承关系；② 基类中声明虚函数且派生类重写；③ 通过基类的指针或引用调用。

```cpp
struct Shape {
    virtual ~Shape() = default;
    virtual double area() const = 0;
    virtual std::string name() const { return "Shape"; }
};

struct Circle : Shape {
    explicit Circle(double r) : r_(r) {}
    double area() const override { return 3.14159265 * r_ * r_; }
    std::string name() const override { return "Circle"; }
private:
    double r_;
};

void print(const Shape& s) {              // 引用：不切片，动态绑定
    std::cout << s.name() << ": " << s.area() << '\n';
}
```

## 虚函数机制：vtable 与 vptr

编译器为每个**含虚函数的类**生成一张虚表（vtable），表中按声明顺序存放虚函数地址；每个**对象**里放一个指向该表的指针（vptr）。

| 对象地址（x86-64） | 内容 |
| --- | --- |
| `+0` | vptr → `Circle` 的虚表 |
| `+8` | `r_` |

| 虚表槽位 | 内容 |
| --- | --- |
| 0 | `&Circle::~Circle`（完整对象析构） |
| 1 | `&Circle::~Circle`（删除析构，Itanium ABI 下占两个槽） |
| 2 | `&Circle::area` |
| 3 | `&Circle::name` |

关键结论：

- **每个类一张虚表，每个对象一个 vptr**。同类的所有对象共享同一张表，所以 `sizeof` 只增加一个指针。
- vptr 在构造函数里被设置：基类构造期间指向基类虚表，进入派生类构造时改指派生类虚表。
- 虚表通常放在**只读数据段**（`.rodata`；Itanium ABI 用 `.data.rel.ro`，因重定位需要而可写后只读）。这是实现细节，标准不规定。
- 调用开销：读 vptr → 取槽位 → 间接跳转。比普通调用多一次访存，且目标不确定，**通常无法内联**（编译器能证明动态类型时可去虚化）。
- 有虚函数 → 对象多一个指针；无虚函数 → 零开销，布局与 C struct 兼容。

!!! warning "不要手写「对象头部就是 vptr」的代码"
    把对象首地址当 `void**` 去读虚表、调私有虚函数，依赖具体 ABI 和编译器版本，属于 UB。
    面试可以讲，工程里禁止。

## 纯虚函数与抽象类

```cpp
struct Interface {
    virtual ~Interface() = 0;          // 纯虚析构：仍然必须提供定义
    virtual void run() = 0;
};
Interface::~Interface() = default;     // 少了这行 → 链接错误

struct Impl : Interface {
    void run() override {}
};
// Interface obj;   // 错误：抽象类不能实例化
```

- 含至少一个纯虚函数的类是**抽象类**，不能实例化，但可以有数据成员、构造函数、普通成员函数。
- 只含纯虚函数 + 虚析构的类就是**接口类**，用来表达契约。
- 纯虚函数**可以有定义**（在类外提供），派生类可以显式调用 `Base::f()`。
- 纯虚析构必须定义：派生类析构时会调用基类析构，链接器需要这个符号。

!!! note "抽象类可以有构造函数"
    派生类构造时必须先构造基类子对象，所以抽象类的构造函数会被调用，只是不能直接 `new` 抽象类。

## 虚析构函数

```cpp
struct B { ~B() {} };                       // 非虚析构
struct D : B { std::string s; };

B* p = new D;
delete p;                                    // UB：只调用 ~B，D 的成员泄漏
```

通过基类指针删除派生类对象时，若析构函数非虚，只会执行基类析构（静态绑定），派生类部分泄漏，行为未定义。

```cpp
struct B { virtual ~B() = default; };       // 正确：多态删除
```

什么时候**不需要**虚析构：

| 场景 | 原因 |
| --- | --- |
| 类被标记 `final` | 不会被继承，不存在派生类 |
| 不通过基类指针删除 | 栈对象、成员对象按静态类型析构 |
| 类本身没有虚函数、只作值类型 | 没有多态使用方式，加虚析构反而引入 vptr |
| 析构函数 `protected` 且禁止 delete | 有意禁止多态删除 |

!!! tip "经验法则"
    只要类**可能**被继承并通过基类指针删除，析构就声明为 `virtual`。代价是多一个 vptr；
    如果在意布局（如与 C 交互的 POD），就把类标 `final` 或把析构设为 protected 非虚。

## override / final 与重载、重写、隐藏

| 概念 | 作用域 | 条件 | 绑定 |
| --- | --- | --- | --- |
| 重载 overload | 同一作用域 | 同名、参数列表不同 | 编译期 |
| 重写 override | 基类 / 派生类 | 虚函数、签名相同（返回类型可协变） | 运行期 |
| 隐藏 hiding | 基类 / 派生类 | 同名但非虚，或签名不同 | 编译期 |

```cpp
struct Base {
    virtual void f(int);
    void g();
};
struct Derived : Base {
    void f(int) override;    // 重写：签名一致 + override 让编译器校验
    void f(double);          // 隐藏：名字隐藏，Base::f(int) 在派生类作用域不可见
    void g();                // 隐藏：非虚函数，静态绑定
};
```

!!! danger "名字隐藏是高频 bug"
    派生类只要声明了同名函数，基类的**所有**同名重载都会被隐藏，即使参数不同。
    解决：`using Base::f;` 把基类重载引入派生类作用域。`override` 能挡住「以为在重写、其实签名不一致」的情况。

```cpp
struct Derived : Base {
    using Base::f;           // 恢复 Base::f(int) 的可见性
    void f(double);
};
```

`final` 有两个位置：修饰虚函数（禁止继续重写）、修饰类（禁止继承）。它还能帮编译器去虚化。

## 构造函数/析构函数中调用虚函数

```cpp
struct Base {
    Base() { f(); }                       // 调用的是 Base::f
    virtual void f() { std::puts("Base::f"); }
    virtual ~Base() { f(); }              // 同样是 Base::f
};
struct Derived : Base {
    void f() override { std::puts("Derived::f"); }   // 构造/析构期间永远不会被调到
    std::string s_{"data"};
};
```

原因有两层：

1. **vptr 阶段**：基类构造期间 vptr 指向基类虚表，派生类构造完成后才改指派生类虚表；析构时反向切回。
2. **语义正确性**：基类构造时派生类成员还没构造，若调用派生实现会访问未初始化对象；析构时派生类成员已销毁，同理。

!!! note "构造函数里想用多态怎么办"
    用「两段式构造」：构造函数只做基本初始化，再提供 `init()` 虚函数由调用方显式调用；
    或者用工厂函数在对象完整构造后再分发。

## 哪些函数不能是虚函数

| 函数 | 能否虚 | 原因 |
| --- | --- | --- |
| 构造函数 | ❌ | 对象尚未建立，vptr 未初始化 |
| 静态成员函数 | ❌ | 没有 `this`，无对象可查虚表 |
| 友元函数 | ❌ | 不是成员，不参与继承体系 |
| 非成员函数 | ❌ | 同上 |
| 内联函数 | ⚠️ 可声明 | 语法允许，但动态调用时通常无法内联 |
| 析构函数 | ✅ 且常应声明 | 多态删除所必需 |
| 私有虚函数 | ✅ | NVI 惯用法：public 非虚接口 + private 虚实现 |

## 多重继承、二义性与虚继承

```cpp
struct A { int a; virtual void fa(); };
struct B { int b; virtual void fb(); };
struct C : A, B { int c; };
// C 对象布局：A 子对象（vptr_A, a）→ B 子对象（vptr_B, b）→ c
```

- 多继承对象里有**多个 vptr**（每个多态基类一个），`C*` 转 `B*` 时指针地址要**加上偏移**。
- 通过 `B*` 调用 `fb()` 时，函数内部需要把 `this` 调整回 `C*`，这个调整由 **thunk** 完成。这就是面试里「多继承下 this 指针为什么要调整」的答案。
- 成员名二义性：两个基类都有 `f()` 时 `c.f()` 编译错误，必须 `c.A::f()` 或 `c.B::f()`。

```cpp
struct Animal { int age; };
struct Mammal : virtual Animal {};      // 虚继承
struct Bird   : virtual Animal {};
struct Bat : Mammal, Bird {};           // 只有一份 Animal，b.age 无二义

// 不加 virtual：Bat 里有两份 Animal，b.age 二义，且 sizeof 更大
```

虚继承的代价：

| 开销 | 说明 |
| --- | --- |
| 虚基类指针/偏移 | 对象内需要额外指针（或 vtable 中的偏移）定位共享子对象 |
| 构造责任 | 虚基类由**最派生类**直接构造，中间类对虚基类的初始化被忽略 |
| 访问成本 | 访问虚基类成员要经过一次间接寻址 |
| 布局复杂 | 对象布局更复杂，与 C 不兼容，跨编译器 ABI 差异更大 |

!!! warning "菱形继承的正确解法通常是「不用菱形」"
    虚继承能消除数据冗余和二义性，但让布局、构造、初始化都变复杂。
    大多数设计问题用组合或接口（纯虚类）就能绕开真正的菱形。

## RTTI

```cpp
struct Base { virtual ~Base() = default; };
struct Derived : Base { void hi() { std::puts("hi"); } };

Base* p = new Derived;
if (auto* d = dynamic_cast<Derived*>(p)) d->hi();     // 失败返回 nullptr
try {
    auto& r = dynamic_cast<Derived&>(*p);             // 失败抛 std::bad_cast
    (void)r;
} catch (const std::bad_cast&) {}
```

- `dynamic_cast` 依赖虚表里的 RTTI 信息，要求源类型**是多态类型**（至少一个虚函数），否则编译错误。
- 指针转换失败返回 `nullptr`；引用转换失败抛 `std::bad_cast`（引用没有「空」值）。
- `typeid(*p)` 对多态类型给**动态类型**，`typeid(p)` 给静态类型 `Base*`；非多态类型永远给静态类型。
- 对空指针解引用取 `typeid` 抛 `std::bad_typeid`。
- `static_cast` 下行转换不做检查，错误就是 UB；`dynamic_cast` 有运行时开销（遍历继承图）。

!!! tip "什么时候关掉 RTTI"
    嵌入式、游戏引擎、部分高频交易系统会用 `-fno-rtti`（GCC/Clang）或 `/GR-`（MSVC）省体积、去掉运行时查表。
    前提是代码里不出现 `dynamic_cast`/`typeid`，改用自研的类型 id 或访问者模式。

## 对象切片

```cpp
void byValue(Shape s);                 // 切片：只拷贝 Shape 子对象，虚表变成 Shape 的
void byRef(const Shape& s);            // 正确

std::vector<Shape> v;                  // 错误用法：存进去的全被切片
std::vector<std::unique_ptr<Shape>> w; // 正确：存指针，保留动态类型
```

切片后对象的动态类型退化为基类，虚调用不再分发到派生实现（且对抽象类根本无法编译）。凡是要多态，就用指针或引用传递。

## 设计原则与常见模式

| 原则 | 一句话 |
| --- | --- |
| SRP 单一职责 | 一个类只有一个变化的原因 |
| OCP 开闭 | 对扩展开放、对修改关闭——用虚函数/模板留扩展点 |
| LSP 里氏替换 | 派生类必须能替换基类而不破坏契约（不要抛出基类没有的异常、不要加强前置条件） |
| ISP 接口隔离 | 小而专的接口，别让实现者被迫实现用不到的方法 |
| DIP 依赖倒置 | 高层依赖抽象，不依赖具体实现 |

| 模式 | 一句话 | C++ 实现要点 |
| --- | --- | --- |
| 工厂 | 把对象创建封装起来 | 返回 `std::unique_ptr<Base>`，避免裸 `new` |
| 策略 | 运行期替换算法 | 抽象基类 + `unique_ptr` 成员，或直接 `std::function` |
| 观察者 | 一对多通知 | `vector<Observer*>`，注意注销与悬垂（`weak_ptr`） |
| 单例 | 全局唯一实例 | 函数内局部静态，C++11 起线程安全 |
| RAII | 构造获取、析构释放 | 所有资源管理（锁、文件、内存）的基石 |

## 面试追问速查

???+ question "面试追问：虚函数表在哪个内存区？什么时候生成？"
    虚表是**编译期**由编译器生成的静态数据（每个多态类一张），链接后放在只读数据段
    （GCC 常见 `.data.rel.ro`，因含重定位信息）；vptr 在**运行期构造对象时**被写入，指向对应类的虚表。
    注意标准不规定这些细节，不同 ABI 有差异。

???+ question "面试追问：多继承下 this 指针为什么要调整？"
    第二个及以后的基类子对象在派生类对象中有非零偏移，`Derived*` 转 `Base2*` 要加偏移。
    通过 `Base2*` 调虚函数时，thunk 会把 `this` 减回 `Derived*` 再进入真正的实现，否则访问成员会错位。

???+ question "面试追问：为什么基类析构函数常声明为 virtual？"
    为了 `delete basePtr` 时能调用到派生类析构。非虚时只执行基类析构，派生类资源泄漏，标准定为 UB。
    代价是对象多一个 vptr；若类 `final` 或从不通过基类指针删除，可以不加。

???+ question "面试追问：虚函数可以是 inline 吗？"
    可以声明 `inline`（尤其定义在类内的虚函数隐式 inline），但通过指针/引用动态调用时编译器不知道目标，
    通常无法内联；只有去虚化（能证明动态类型）或直接对象调用时才可能内联。

???+ question "面试追问：什么是空基类优化（EBO）？"
    空类 `sizeof` 为 1（保证唯一地址），但作为**基类**时可以不占空间，`sizeof(Derived) == sizeof(int)`。
    `[[no_unique_address]]`（C++20）把同样的优化扩展到成员变量。标准库用 EBO 让带状态的 allocator 不撑大容器。

???+ question "面试追问：`dynamic_cast` 和 `static_cast` 的区别？"
    `static_cast` 编译期完成、无运行时检查，下行转换错了就是 UB；`dynamic_cast` 运行期查 RTTI，
    失败返回 `nullptr`/抛 `bad_cast`，要求源类型多态，有性能开销。向上转换两者等价，用 `static_cast` 即可。

???+ question "面试追问：为什么说「不要在构造函数里调用虚函数」？"
    因为不生效：基类构造期间 vptr 指向基类虚表，调用的是基类版本；即使能调到派生版本，派生类成员尚未构造，
    访问它们是 UB。析构期间同理。

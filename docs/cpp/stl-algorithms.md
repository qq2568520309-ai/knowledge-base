---
title: STL 算法与 lambda
tags:
  - C++
  - STL
  - 算法
  - lambda
---

# STL 算法与 lambda

算法库的价值在于：**用迭代器把「做什么」和「在哪做」解耦**。
这一章按「迭代器 → 算法 → 排序与比较器 → 可调用对象 → ranges/并行」的顺序展开，
每一层都对应面试里的一类追问。

## 迭代器：算法与容器的契约

迭代器是泛化的指针，按支持的操作分为五类（C++20 增加 contiguous）：

| 类别 | 支持操作 | 典型容器 | 典型算法 |
| --- | --- | --- | --- |
| 输入 input | `++`、`*`、单遍读 | `istream_iterator` | `find`、`accumulate` |
| 输出 output | `++`、`*=`、单遍写 | `ostream_iterator`、`back_inserter` | `copy`、`transform` |
| 前向 forward | 多遍读写、可保存 | `forward_list`、`unordered_*` | `replace`、`unique` |
| 双向 bidirectional | 额外 `--` | `list`、`map`、`set` | `reverse`、`copy_backward` |
| 随机访问 random access | `+ n`、`-`、`[]`、比较 | `vector`、`deque`、`array` | `sort`、`nth_element` |

算法在文档里写明最低迭代器要求：`std::sort` 要求随机访问，所以 `list` 用不了，只能用自己的 `sort` 成员。

```cpp
template <class It, class T>
It my_find(It first, It last, const T& value) {
    for (; first != last; ++first)
        if (*first == value) return first;
    return last;
}
// 只依赖 ++、*、!=，因此对输入迭代器也成立
```

### iterator_traits

算法需要从迭代器类型反推元素类型、差值类型，统一由 `iterator_traits` 提供：

```cpp
template <class It>
void demo(It it) {
    using value_type = typename std::iterator_traits<It>::value_type;
    using diff_t = typename std::iterator_traits<It>::difference_type;
    static_assert(std::is_same_v<value_type, int>);
    diff_t n = std::distance(it, it);   // 随机访问 O(1)，其余 O(n)
}
```

`std::distance`/`std::advance` 内部用迭代器类别标签做**重载分派**：随机访问直接相减，链表则循环前进。
这就是 traits + tag dispatch 的经典用法，模板章节还会再讲。

### 迭代器适配器

- `reverse_iterator`：`rbegin()`/`rend()`，内部 `base()` 指向当前元素的下一个位置，`*rit == *(rit.base() - 1)`；`std::begin`/`std::end` 是泛化取界，对 C 数组同样有效；
- 插入迭代器：`back_inserter`（要求 `push_back`）、`front_inserter`（要求 `push_front`）、`inserter(container, pos)`；
- 流迭代器：`istream_iterator<int> in(std::cin), eof;`、`ostream_iterator<int> out(std::cout, " ")`；
- 移动迭代器：`std::make_move_iterator`，让 `copy` 变成移动。

```cpp
std::vector<int> src{1, 2, 3}, dst;
std::copy(src.begin(), src.end(), std::back_inserter(dst));  // 自动扩容，不会越界
std::copy(src.rbegin(), src.rend(), std::ostream_iterator<int>(std::cout, " "));
```

!!! warning "迭代器失效与算法"
    算法只拿到迭代器，不知道容器。若在算法执行期间修改容器导致迭代器失效（如对 `vector` 扩容），
    行为是 UB。`std::remove_if` 之类的算法只做搬移，不改变容器大小，安全；删除必须由容器完成。

## 常用算法

### 查找与判断

```cpp
auto it = std::find(v.begin(), v.end(), 42);          // 线性，返回首个匹配
auto it2 = std::find_if(v.begin(), v.end(), [](int x) { return x % 2 == 0; });
int n = std::count_if(v.begin(), v.end(), [](int x) { return x > 0; });
bool all = std::all_of(v.begin(), v.end(), [](int x) { return x >= 0; });
bool any = std::any_of(v.begin(), v.end(), is_even);
bool none = std::none_of(v.begin(), v.end(), is_negative);
```

- `find` 用 `operator==`；`find_if` 用谓词；`find_if_not` 取反；
- `all_of` 对空区间返回 `true`（空真），这是易错点；
- 有序区间用 `binary_search`/`lower_bound`，O(log n)；
- 极值用 `min`/`max`/`minmax`、`min_element`/`max_element`/`minmax_element`，以及 `clamp`（C++17）。

### 修改序列

```cpp
std::transform(v.begin(), v.end(), out.begin(), [](int x) { return x * 2; });
std::copy_if(v.begin(), v.end(), std::back_inserter(out), [](int x) { return x > 0; });
std::fill(v.begin(), v.end(), 0);
std::generate(v.begin(), v.end(), [i = 0]() mutable { return i++; });
std::replace(v.begin(), v.end(), 1, 9);               // 所有 1 换成 9
std::reverse(v.begin(), v.end());
std::rotate(v.begin(), v.begin() + k, v.end());       // 左旋 k 位，O(n)
std::shuffle(v.begin(), v.end(), std::mt19937{std::random_device{}()});
```

### remove-erase 惯用法

`std::remove`/`remove_if` **不删除元素**，只把保留的元素前移，返回新的逻辑尾，容器大小不变。

```cpp
std::vector<int> v{1, 2, 3, 2, 4};
auto new_end = std::remove(v.begin(), v.end(), 2);
// v == {1, 3, 4, ?, ?}，new_end 指向第一个"废弃"位置
v.erase(new_end, v.end());        // 真正删除，size 变为 3

// C++20 一行完成
std::erase(v, 2);
std::erase_if(v, [](int x) { return x % 2 == 0; });
```

为什么这样设计？算法只依赖迭代器，**不能改变容器大小**；把"搬移"和"删除"拆开，
算法才能同时适用于数组、`vector`、`deque` 等不同容器。

!!! danger "只 remove 不 erase 的 bug"
    `std::remove(v.begin(), v.end(), x);` 之后 `v.size()` 不变，尾部是无效值。
    对 `list` 用成员 `remove`/`remove_if`（会真正删除）；对 `map` 用 `erase(it++)` 或 C++20 `erase_if`。

### 去重、划分、合并

```cpp
std::sort(v.begin(), v.end());
auto last = std::unique(v.begin(), v.end());  // 只去除相邻重复，需先排序
v.erase(last, v.end());

auto mid = std::partition(v.begin(), v.end(), is_even);   // 不保序，O(n)
auto mid2 = std::stable_partition(v.begin(), v.end(), is_even); // 保序，可能分配

std::merge(a.begin(), a.end(), b.begin(), b.end(), std::back_inserter(c)); // 输入需有序
std::inplace_merge(v.begin(), v.begin() + k, v.end());    // 合并同一容器的两段有序区间
```

### 排序与二分

| 算法 | 复杂度 | 稳定性 | 说明 |
| --- | --- | --- | --- |
| `sort` | 平均 O(n log n) | 否 | 内省排序，最坏也 O(n log n) |
| `stable_sort` | O(n log n) | 是 | 归并，可能额外 O(n) 空间 |
| `partial_sort` | O(n log k) | 否 | 前 k 个有序，其余无序 |
| `nth_element` | 平均 O(n) | 否 | 第 n 位就位，左边都不大于它 |
| `list::sort` | O(n log n) | 是 | 链表归并，只能成员调用 |

二分要求区间**已按同一比较器有序**：

```cpp
std::sort(v.begin(), v.end());                       // 升序
bool has = std::binary_search(v.begin(), v.end(), 7);
auto lo = std::lower_bound(v.begin(), v.end(), 7);   // 第一个 >= 7
auto hi = std::upper_bound(v.begin(), v.end(), 7);   // 第一个 > 7
auto [f, l] = std::equal_range(v.begin(), v.end(), 7); // 等价区间 [f, l)
```

`lower_bound` 手写模板（面试高频）：

```cpp
template <class It, class T>
It lower_bound_impl(It first, It last, const T& value) {
    auto len = std::distance(first, last);
    while (len > 0) {
        auto half = len / 2;
        It mid = first;
        std::advance(mid, half);
        if (*mid < value) { first = ++mid; len -= half + 1; }
        else len = half;
    }
    return first;
}
```

### 数值算法（`<numeric>`）

```cpp
int sum = std::accumulate(v.begin(), v.end(), 0);            // 初值类型决定返回类型
int prod = std::accumulate(v.begin(), v.end(), 1, std::multiplies<int>{});
std::iota(v.begin(), v.end(), 0);                             // 0,1,2,...
int dot = std::inner_product(a.begin(), a.end(), b.begin(), 0);
auto r = std::reduce(std::execution::par, v.begin(), v.end()); // C++17，顺序不保证
```

!!! warning "accumulate 的初值陷阱"
    `std::accumulate(v.begin(), v.end(), 0)` 返回 `int`，对 `double` 序列会逐元素截断。
    正确写法是 `0.0` 或 `T{}`。另外 `reduce` 要求运算满足结合律，浮点加法不满足，结果可能不确定。

## sort 的底层：内省排序

`std::sort` 不是纯快排，主流实现是 **introsort（内省排序）**：

1. 快速排序分区，三数取中选 pivot；
2. 递归深度超过 `2 * log2(n)` 时改用**堆排序**，把最坏情况压到 O(n log n)，避免有序输入退化；
3. 小区间（通常 ≤ 16）改用**插入排序**，减少递归和函数调用开销。

因此 `sort` 平均和最坏都是 O(n log n)，但**不稳定**：相等元素的相对顺序可能改变。

`stable_sort` 用归并排序；缓冲区分配失败时退化为原地归并，复杂度 O(n log² n)。
需要稳定又想要速度，可以对 `(key, index)` 排序，或排序前给元素加原始下标。

```cpp
struct Item { int key; int idx; };
std::vector<Item> items = ...;
std::stable_sort(items.begin(), items.end(),
                 [](const Item& a, const Item& b) { return a.key < b.key; });
```

!!! tip "partial_sort 与 nth_element 的选择"
    只要前 k 名且 k 远小于 n：`partial_sort`（堆，O(n log k)）。
    只要第 k 名、不关心两侧顺序：`nth_element`（平均 O(n)），常用于求中位数或 Top-K 分界。

## 比较器与严格弱序

所有排序/有序容器都要求比较器满足 **strict weak ordering（严格弱序）**：

1. 非自反：`comp(x, x) == false`；
2. 非对称：`comp(x, y)` 为真则 `comp(y, x)` 为假；
3. 传递：`comp(x, y) && comp(y, z)` 蕴含 `comp(x, z)`；
4. 等价传递：`!comp(x,y) && !comp(y,x)` 定义等价，等价关系可传递。

```cpp
std::sort(v.begin(), v.end(), [](int a, int b) { return a <= b; });  // 错误！
```

`<=` 违反非自反：`comp(x, x)` 为真，`sort` 可能越界读写，是 **UB**（不是简单的"结果不对"）。

```cpp
// 正确：按绝对值升序，绝对值相等时按原值升序，保证全序
std::sort(v.begin(), v.end(), [](int a, int b) {
    int aa = std::abs(a), ab = std::abs(b);
    return aa != ab ? aa < ab : a < b;
});
```

捕获状态的 lambda 也可作比较器（如按外部阈值排序），但必须保证比较规则在排序期间不变。

!!! danger "比较器里改状态"
    若比较器依赖可变全局状态，且比较过程中状态变化，会破坏等价类的一致性，导致越界或死循环。
    比较器应当是纯函数（对相同输入永远返回相同结果）。

## lambda：闭包对象

lambda 的本质是编译器生成的**唯一命名类**（闭包类型），捕获的变量成为成员，
函数体成为 `operator()`。默认 `operator()` 是 `const` 的。

```cpp
int base = 10;
auto add = [base](int x) { return x + base; };   // 值捕获，创建时拷贝
auto inc = [&base](int x) { return x + (++base); }; // 引用捕获，注意生命周期
auto self = [=, &base]() { return base; };       // 默认值捕获，base 例外按引用
```

| 捕获形式 | 含义 | 风险 |
| --- | --- | --- |
| `[x]` | 值捕获，拷贝一份 | 修改不影响外部；大对象有拷贝成本 |
| `[&x]` | 引用捕获 | 悬垂引用（异步、返回 lambda） |
| `[=]` / `[&]` | 默认捕获 | `[&]` 在异步场景极易悬垂 |
| `[this]` | 捕获当前对象指针 | 对象析构后调用即 UB |
| `[x = expr]` | 初始化捕获（C++14） | 可捕获移动对象 |
| `[*this]` | 按值捕获对象副本（C++17） | 对象需可拷贝 |

```cpp
auto p = std::make_unique<int>(42);
auto f = [q = std::move(p)] { return *q; };   // 初始化捕获，移动独占指针
auto g = [n = 0]() mutable { return ++n; };    // mutable 允许修改按值捕获的成员
```

!!! warning "按值捕获不是深拷贝"
    捕获的是指针/引用成员时，拷贝的只是指针。`[ptr]` 不会复制 `*ptr`，原对象销毁后依然悬垂。

lambda 在 C++14 起支持泛型参数（`[](auto x){}`），C++17 起可 `constexpr`，C++20 起可模板化并捕获包展开。
无捕获 lambda 可转换为函数指针，有捕获则不能。

## 函数对象与 std::function

函数对象（functor）是重载了 `operator()` 的类，编译器可内联，通常比函数指针更快：

```cpp
struct Square { int operator()(int x) const { return x * x; } };
std::transform(v.begin(), v.end(), out.begin(), Square{});
```

`std::function<Sig>` 是**类型擦除**容器，能装函数、lambda、成员函数绑定结果，代价是：

- 一次间接调用（通常无法内联）；
- 可能堆分配（小对象优化只覆盖小闭包，libstdc++ 约 16 字节）；
- 构造/拷贝有开销。

性能排序（一般情况）：**模板参数 / lambda（可内联） > 函数指针 > `std::function`**。
只有需要"运行时多态的可调用对象"（回调注册、事件表）才用 `std::function`。

```cpp
void register_cb(std::function<void(int)> cb);
register_cb([](int x) { std::cout << x; });   // 存起来，调用时无法内联

// std::bind 的坑：嵌套 bind、占位符作用域、按值/引用语义不直观
using namespace std::placeholders;
auto f = std::bind(&Foo::bar, &foo, _1);
auto better = [&foo](int x) { return foo.bar(x); };  // 更清晰，建议用 lambda
```

相关工具：`std::mem_fn(&T::f)` 把成员函数指针变成可调用对象；`std::not_fn(pred)`（C++17）取反谓词；
`std::ref`/`std::cref` 让 `bind`/`thread` 按引用传递，避免 `reference_wrapper` 被拷贝成值。

## 算法 vs 手写循环

| 维度 | STL 算法 | 手写循环 |
| --- | --- | --- |
| 可读性 | 意图明确（`find_if` 一眼看懂） | 取决于写法，容易埋逻辑 |
| 正确性 | 边界已处理好 | 易漏 `end()`、易写错步长 |
| 性能 | 通常等价，内联后无额外开销 | 可针对场景特化（如提前 break、SIMD） |
| 调试 | 断点难进模板 | 逐行可控 |

原则：**先用算法表达意图，性能热点再考虑手写或特化**。`for_each` 不如 range-for 直观，优先 range-for。

## ranges（C++20）

ranges 把"容器/区间"变成一等公民，支持惰性视图与管道：

```cpp
#include <ranges>
namespace rv = std::views;

auto result = nums | rv::filter([](int x) { return x % 2 == 0; })
                   | rv::transform([](int x) { return x * x; })
                   | rv::take(5);

std::vector<int> out;
std::ranges::copy(result, std::back_inserter(out));
std::ranges::sort(out);          // 直接传容器，不必 begin/end
```

- 视图是**惰性**的，不分配、不拷贝元素；但要注意底层区间生命周期；
- `views::filter` 的迭代器可能多次计算谓词，谓词最好无副作用；
- C++20 的 ranges 算法对投影（projection）友好，如 `sort(v, {}, &Person::age)`。

## 并行算法（C++17）

```cpp
#include <execution>
std::sort(std::execution::par, v.begin(), v.end());
std::for_each(std::execution::par_unseq, v.begin(), v.end(), [](int& x) { x *= 2; });
```

执行策略：`seq`（串行）、`par`（多线程）、`par_unseq`（可向量化）、C++20 的 `unseq`。
限制：元素访问函数不得有数据竞争、不得抛异常（抛出会 `std::terminate`）、不得在内部加锁；
`par_unseq` 下函数甚至可能在同一线程交错执行。实际收益取决于数据规模和实现，小数组往往更慢。

## 面试追问

???+ question "面试追问：为什么 remove 不删除元素？"
    算法只操作迭代器区间，无法改变容器大小（不同容器删除方式不同）。
    `remove` 把不等于目标值的元素依次前移，返回新逻辑尾；真正删除要容器 `erase`。
    C++20 提供 `std::erase`/`std::erase_if` 一步完成。对 `list` 直接用成员 `remove`。

???+ question "面试追问：sort 是稳定排序吗？如何稳定排序？"
    `std::sort` 不稳定，底层内省排序；`std::stable_sort` 稳定，用归并，可能额外 O(n) 空间。
    若必须稳定又要控制内存，可对 `pair<key, index>` 排序，或自己实现归并。

???+ question "面试追问：如何按 value 对 map 排序？"
    `map` 按 key 有序，不能按 value 重排。把元素拷贝到 `vector<pair<K,V>>`，
    用 lambda `[](auto& a, auto& b){ return a.second < b.second; }` 排序；
    若 value 可能相等且需要稳定，用 `stable_sort` 或比较时加上 key。

???+ question "面试追问：lower_bound 与 upper_bound 的区别？"
    `lower_bound` 返回第一个 **不小于** value 的位置（`>=`），`upper_bound` 返回第一个 **大于** value 的位置（`>`）。
    两者相减得到等价元素个数，`equal_range` 一次返回这对迭代器。
    要求区间已按同一比较器有序；手写时用 `len/2` 折半，注意 `advance` 与边界更新。

???+ question "面试追问：std::function 为什么慢？什么时候必须用？"
    类型擦除导致调用经虚函数/函数指针间接，难以内联；闭包超过小对象缓冲区会堆分配。
    需要运行时多态回调（插件、事件总线、回调表）时用；模板能解决的场景不要用。

???+ question "面试追问：迭代器失效后继续用算法会怎样？"
    UB。典型如对 `vector` 一边 `push_back` 一边用旧迭代器遍历；`erase` 后继续 `++it`。
    正确做法是用 `erase` 的返回值、先收集下标再删除，或改用 `remove_if` + `erase`。

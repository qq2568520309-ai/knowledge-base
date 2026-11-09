---
title: STL 容器
tags:
  - C++
  - STL
  - 容器
---

# STL 容器

STL 的容器不是"一堆数据结构"的集合，而是一套通过**迭代器**把数据结构和算法解耦的泛型框架。
面试问容器，本质是在问三件事：内存怎么排布、操作复杂度从哪来、什么操作会让迭代器失效。

## STL 六大组件

| 组件 | 作用 | 典型代表 |
| --- | --- | --- |
| 容器 container | 管理元素集合与内存 | `vector`、`map`、`list` |
| 算法 algorithm | 通过迭代器操作区间 | `sort`、`find`、`transform` |
| 迭代器 iterator | 容器与算法之间的统一接口 | `vector<int>::iterator` |
| 仿函数 functor | 可被调用的对象，作策略参数 | `std::less`、lambda |
| 适配器 adaptor | 改变接口或底层容器 | `stack`、`reverse_iterator` |
| 分配器 allocator | 分离"分配内存"与"构造对象" | `std::allocator`、`pmr` |

```cpp
// 算法不知道容器的存在，只认迭代器区间
std::vector<int> v{3, 1, 2};
std::sort(v.begin(), v.end());            // 随机访问迭代器
std::list<int> l{3, 1, 2};
l.sort();                                  // list 只能用成员 sort
```

!!! tip "泛型编程的核心"
    算法只依赖迭代器**类别**提供的操作，而不是具体容器。这就是为什么 `sort` 要求随机访问迭代器，
    而 `find` 只要求输入迭代器——约束写在接口上，编译期检查，零运行时开销。

## 容器分类

| 类别 | 容器 | 头文件 | 底层结构 |
| --- | --- | --- | --- |
| 序列式 | `vector` `deque` `list` `forward_list` `array` | `<vector>` `<deque>` `<list>` `<forward_list>` `<array>` | 动态数组 / 分段数组 / 链表 |
| 有序关联式 | `map` `multimap` `set` `multiset` | `<map>` `<set>` | 红黑树 |
| 无序关联式 | `unordered_map` `unordered_multimap` `unordered_set` `unordered_multiset` | `<unordered_map>` `<unordered_set>` | 哈希表 + 桶 |
| 容器适配器 | `stack` `queue` `priority_queue` | `<stack>` `<queue>` | 默认 `deque` / `vector` |
| 特殊 | `string` `vector<bool>` `span`(C++20) | `<string>` `<vector>` `<span>` | SSO 缓冲区 / 位压缩 |

## vector：三段式指针

`vector` 对象本身通常只有三个指针（24 字节），元素存放在堆上：

```cpp
template <class T, class Alloc = std::allocator<T>>
class vector {
    T* begin_;   // 首元素
    T* end_;     // 尾后位置，size = end_ - begin_
    T* cap_;     // 容量尾，capacity = cap_ - begin_
};
```

- `size()` 是已构造元素个数，`capacity()` 是不重新分配时最多能放的个数。
- `size() <= capacity()` 恒成立；`capacity()` 之外的原始内存没有对象，访问是 UB。
- `data()` 返回连续内存首地址，可与 C 接口互操作。

```cpp
std::vector<int> v;
v.reserve(100);              // 只改 capacity，不构造元素，size 仍为 0
v.resize(10);                // 构造 10 个值初始化元素，size == 10
std::cout << v.size() << ' ' << v.capacity();  // 10 100
```

!!! warning "reserve 与 resize 别混"
    `reserve(n)` 改的是容量，不改变元素个数，不能随后直接 `v[0] = 1`（元素还不存在）。
    `resize(n)` 改的是元素个数，会构造或析构元素。想在循环里避免反复扩容，用 `reserve`。

### 扩容过程与均摊 O(1)

`push_back` 在 `size == capacity` 时触发扩容：

1. 按增长策略申请新内存（libstdc++ 为 2 倍，MSVC 约 1.5 倍）；
2. 把旧元素**移动构造**（移动构造非 `noexcept` 时退化为拷贝）到新内存；
3. 析构旧元素、释放旧内存；
4. 更新三个指针。

若元素的移动构造声明为 `noexcept`，扩容走移动；否则标准允许退化为拷贝，以保证强异常安全。

**均摊 O(1) 证明**：按倍数扩容，第 k 次扩容拷贝 $1 + 2 + 4 + \dots + 2^k < 2^{k+1}$ 个元素，
总代价与最终元素数 $n$ 同阶，因此单次 `push_back` 均摊常数时间。
若每次只加固定常数 $c$，总拷贝代价是 $O(n^2)$。

!!! danger "扩容用倍数而不是固定增量"
    固定增量会让 `push_back` 退化为均摊 O(n)。倍数扩容牺牲最多约一倍冗余空间，换取均摊 O(1)。

### 迭代器失效

| 操作 | 失效范围 |
| --- | --- |
| 扩容（`push_back`/`insert` 触发） | 全部迭代器、指针、引用 |
| `insert`/`emplace` 未扩容 | 插入点及之后的迭代器（引用是否失效由标准实现决定，通常不失效） |
| `erase` | 删除点及之后的迭代器；被删元素的引用失效 |
| `reserve`/`shrink_to_fit` 改变容量 | 全部 |
| `clear` | 全部（但 capacity 不变） |
| `swap` | 迭代器仍指向原元素，但归属交换 |

```cpp
std::vector<int> v{1, 2, 3, 4};
for (auto it = v.begin(); it != v.end();) {
    if (*it % 2 == 0) it = v.erase(it);  // erase 返回下一个有效位置
    else ++it;
}
```

### at 与 operator[]

`operator[]` 不做边界检查，越界是 UB；`at()` 越界抛 `std::out_of_range`。
热路径用 `[]`，对外接口或调试期用 `at()`。

### `vector<bool>` 的坑

标准对 `vector<bool>` 做了位压缩特化：每个元素只占 1 bit。

```cpp
std::vector<bool> vb{true, false};
auto b = vb[0];        // 返回代理对象 vector<bool>::reference，不是 bool&
// bool* p = &vb[0];   // 编译错误：不能取地址
// bool& r = vb[0];    // 编译错误
```

- 没有 `data()`，不能传给 `bool*` 接口；
- `operator[]` 返回代理，`auto` 推导出代理而非 `bool`，泛型代码里容易出问题；
- 多线程写不同 bit 不是线程安全的（同一机器字）。

需要位压缩用 `std::bitset`（定长）或 `vector<uint8_t>`/`deque<bool>`（要真引用）。

## deque：分段连续

`deque` 用一段**中控数组**（map）存放多个指向固定大小缓冲区的指针，缓冲区首尾相接逻辑上构成双端队列。

```text
map: [ p0 ][ p1 ][ p2 ] ...   →  每个指针指向一块固定大小的 chunk（libstdc++ 512 字节）
```

- 头尾插入删除均摊 O(1)，且**不需要搬移已有元素**，只在当前 chunk 满时新分配一块；
- 随机访问 O(1)，但要两级寻址：先算 chunk 下标，再算块内偏移，比 `vector` 多一次间接；
- 中间 `insert`/`erase` 要搬移元素，O(n)；
- 没有 `capacity()`/`reserve()`（容量按块增长，概念不适用）；
- 迭代器比裸指针复杂得多（含 cur/first/last/node 四个指针），排序、遍历稍慢。

`deque` 适合**两端频繁增删、又需要随机访问**的场景，也是 `stack`/`queue` 的默认底层容器。

## list 与 forward_list

每个节点由 `prev`/`next` 指针和值组成，节点独立分配。
- `list` 双向链表，`forward_list` 单向链表（省一个指针，但只支持前向迭代）；
- 任意位置插入删除 O(1)，前提是**已经持有该位置的迭代器**；按值查找仍是 O(n)；
- 每个节点独立分配，缓存局部性差，遍历性能通常远低于 `vector`；
- `splice` 把另一条链表的节点摘下挂到当前链表，O(1)，不拷贝不移动元素；
- 成员 `sort()` 用归并排序（稳定），因为 `std::sort` 需要随机访问迭代器；`forward_list` 还有 `sort`/`merge`/`splice_after`。

```cpp
std::list<int> a{1, 2, 3}, b{4, 5};
auto pos = std::next(a.begin());
a.splice(pos, b);          // b 的节点整体挂到 a，b 变空，无元素拷贝
a.sort(std::greater<int>{});  // 成员函数，不是 std::sort
```

!!! warning "别用 list 做「插入快」的默认选择"
    现代 CPU 上，`vector` 中间插入的搬移往往比链表遍历找位置更快。
    只有在节点很大、插入位置已持有迭代器、且要求引用稳定时才优先考虑链表。

## array：零开销定长数组

```cpp
std::array<int, 5> a{1, 2, 3, 4, 5};
static_assert(sizeof(a) == sizeof(int) * 5);  // 无额外成员，可聚合初始化
```

- 大小是编译期常量，对象在栈上（或作为成员内联），无堆分配；
- 不是指针，不会退化为指针，`std::size(a)` 安全；
- 有 `begin/end`，可配合 STL 算法；`at()` 带检查；
- 与 C 数组相比：能按值传递、能拷贝、有越界检查版本、类型安全。

## string：SSO 与 COW

`std::string` 通常包含指针、长度、以及一块 16 字节左右的本地缓冲区。
短字符串（libstdc++ 15 字符，MSVC 15 字符）直接存在对象内部，不分配堆内存，即 **SSO（Small String Optimization）**。

```cpp
std::string s = "hi";          // 走 SSO，无堆分配
std::cout << s.capacity();     // libstdc++ 通常为 15
std::string big(100, 'x');     // 超过 SSO 阈值，堆分配
```

- **COW（Copy-On-Write）**：C++98 时代一些实现用引用计数共享缓冲区，写时复制。
  C++11 起标准实际上禁止了 COW：`operator[]` 返回引用、迭代器失效规则、并发只读等要求使其无法满足。
  面试若问"string 是 COW 吗"，答"现代实现不是，C++11 后不允许"。
- `c_str()` 返回以 `\0` 结尾的缓冲区，C++11 起保证 `data()` 与 `c_str()` 等价且可读；
- 修改字符串（扩容、`append` 等）可能使 `c_str()` 返回的指针失效，不能长期保存；
- 容量相关：`reserve`、`shrink_to_fit`（非强制）、`capacity`；
- `string_view`（C++17）：只含指针 + 长度，**不拥有**内存、不保证 `\0` 结尾。

```cpp
std::string_view sv = "hello world";
sv = sv.substr(0, 5);          // O(1)，不开辟新字符串
// 不能写 sv[0] = 'H';         // 只读视图
```

!!! danger "string_view 悬垂"
    `string_view` 不延长生命周期。`std::string_view sv = std::string("tmp");` 或
    从临时 `string` 的 `c_str()` 构造，都会立刻悬垂。只在被引用对象生命周期覆盖整个使用时使用。

## 红黑树：map/set 的底层

### 从 BST 退化说起

普通二叉搜索树在有序插入时退化成链表，查找 O(n)。平衡树通过旋转维持高度 O(log n)：

- **AVL 树**：任一节点左右子树高度差不超过 1，平衡严格，查找更快，但插入删除旋转次数多；
- **红黑树**：用颜色约束近似平衡，最长路径不超过最短路径的 2 倍，高度 ≤ 2log(n+1)，旋转更少。

### 五条性质

1. 每个节点非红即黑；
2. 根节点是黑色；
3. 每个叶子（NIL 空节点）是黑色；
4. 红色节点的两个子节点必须是黑色（不能有连续红节点）；
5. 从任一节点到其所有叶子的路径上黑节点数量相同（黑高相等）。

由性质 4、5 可推出：最长路径（红黑交替）≤ 2 × 最短路径（全黑），因此树高被限制在 O(log n)。

插入先染红再调整（违反性质 4 时看叔叔节点颜色，决定变色还是旋转）；删除更复杂，
需要处理"双黑"并向上借位。**面试一般只需说清五条性质和调整思路，不必手写完整旋转。**

!!! tip "为什么 map 用红黑树而不是 AVL 或哈希"
    `map` 需要**有序遍历**和**稳定的迭代器/引用**：插入删除只影响局部，迭代器不失效。
    红黑树旋转少、写性能好，是有序关联容器的工业标准选择。哈希表无序，且 rehash 会使迭代器失效。

`map`/`set` 的特性：

- 元素按 key 有序（默认 `std::less<Key>`），中序遍历即升序；
- 查找/插入/删除 O(log n)；
- `map` 的 `value_type` 是 `std::pair<const Key, T>`，key 不可改；`set` 的 key 即 value，也不可改；
- `operator[]` 在 key 不存在时**插入**默认值，因此不能用于 `const map`；只想查询用 `find` 或 `at`；
- 插入失败（重复 key）返回 `pair<iterator, bool>`，`bool` 表示是否插入成功。

```cpp
std::map<std::string, int> m;
m["a"] = 1;                              // 不存在则插入 {"a", 0} 再赋值
if (auto it = m.find("b"); it != m.end()) { /* 命中 */ }
m.emplace("c", 3);                       // 原地构造，避免临时 pair
```

## 哈希表：unordered_map/set

典型实现：**桶数组 + 链地址法**（libstdc++ 把所有节点串成一条单链表，桶里存前驱指针）。

- `bucket_count()` 桶数量，`load_factor() = size / bucket_count`；
- `max_load_factor()` 默认 1.0，超过触发 **rehash**：桶数组扩容（通常约 2 倍），重新分配节点到新桶；
- `rehash(n)` 手动设置桶数，`reserve(n)` 预留可容纳 n 个元素而不 rehash 的桶数；
- 平均 O(1)，最坏 O(n)（所有 key 落同一桶）；哈希函数质量决定实际性能。

!!! warning "rehash 的失效规则"
    rehash 使**所有迭代器失效**，但标准保证**指向元素的引用和指针仍然有效**（节点本身不搬移，只改桶链）。
    这与 `vector` 扩容完全不同，是高频追问点。

自定义 key 需要提供哈希函数和相等比较：

```cpp
struct Point { int x, y; bool operator==(const Point& o) const { return x == o.x && y == o.y; } };

struct PointHash {
    std::size_t operator()(const Point& p) const noexcept {
        // 组合哈希，避免简单相加导致大量冲突
        std::size_t h1 = std::hash<int>{}(p.x);
        std::size_t h2 = std::hash<int>{}(p.y);
        return h1 ^ (h2 + 0x9e3779b97f4a7c15ULL + (h1 << 6) + (h1 >> 2));
    }
};

std::unordered_map<Point, int, PointHash> mp;
```

### map 与 unordered_map 对比

| 维度 | `map` | `unordered_map` |
| --- | --- | --- |
| 底层 | 红黑树 | 哈希桶 + 链表 |
| 顺序 | key 有序 | 无序 |
| 查找 | O(log n) | 平均 O(1)，最坏 O(n) |
| 插入删除 | O(log n)，迭代器稳定 | 平均 O(1)，rehash 时迭代器失效 |
| 内存 | 每节点三指针 + 颜色 | 桶数组 + 节点指针，通常更费 |
| 要求 | key 可比较（严格弱序） | key 可哈希且可相等比较 |
| 适用 | 范围查询、有序输出 | 纯查找、追求平均性能 |

## 容器适配器

适配器不自己管理数据，而是包装一个底层容器并限制接口。

| 适配器 | 默认底层 | 可用底层 | 特点 |
| --- | --- | --- | --- |
| `stack` | `deque` | `vector`/`deque`/`list` | LIFO，`push/pop/top` |
| `queue` | `deque` | `deque`/`list` | FIFO，`push/pop/front/back` |
| `priority_queue` | `vector` | `vector`/`deque` | 堆，`push/pop/top` |

`priority_queue` 是**大顶堆**（默认 `std::less`），底层用 `std::make_heap`/`push_heap`/`pop_heap` 维护：

```cpp
std::vector<int> v{3, 1, 4, 1, 5};
std::make_heap(v.begin(), v.end());              // 构建大顶堆 O(n)
v.push_back(9); std::push_heap(v.begin(), v.end());   // O(log n)
std::pop_heap(v.begin(), v.end());               // 最大值移到末尾，O(log n)
int top = v.back(); v.pop_back();
```

取前 k 大：维护大小为 k 的**小顶堆**，遍历数组，比堆顶大就替换，时间 O(n log k)，空间 O(k)。

## 复杂度与选型

| 容器 | 随机访问 | 尾部插入 | 中间插入 | 查找 | 迭代器类别 |
| --- | --- | --- | --- | --- | --- |
| `vector` | O(1) | 均摊 O(1) | O(n) | O(n) | 随机访问 |
| `deque` | O(1) | 均摊 O(1) | O(n) | O(n) | 随机访问 |
| `list` | O(n) | O(1) | O(1) | O(n) | 双向 |
| `forward_list` | O(n) | O(1)（首部/已知位置后） | O(1) | O(n) | 前向 |
| `array` | O(1) | 不支持 | 不支持 | O(n) | 随机访问 |
| `map`/`set` | — | — | O(log n) | O(log n) | 双向 |
| `unordered_*` | — | — | 平均 O(1) | 平均 O(1) | 前向 |

选型顺序：默认 `vector`（连续内存、缓存友好，绝大多数场景最快）；需要两端增删且随机访问选 `deque`；
需要有序、范围查询、迭代器稳定选 `map`/`set`；只按 key 快速查找选 `unordered_*`；
在已知位置频繁插入删除且元素大、要求引用稳定选 `list`；定长无堆分配选 `array`；
只需一端进出用 `stack`/`queue`/`priority_queue`，语义更清晰。

!!! warning "线程安全"
    标准库容器**不是线程安全的**。多线程写同一容器必须加锁；**不同元素**的并发修改在无结构性改变时允许
    （`vector<bool>` 例外）；多线程只读（全为 `const` 操作）是安全的。

## 分配器与内存管理

`allocator` 把"分配原始内存"和"构造对象"拆成两步：`allocate/deallocate` 与 `construct/destroy`。
`vector` 扩容时先分配裸内存，再用移动构造逐个建对象，正是这个分离的体现。

C++17 的 `std::pmr`（polymorphic memory resource）把分配器从**编译期模板参数**变成**运行时多态**：

```cpp
#include <memory_resource>
std::pmr::monotonic_buffer_resource pool;
std::pmr::vector<int> v{&pool};   // 从池上分配，批量释放，适合短生命周期高频分配
```

适用场景：解析、序列化等大量小对象、统一释放的场合；注意池的生命周期必须长于容器。

## 面试追问

???+ question "面试追问：vector 扩容为什么用倍数，1.5 倍和 2 倍有何区别？"
    倍数扩容保证均摊 O(1)；固定增量会退化为 O(n²)。
    2 倍实现简单、拷贝次数少，但更容易出现"刚扩容完又浪费一半"的内存碎片；
    1.5 倍（MSVC 常用）内存增长率更温和，且理论上更利于复用前面释放的块。
    标准不规定倍数，只说 `push_back` 均摊常数，具体由实现决定。

???+ question "面试追问：clear() 会释放内存吗？shrink_to_fit 呢？"
    `clear()` 只析构元素、把 size 置 0，**capacity 不变**，内存仍可复用。
    `shrink_to_fit()` 请求把 capacity 降到 size，但标准说它是**非强制**的，实现可以忽略。
    真正释放可用 `vector<T>().swap(v)`（C++11 起也可 `v.shrink_to_fit()` 后再看实现）。

???+ question "面试追问：push_back 与 emplace_back 的区别？"
    `push_back` 接收已构造的对象（左值拷贝、右值移动）；`emplace_back` 把参数完美转发到
    容器内**原地构造**，省一次临时对象。对 `std::string` 这类类型，`emplace_back("abc")`
    直接构造，而 `push_back("abc")` 会先构造临时 `string` 再移动。
    但 `emplace_back` 也可能因隐式转换引发意外构造，且不能用于初始化列表场景。

???+ question "面试追问：map 的 operator[] 和 insert 有什么区别？"
    `operator[]` 在 key 不存在时会**插入**一个值初始化的元素再返回引用，因此不能用于 `const map`，
    也可能造成"只想查却插入了"的 bug；`insert`/`emplace` 不覆盖已有值（返回 `bool` 表示是否插入）；
    `at` 不存在时抛异常；`find` 不插入。查询优先 `find`，插入优先 `emplace`。

???+ question "面试追问：迭代器失效怎么系统性记忆？"
    按"内存是否重排"分两类：**重排型**（`vector` 扩容/`reserve`、`string` 扩容、`deque` 中间插入删除）
    全部或大面积失效；**局部型**（`vector` 未扩容的 insert/erase、`list`/`map`/`set` 的插入删除）
    只有被删元素及其后的迭代器失效，其他节点稳定。
    哈希表 rehash 失效迭代器但引用/指针仍有效。答题时先分类，再举容器例子。

---
title: 性能优化与问题排查
tags:
  - C++
  - 性能优化
  - 调试
  - 性能分析
---

# 性能优化、调试与问题排查

性能工作的顺序永远是：**测量 → 定位 → 假设 → 验证**。没有 profile 的"优化"只是把代码改得更难懂。
本章覆盖方法论、CPU/内存层面的真实开销、容器与 IO 的取舍，以及线上崩溃、泄漏、卡顿的排查手段。

!!! tip "三条铁律"
    1. 先有**可复现的基准**，再动代码；否则你不知道是变快还是变慢。
    2. 优化**热点**，不要优化"看起来慢"的代码。99% 的时间通常在 1% 的代码里。
    3. 每次只改一个变量，用同一份基准对比，并保留回滚点。

## 方法论

### Amdahl 定律

若某部分占总耗时比例 `p`，加速 `s` 倍，整体加速比为：

```
speedup = 1 / ((1 - p) + p / s)
```

推论：占 10% 的代码优化 10 倍，整体只有 1.09 倍；把 90% 的那部分优化 2 倍，整体 1.82 倍。
**优化前先算理论上限**，别在无关紧要的地方死磕。

### 瓶颈分类

| 类型 | 典型征兆 | 优先手段 |
| --- | --- | --- |
| CPU-bound | `top` 单核 100%，IPC 低 | 算法、减少分支、向量化、`-O3` |
| Memory-bound | cache miss 高，内存带宽打满 | 提升局部性、SoA、减少间接寻址 |
| IO-bound | `iowait` 高，线程阻塞在 `read` | 缓冲、批量、异步、mmap |
| Lock-bound | 多核不线性扩展，`perf` 显示 futex | 减小临界区、分片锁、无锁结构 |
| 分配器 | 热点在 `malloc`/`free` | 对象池、arena、`pmr` |

### 基准测试

```cpp
#include <chrono>
#include <cstdio>

int main() {
    volatile int sink = 0;                   // 防止整个循环被优化掉
    auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < 1000000; ++i) sink += 1;
    auto t1 = std::chrono::steady_clock::now();
    std::printf("%.1f ns/op\n",
        std::chrono::duration<double, std::nano>(t1 - t0).count() / 1e6);
}
```

- 用 `steady_clock`，不要用 `system_clock`（可能被 NTP 调整）。
- 先 warmup，再取多次运行的**中位数**；关掉 CPU 调频（`cpupower frequency-set -g performance`）。
- 真正做项目用 **Google Benchmark**：`BENCHMARK(BM_X)->Range(8, 8<<10);`，自带 `DoNotOptimize` / `ClobberMemory` 与统计。

!!! warning "微基准的常见陷阱"
    循环被完全优化掉、数据全在 L1、与实际输入规模不符、编译器把结果算成常量——都会给出"假的好成绩"。
    基准里必须有 `DoNotOptimize` 或 `volatile` 写入，并且输入规模要接近真实。

## 性能分析工具

| 工具 | 维度 | 典型用法 |
| --- | --- | --- |
| `perf` | 采样（CPU、cache、分支） | `perf record -g -F 999 ./app` → `perf report` |
| 火焰图 | 可视化采样结果 | `perf script \| stackcollapse-perf.pl \| flamegraph.pl > f.svg` |
| `gprof` | 插桩（调用计数） | `g++ -pg`，运行后 `gprof ./app gmon.out` |
| `valgrind --tool=callgrind` | 指令级模拟 | 精确但慢 20–50 倍，配 `kcachegrind` 看调用图 |
| `valgrind --tool=massif` | 堆内存峰值 | 定位"谁吃掉了内存" |
| `heaptrack` | 分配次数与泄漏 | 比 massif 更易用，带分配栈 |
| VTune / perf c2c | 硬件计数器、伪共享 | 定位 cache line 争用 |
| `-fopt-info` | 编译器优化报告 | 看哪些循环没向量化、哪些调用没内联 |

```bash
perf record -F 999 -g -- ./app            # 采样
perf report --stdio | head -50            # 热点函数
perf stat -e cache-misses,cache-references,branch-misses ./app
perf c2c record ./app                     # 伪共享 / cache line 争用

g++ -O2 -fopt-info-vec-optimized=vec.txt -c hot.cpp
g++ -O2 -fopt-info-missed=miss.txt -c hot.cpp    # 为什么没优化
```

## 缓存与内存访问

x86-64 的 cache line 是 **64 字节**；Apple Silicon 为 128 字节。CPU 每次取数都按行搬，所以**访问模式比访问次数更重要**。

| 层级 | 延迟（量级） | 容量 |
| --- | --- | --- |
| L1 | ~4 cycles | 32–64 KB/核 |
| L2 | ~12 cycles | 256 KB–1 MB/核 |
| L3 | ~40 cycles | 数 MB–数十 MB，多核共享 |
| DRAM | ~80–120 ns（数百 cycle） | GB 级 |

**局部性**：时间局部性（刚用过的还会用）、空间局部性（旁边的马上会用）。

```cpp
constexpr int N = 4096;
int a[N][N];

// 行优先：连续访问，几乎每行只有一次 cache miss
for (int i = 0; i < N; ++i)
    for (int j = 0; j < N; ++j) a[i][j] += 1;

// 列优先：每次跨 4096*4 字节，cache 完全失效，慢一个数量级
for (int j = 0; j < N; ++j)
    for (int i = 0; i < N; ++i) a[i][j] += 1;
```

**AoS vs SoA**：只用一个字段时，`struct { float x, y, z; }` 数组会浪费 2/3 的带宽；拆成三个数组（SoA）则连续无浪费，也更容易自动向量化。

```cpp
struct ParticleAoS { float x, y, z; };
struct ParticlesSoA { std::vector<float> x, y, z; };   // 只更新 x 时优
```

!!! danger "false sharing（伪共享）"
    两个线程写**同一 cache line 上的不同变量**，硬件仍要来回同步整行，性能可能下降数倍。
    现象：多线程扩展性差，但 `perf c2c` 显示冲突地址并不相同。

```cpp
struct alignas(64) Counter { std::atomic<long> v{0}; };  // 各占一行
Counter c[8];                                            // 按线程索引使用
```

其余手段：软件预取 `__builtin_prefetch(p + 64)`（只对可预测的流式访问有效）、减少指针追逐（链表/树天然不友好）、把热数据放在一起。

!!! tip "分支预测"
    现代 CPU 流水线很深，一次分支误预测约 15–20 cycle。热点循环里可用**无分支写法**：

    ```cpp
    // 分支版：随机数据下误预测率高
    int abs_branch(int x) { return x < 0 ? -x : x; }
    // 无分支版：编译器通常能生成 cmov / 位运算
    int abs_branchless(int x) { int m = x >> 31; return (x ^ m) - m; }
    ```

    但别滥用：可预测的分支（如几乎总是 true）比位运算更快，`-O2` 也可能已生成 `cmov`。先测再换。

## 对象与调用开销

| 机制 | 开销 | 说明 |
| --- | --- | --- |
| 虚函数调用 | 1 次间接跳转 + 可能的误预测 | 约 1–5 ns，热点里才明显 |
| 模板 | 零运行时开销 | 代价是编译时间与代码膨胀 |
| `std::function` | 一次间接调用 + 可能堆分配 | libstdc++ 有 16 字节 SBO，超出即 `new` |
| 异常 | 正常路径零开销（表驱动） | throw 时展开栈，代价高；不要用异常做流程控制 |
| RTTI `dynamic_cast` | 遍历继承图 | 引用转换失败抛异常，指针转换失败返回 `nullptr` |

```cpp
// 热点里的多态：模板编译期绑定、可内联，无 std::function 的类型擦除
template <class F> void for_each(F&& f) { f(0); }
// 或 C 风格函数指针 + void* 上下文
```

!!! warning "异常与 RTTI 的取舍"
    `-fno-exceptions` / `-fno-rtti` 能减小体积、略提性能，但标准库组件（如 `std::function` 的目标类型、`dynamic_cast`）会不可用。
    游戏/嵌入式常见，服务端一般不值得。

## 拷贝与移动

- 只读大对象传 `const T&`；小对象（`int`、指针、`std::string_view`）**按值传**更快。
- C++17 起**返回值保证省略**（prvalue 直接构造在目标位置），`return std::vector<int>{...}` 不会多一次拷贝。
- `std::move` 只是把左值转成右值引用，**不移动任何东西**；对 `const` 对象用 `move` 会退化成拷贝。
- `emplace_back` 原地构造，省一次临时对象；但传入已有对象时 `push_back` 与它等价，别为了"显得现代"而滥用。

```cpp
std::vector<std::string> v;
v.reserve(1000);                       // 避免多次扩容 + 搬移
v.emplace_back(10, 'x');               // 直接构造，不产生临时 string
std::string s = make_name();           // RVO，无拷贝
auto t = std::move(s);                 // 之后不要再用 s 的值
```

**SSO / SBO**：libstdc++ 的 `std::string` 有 15 字符内联缓冲（对象共 32 字节），libc++ 为 22；`std::function` 的内联缓冲通常 16 字节。超出就走堆分配——短字符串与短 lambda 因此几乎零成本。

## 容器性能

| 场景 | 选择 | 原因 |
| --- | --- | --- |
| 顺序遍历为主 | `vector` | 连续内存、预取友好 |
| 频繁中间插入/删除 | `list` / `deque` | 但要接受指针追逐的代价 |
| 有序查找 | `map` / `set` | O(log n)，节点分散 |
| 只需查找 | `unordered_map` | 平均 O(1)，注意 hash 质量与 rehash |
| 小规模有序数据 | 排序 `vector` + 二分 | 常数小、缓存友好（`flat_map` 思路） |

```cpp
std::vector<int> v;
v.reserve(n);                          // 一次性分配，避免 1.5x/2x 反复扩容
std::unordered_map<int, int> m;
m.reserve(n);                          // 按预期元素数预留桶，减少 rehash
```

!!! note "为什么 `vector` 遍历比 `list` 快"
    不是"算法复杂度"问题，而是**内存布局**：`vector` 元素连续，一次 cache line 装 16 个 `int`，硬件预取器能提前取下一行；
    `list` 每个节点一次随机访存，几乎每次都是 cache miss，还多一次指针解引用。实测常差 5–10 倍。

**分配器与内存池**：`new`/`delete` 要走通用分配器，小对象频繁分配是热点。方案：

- 对象池 / freelist：固定大小对象复用。
- **arena**：一次申请大块，按需 bump 指针，统一释放（适合请求级生命周期）。
- **`std::pmr`**（C++17）：`std::pmr::monotonic_buffer_resource` + `std::pmr::vector`，把分配策略变成类型的一部分。

```cpp
#include <memory_resource>
std::byte buf[4096];
std::pmr::monotonic_buffer_resource pool(buf, sizeof buf);
std::pmr::vector<int> v(&pool);        // 分配全部来自栈上缓冲
```

## 字符串与 IO

- 拼接：`s += "x"` 优于 `s = s + "x"`（后者产生临时对象）；已知总长时先 `reserve`。
- 只读视图用 `std::string_view`，避免 `const std::string&` 造成的隐式构造；注意它**不拥有数据**，不能指向已销毁的临时串。
- 格式化：`std::ostringstream` 灵活但慢（虚函数 + locale）；高频路径用 `snprintf` 到栈缓冲；C++20 起用 `std::format`（类型安全、性能接近 `printf`）。
- IO：`std::cout` 与 C stdio 同步会拖慢，竞技/批量输出前 `std::ios::sync_with_stdio(false); std::cin.tie(nullptr);`。
- 系统调用是微秒级开销：小 `write` 要合并成大块；日志用缓冲 + 批量刷盘。

```cpp
char buf[64];
int n = std::snprintf(buf, sizeof buf, "%d,%d", x, y);   // 无分配
```

## 并发性能

- **锁竞争**：临界区越小越好；把无关计算移出锁；读多写少用 `shared_mutex` 或 RCU 思路。
- **分片**：按 key 哈希到 N 个独立锁/计数器，冲突概率降为 1/N（`std::atomic` 数组也可）。
- **线程数**：CPU 密集型用 `std::thread::hardware_concurrency()` 量级；IO 密集型可以更多。
- **NUMA**：跨 socket 访问远端内存延迟明显更高；`numactl --cpunodebind=0 --membind=0` 绑定，或让线程只碰本地节点数据。
- **无锁**不是银弹：CAS 循环在高竞争下会退化，正确性也更难保证。

```cpp
std::atomic<long> counter{0};
counter.fetch_add(1, std::memory_order_relaxed);   // 只计数，无需顺序保证
```

## 编译优化

| 选项 | 效果 | 风险 |
| --- | --- | --- |
| `-O2` | 生产默认，稳健 | 无 |
| `-O3` | 更激进的向量化/内联 | 代码膨胀、i-cache 压力 |
| `-march=native` | 用本机指令集（AVX2/AVX-512） | 二进制不可移植 |
| `-flto` | 跨 TU 内联、去虚化 | 链接慢、内存高 |
| PGO | 按真实分支概率布局代码 | 需要采集流程（两阶段构建） |
| `__builtin_expect` | 提示分支方向 | C++17 无 `[[likely]]`，只能用它 |

```bash
# PGO：先插桩跑典型负载，再用 profile 编译
g++ -O2 -fprofile-generate -o app_pgo app.cpp && ./app_pgo workload
g++ -O2 -fprofile-use -o app app.cpp
```

**SIMD**：`-O3 -march=native -fopt-info-vec-optimized` 可确认循环是否被向量化；条件是对齐、无跨迭代依赖、无函数调用。需要精确控制时用 intrinsics：

```cpp
#include <immintrin.h>
__m256 a = _mm256_loadu_ps(x);          // 8 个 float
__m256 b = _mm256_loadu_ps(y);
_mm256_storeu_ps(z, _mm256_add_ps(a, b));
```

`restrict`（GCC/Clang 写作 `__restrict`）告诉编译器指针不重叠，是向量化的常见前提；标准 C++ 没有该关键字。

## 未定义行为与优化

优化器**假设 UB 不会发生**。一旦代码有 UB，`-O2` 下的行为可能和 `-O0` 完全不同，且没有任何警告。

| UB | 典型"优化"后果 |
| --- | --- |
| 有符号整数溢出 | `if (x + 1 < x)` 被判定恒假，整个分支被删 |
| 越界访问 | 循环被假设不会越界，检查被消除 |
| 空指针解引用 | 编译器可假定指针非空，`if (!p) return;` 被删 |
| 严格别名违规 | 通过 `int*` 改写 `float` 对象，读写被重排或缓存 |

```cpp
// 错误：strict aliasing 违规
float f = 1.0f;
int bits = *(int*)&f;                    // UB
// 正确
int bits; std::memcpy(&bits, &f, sizeof f);
```

!!! danger "排查 UB 的姿势"
    用 `-fsanitize=undefined,address` 跑测试；不要把"`-O0` 能跑"当作正确性证据。
    有符号溢出若确属预期语义，显式用 `-fwrapv` 或改无符号/`std::int64_t` 计算。

## 内存问题排查

```bash
# 编译期插桩：ASan（越界/悬垂/UAF）、UBSan（UB）、TSan（数据竞争）、MSan（未初始化，仅 Clang）
g++ -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer app.cpp -o app_asan
g++ -g -O1 -fsanitize=thread app.cpp -o app_tsan

# Valgrind：无需重编译，但慢 20–50 倍
valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes ./app
```

| 问题 | 手段 |
| --- | --- |
| 内存泄漏 | ASan（`detect_leaks=1`，Linux 默认开）、Valgrind、heaptrack |
| 越界 / UAF | ASan，报错附带分配与释放栈 |
| 数据竞争 | TSan（注意与 ASan 互斥）、`perf c2c` 辅助 |
| 未初始化读 | MSan / Valgrind `--track-origins` |
| 栈溢出 | `ulimit -s`、深递归改迭代、大局部数组改堆/`static` |
| OOM | `dmesg \| grep -i oom`、`/proc/<pid>/status` 的 `VmRSS`、cgroup 限额 |

线上崩溃定位：

```bash
gdb ./app core -ex 'bt full' -ex 'thread apply all bt' -ex quit
addr2line -e app -f -C 0x401136        # 无符号表时反查
cat /proc/<pid>/maps                   # 进程地址空间布局
strace -f -T -e trace=openat,read,write ./app   # 系统调用与耗时
```

!!! note "Release 也要留调试信息"
    `-O2 -g` 同时开是标准做法；发布时 `objcopy --only-keep-debug` 分离 `.debug`，崩溃时用同版本二进制 + 符号文件还原栈。

## 常见陷阱清单

| 陷阱 | 症状 | 修法 |
| --- | --- | --- |
| 热循环里 `std::string` 拼接 | 分配器热点 | `reserve` / `string_view` |
| `vector` 未 `reserve` | 多次扩容搬移 | 预留容量 |
| 循环内 `map::find` + 拷贝 | 无谓拷贝 | `const auto&` / `find` 返回迭代器 |
| 按值传递大对象 | 隐藏拷贝 | `const T&` |
| 频繁 `new` 小对象 | `malloc` 热点 | 池 / arena / `pmr` |
| 多线程共享计数器 | false sharing | `alignas(64)` + 每线程累加 |
| `unordered_map` 反复 rehash | 偶发长尾延迟 | `reserve` + 调 load factor |

???+ question "面试追问：`inline` 一定更快吗？"
    不一定。`inline` 只是**建议**，现代编译器按成本模型自行决定；强制内联会导致代码膨胀、i-cache 失效，反而更慢。
    它真正的语义是"允许在多个 TU 中定义"，与性能无必然关系。

???+ question "面试追问：虚函数比普通函数慢多少？"
    多一次间接跳转（读 vptr → 读 vtable → 取函数地址），约 1–5 ns；真正的代价是**分支预测失败**与**无法内联**。
    热点里可用模板/`std::variant`+`visit`/函数指针替代；非热点不必在意。

???+ question "面试追问：为什么 `vector` 比 `list` 遍历快？"
    连续内存 + 预取友好 + 每元素只需 4 字节（无指针开销）；`list` 每节点一次随机访存，几乎必然 cache miss。
    即使 `list` 插入是 O(1)，遍历时也常慢 5–10 倍。

???+ question "面试追问：如何定位内存泄漏？"
    先确认是真泄漏（RSS 持续上涨且不回落，而非分配器缓存）；再用 ASan/Valgrind 拿到**分配栈**；
    生产环境用 heaptrack 或定期抓 `/proc/<pid>/status` + `pmap` 对比。最后检查循环引用（`shared_ptr` 互指）与未释放的 C 资源。

???+ question "面试追问：什么叫 cache 友好？"
    让访问落在**连续地址、可预测顺序、同一 cache line 内**：数组代替链表、行优先遍历、SoA、把热字段聚在一起、避免指针追逐。
    衡量指标是 `perf stat` 的 cache-misses 与 IPC，而不是代码行数。

!!! tip "下一步"
    底层细节看 [内存模型](memory.md)，并发见 [并发编程](concurrency.md)，构建参数见 [编译与链接](build.md)。

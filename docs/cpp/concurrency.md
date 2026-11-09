---
title: 多线程与并发编程
tags:
  - C++
  - 并发
  - 多线程
  - 内存序
---

# 多线程与并发编程

并发题在面试里区分度很高：背得出 `std::thread` 和 `mutex` 只是入门，能讲清**内存序、条件变量的谓词、线程池的停止语义**才算过关。这一章按「怎么用 → 底层原语 → 什么情况下出错」组织，代码默认 C++17，C++20 特性单独标注。

!!! tip "先建立心智模型"
    并发 bug 的根源只有三个：**共享可变状态**、**执行顺序不确定**、**编译器/CPU 重排**。锁解决第一个，条件变量解决第二个，内存序解决第三个。分析任何并发代码时，先问：哪些数据被共享？谁保证顺序？谁保证可见性？

## 并发、并行与内存模型

- **并发（concurrency）**：多个任务在时间上重叠，单核分时也算。
- **并行（parallelism）**：多个任务在同一时刻真正同时执行，需要多核。
- **进程**：独立地址空间，隔离强，通信靠 IPC；**线程**：共享地址空间，切换轻，但数据竞争风险高。

C++ 内存模型一句话：**多线程下每个线程有本地视图，原子操作和同步原语建立 happens-before 关系，才保证一个线程的写对另一个线程可见**。没有同步的共享读写就是数据竞争，属于未定义行为（UB），不是「读到旧值」这么温和。

## std::thread 基础

`std::thread t(f, args...)` 创建线程：参数默认按值拷贝，需要引用时用 `std::ref`/`std::cref`；`join()` 等待结束，`detach()` 分离。`std::thread::hardware_concurrency()` 给出建议线程数，`get_id()` 取线程 id。注意 lambda 捕获引用时必须保证被引用对象的生命周期覆盖线程执行期。

!!! danger "thread 析构时仍 joinable 会 std::terminate"
    `std::thread` 析构函数不会自动 join 或 detach。必须显式选择其一，否则程序直接终止。RAII 封装（析构时 join）是工程里的常见做法。

### jthread 与 stop_token（C++20）

`std::jthread` 析构时自动 `join`，并内置协作式停止机制：线程函数可接收 `std::stop_token`，外部调用 `request_stop()`，线程用 `stop_requested()` 轮询退出。

```cpp
std::jthread worker([](std::stop_token st) {
    while (!st.stop_requested()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
}); // 析构时 request_stop() + join()
```

## 数据竞争与互斥量

**数据竞争**：两个线程并发访问同一内存位置，至少一个写，且没有同步。**竞态条件**：结果依赖调度顺序，即使每次访问都加锁也可能存在（如「先检查再操作」的复合逻辑）。

```cpp
int counter = 0;                       // 共享
void bad_inc() { ++counter; }          // 非原子：读-改-写三步，结果丢失

std::mutex m;
void good_inc() {
    std::lock_guard<std::mutex> lk(m);
    ++counter;
}
```

| 互斥量 | 特点 | 适用场景 |
| --- | --- | --- |
| `std::mutex` | 最普通，不可重入 | 绝大多数临界区 |
| `std::recursive_mutex` | 同线程可重复加锁 | 递归函数/回调重入，慎用 |
| `std::timed_mutex` | 支持 `try_lock_for` | 需要超时避免长时间阻塞 |
| `std::shared_mutex` | 读写锁，多读单写 | 读多写少（C++17） |

### 三种锁管理器

```cpp
std::mutex m1, m2;
void f() { std::lock_guard<std::mutex> lk(m1); } // 构造加锁，析构解锁
void g() {
    std::unique_lock<std::mutex> lk(m1, std::defer_lock); // 延迟加锁
    lk.lock(); /* ... */ lk.unlock();                     // 可手动控制
}
void h() { std::scoped_lock lk(m1, m2); } // C++17：一次锁多个，内部避免死锁
```

`std::scoped_lock` 使用死锁避免算法（类似 `std::lock`），是同时锁多个互斥量的首选。锁的粒度要「够小但覆盖完整复合操作」：把 I/O、内存分配移出临界区，但不要把「检查 + 修改」拆成两把锁。

## 死锁

死锁的四个必要条件：**互斥、占有且等待、不可抢占、循环等待**。C++ 里最常见的形态是两个线程以相反顺序加锁：线程 A 先 `m1` 后 `m2`，线程 B 先 `m2` 后 `m1`，形成循环等待。

避免策略：

1. **固定加锁顺序**：给 mutex 编号，永远按地址或 id 升序加锁。
2. **一次性加锁**：`std::scoped_lock(m1, m2)` 或 `std::lock`。
3. **超时退避**：`timed_mutex::try_lock_for`，失败就释放已持有的锁重试。
4. **层次锁、减少锁数量**：给锁分层，只允许低层向高层加锁（`std::hierarchical_mutex` 思路）；或用消息传递、无锁结构、单线程串行化替代共享状态。

!!! warning "死锁不只有互斥量"
    线程 join 自己、条件变量等待一个永远不会通知的条件、线程池任务互相等待对方的结果，都会造成「逻辑死锁」。排查时先看线程栈，再看锁的持有关系。

## 条件变量

条件变量解决「等待某个条件成立」，必须与 mutex 配合：**判断条件与进入等待必须是原子的**，否则会丢失唤醒。

```cpp
std::mutex m;
std::condition_variable cv;
std::queue<int> q;
bool done = false;

void consume() {
    std::unique_lock<std::mutex> lk(m);
    cv.wait(lk, [] { return !q.empty() || done; }); // 谓词版本，内部循环
    if (!q.empty()) { q.pop(); }
}
void produce(int v) {
    { std::lock_guard<std::mutex> lk(m); q.push(v); }
    cv.notify_one();
}
```

为什么必须用谓词循环？虚假唤醒（标准允许 `wait` 无通知返回）、惊群（醒来后条件又被其他线程改变）、丢失唤醒（通知发生在 `wait` 之前）。`notify_one` 唤醒一个等待者，`notify_all` 唤醒全部（关闭标志、广播状态变化时用）。通知可以在解锁后做，减少「被唤醒后立刻阻塞在锁上」的抖动。

???+ question "面试追问：条件变量为什么要配合互斥量？"
    因为「检查谓词」和「进入等待」必须是不可分割的原子操作。互斥量保证检查时没有其他线程修改条件；`wait` 内部会原子地释放锁并睡眠，被唤醒后重新加锁再返回。若不用锁，通知可能恰好发生在检查之后、睡眠之前，造成丢失唤醒。

## future、promise 与 async

```cpp
auto f = std::async(std::launch::async, [] { return 42; });
int v = f.get();                       // 阻塞取结果，只能 get 一次

std::promise<int> p;                   // 手动设置结果或异常
auto fut = p.get_future();
std::thread([&p] { p.set_value(7); }).join();
fut.get();

std::packaged_task<int(int)> task([](int x) { return x * 2; });
auto r = task.get_future();            // 把 task 交给线程池执行
```

要点：

- `std::async` 不指定策略时允许延迟执行，**返回的 future 析构会阻塞等待**（若任务是 `async` 策略），容易造成意外串行。
- 异常会通过 future 传播，`get()` 时重新抛出；`std::future` 不可拷贝只能移动，`shared_future` 可多线程 `get`。

## atomic 与 CAS

`std::atomic<T>` 提供原子读改写，避免数据竞争。常用特化有 `atomic<bool>`、`atomic<int>`、`atomic<size_t>`、`atomic<T*>`，C++20 增加 `atomic<float>`、`atomic<shared_ptr<T>>` 和 `atomic_ref`。

```cpp
std::atomic<int> counter{0};
counter.fetch_add(1, std::memory_order_relaxed);
int old = counter.exchange(10);  // 原子交换
int expected = counter.load();   // CAS：失败时 expected 更新为当前值
while (!counter.compare_exchange_weak(expected, expected + 1)) { }
```

`compare_exchange_weak` 允许伪失败（spurious failure），在循环里更高效；`compare_exchange_strong` 不会伪失败，适合单次判断。CAS 循环是无锁结构的基础，但要警惕 **ABA 问题**：值从 A 变 B 又变回 A，CAS 察觉不到中间变化，通常用版本号/标记指针解决。`atomic_flag` 是标准保证 lock-free 的类型，用 `test_and_set(acquire)`/`clear(release)` 即可实现自旋锁；`is_lock_free()` 判断其他 `atomic<T>` 是否由硬件指令实现，大于机器字长的类型可能内部加锁。

## 内存序

先记住两条关系：**sequenced-before** 是同一线程内的语句顺序；**happens-before** 跨线程，由同步操作建立。若 A happens-before B，则 A 的写在 B 看来可见。

| 内存序 | 语义 | 典型用途 |
| --- | --- | --- |
| `relaxed` | 只保证原子性，不保证顺序 | 计数器、统计 |
| `acquire` | 读操作，之后的读写不能重排到它之前 | 消费者加载标志 |
| `release` | 写操作，之前的读写不能重排到它之后 | 生产者发布数据 |
| `acq_rel` | 同时具备 acquire/release | RMW 操作 |
| `seq_cst` | 全局单一顺序，默认 | 不确定时的安全选择 |

```cpp
std::atomic<bool> ready{false};
int payload = 0;

// 生产者
payload = 42;                                      // (1)
ready.store(true, std::memory_order_release);      // (2) 保证 (1) 不会排到 (2) 之后

// 消费者
while (!ready.load(std::memory_order_acquire)) { } // (3) 保证之后的读不会排到 (3) 之前
assert(payload == 42);                             // 一定成立
```

`release` 与 `acquire` 必须**配对**才建立 happens-before。`relaxed` 只适合「不需要与其他内存建立顺序」的计数；一旦有「先准备数据，再发布标志」的模式，就必须用 release/acquire 或 seq_cst。

!!! danger "volatile 不能替代 atomic"
    `volatile` 只阻止编译器优化掉访问，不提供原子性，也不建立跨线程的 happens-before，更不会插入 CPU 内存屏障。用它做线程同步是错误的；它只适用于内存映射 I/O、信号处理等场景。

???+ question "面试追问：什么时候可以把 seq_cst 放松？"
    当你能证明不存在跨变量的顺序依赖时。例如纯统计计数器用 `relaxed`；「初始化数据 → 置 ready 标志」用 release/acquire；只有需要所有线程看到同一全局顺序（如 Dekker 算法、多生产者多消费者队列的某些实现）才必须 `seq_cst`。放松的前提是你能画出 happens-before 图，否则默认 seq_cst。

## thread_local、call_once 与 once_flag

```cpp
thread_local int tls_counter = 0;   // 每个线程独立实例，常用于缓存、错误码

std::once_flag flag;
void init() {
    std::call_once(flag, [] { /* 只执行一次，且线程安全 */ });
}
```

`thread_local` 的初始化在首次使用该线程时进行，销毁在线程退出时；它不解决共享问题，只是「每线程一份」。`call_once` 比双检锁更安全，是单例初始化的标准工具；需要配合非 `std::mutex` 的锁类型时用 `std::condition_variable_any`，代价是内部多一层锁。

## 线程池完整实现

线程池 = 任务队列 + 固定工作线程 + 条件变量 + 停止标志。下面是一个可直接编译的 C++17 版本：

```cpp
#include <condition_variable>
#include <functional>
#include <future>
#include <mutex>
#include <queue>
#include <stdexcept>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

class ThreadPool {
public:
    explicit ThreadPool(std::size_t n = std::thread::hardware_concurrency()) {
        if (n == 0) n = 1;
        for (std::size_t i = 0; i < n; ++i)
            workers_.emplace_back([this] { worker_loop(); });
    }
    ~ThreadPool() { shutdown(); }
    ThreadPool(const ThreadPool&) = delete;
    ThreadPool& operator=(const ThreadPool&) = delete;
    template <typename F, typename... Args>
    auto submit(F&& f, Args&&... args)
        -> std::future<std::invoke_result_t<F, Args...>> {
        using R = std::invoke_result_t<F, Args...>;
        auto task = std::make_shared<std::packaged_task<R()>>(
            std::bind(std::forward<F>(f), std::forward<Args>(args)...));
        std::future<R> fut = task->get_future();
        {
            std::lock_guard<std::mutex> lk(mutex_);
            if (stop_) throw std::runtime_error("submit on stopped pool");
            tasks_.emplace([task] { (*task)(); });
        }
        cv_.notify_one();
        return fut;
    }
    void shutdown() {
        {
            std::lock_guard<std::mutex> lk(mutex_);
            if (stop_) return;
            stop_ = true;
        }
        cv_.notify_all();
        for (auto& t : workers_) if (t.joinable()) t.join();
    }
private:
    void worker_loop() {
        for (;;) {
            std::function<void()> job;
            {
                std::unique_lock<std::mutex> lk(mutex_);
                cv_.wait(lk, [this] { return stop_ || !tasks_.empty(); });
                if (stop_ && tasks_.empty()) return; // 停止时先把队列排空
                job = std::move(tasks_.front());
                tasks_.pop();
            }
            job(); // 在锁外执行，避免任务阻塞其他线程
        }
    }
    std::mutex mutex_;
    std::condition_variable cv_;
    std::queue<std::function<void()>> tasks_;
    std::vector<std::thread> workers_;
    bool stop_ = false;
};
```

设计要点：

- 任务用 `std::function<void()>` 擦除类型，返回值通过 `packaged_task` 的 future 带走；`submit` 在锁内检查停止标志，避免向已停止的池投递任务。
- worker 取任务后**释放锁再执行**，否则任务内部再提交任务会死锁。
- `shutdown` 先置标志、通知全部，再 join；析构函数保证线程不泄漏。
- 真实工程还要考虑：有界队列、任务优先级、动态扩缩容、异常处理。

## 有界队列与生产者-消费者

```cpp
template <typename T>
class BoundedQueue {
public:
    explicit BoundedQueue(std::size_t cap) : cap_(cap) {}
    void push(T v) {
        std::unique_lock<std::mutex> lk(m_);
        not_full_.wait(lk, [this] { return q_.size() < cap_ || closed_; });
        if (closed_) return;
        q_.push(std::move(v));
        not_empty_.notify_one();
    }
    bool pop(T& out) {
        std::unique_lock<std::mutex> lk(m_);
        not_empty_.wait(lk, [this] { return !q_.empty() || closed_; });
        if (q_.empty()) return false;   // 已关闭且排空
        out = std::move(q_.front());
        q_.pop();
        not_full_.notify_one();
        return true;
    }
    void close() {
        { std::lock_guard<std::mutex> lk(m_); closed_ = true; }
        not_empty_.notify_all();
        not_full_.notify_all();
    }
private:
    std::mutex m_;
    std::condition_variable not_empty_, not_full_;
    std::queue<T> q_;
    std::size_t cap_;
    bool closed_ = false;
};
```

注意两个条件变量分别对应「非空」和「未满」，通知时只唤醒对应方向的等待者；`close` 必须 `notify_all`，否则等待线程可能永远不醒。

## 读写锁与单例

`std::shared_mutex`（C++17）适合读多写少：多个读者共享，写者独占。

```cpp
std::shared_mutex rw;
int config = 0;
int read_config() {
    std::shared_lock<std::shared_mutex> lk(rw);
    return config;
}
void write_config(int v) {
    std::unique_lock<std::shared_mutex> lk(rw);
    config = v;
}
```

C++11 起局部静态变量初始化线程安全（magic statics），这是最简洁的单例：

```cpp
class Singleton {
public:
    static Singleton& instance() { static Singleton inst; return inst; }
    Singleton(const Singleton&) = delete;
    Singleton& operator=(const Singleton&) = delete;
private:
    Singleton() = default;
};
```

初始化需要参数或可能失败时用 `std::call_once`；不要写「双检锁 + 普通指针」。

## 无锁编程与性能陷阱

无锁不等于无等待：CAS 循环在竞争激烈时会大量重试，甚至比 mutex 更慢。无锁栈的 push 就是「读头 → 新节点 next 指向旧头 → CAS 更新头」，pop 还要处理 ABA，通常配 `std::shared_ptr` 的原子操作或 hazard pointer。

**false sharing**：两个线程分别写同一 cache line 上的不同变量，缓存一致性协议导致 line 在两核间反复失效。

```cpp
struct alignas(64) PaddedCounter {   // 64 字节通常等于一个 cache line
    std::atomic<long> value{0};
};

PaddedCounter a, b;   // 两个线程各写一个，不再互相拖慢
```
其他性能陷阱：临界区内做 I/O 或分配内存；锁竞争导致线程频繁上下文切换；过度使用 `notify_all` 造成惊群；伪共享的原子计数器。

## 调试并发问题

- **ThreadSanitizer**：`g++ -fsanitize=thread -g -O1 t.cpp -o t`，运行后报告数据竞争及两个访问的栈。
- **gdb**：`info threads` 看线程，`thread apply all bt` 看所有栈，死锁时检查谁持有锁、谁在等锁。
- **Helgrind / DRD**：Valgrind 工具，适合不能重编译的场景；日志记录线程 id、时间戳、锁的获取顺序，靠「复现 + 缩小临界区」定位。

!!! tip "复现优先"
    并发 bug 不要靠盯着代码猜。先用 TSan 跑一遍，再写压力测试（多线程循环 + 随机延迟）提高复现概率；定位到具体变量后，再画 happens-before 图确认同步是否缺失。

## 面试追问

???+ question "面试追问：mutex 底层是怎么实现的？"
    用户态先尝试原子 CAS 抢锁（fast path），失败则进入内核通过 futex 睡眠（slow path），避免忙等浪费 CPU。解锁时若无等待者直接返回；有等待者则 `futex_wake` 唤醒。具体实现依赖平台，Linux 上 glibc 的 pthread mutex 就是 futex + 原子操作。

???+ question "面试追问：自旋锁和互斥锁怎么选？"
    自旋锁不睡眠、忙等，适合临界区极短且线程数不超过核数的场景；互斥锁在竞争时让出 CPU，适合临界区较长或可能阻塞的场景。单核上自旋锁几乎总是错的（自旋的线程占着 CPU，持有者无法运行）。

???+ question "面试追问：atomic 一定是无锁的吗？"
    不一定。`is_lock_free()` 才能确定；对大于机器字长的类型，标准允许用内部锁实现。`atomic_flag` 保证无锁。判断「无锁」要看硬件指令支持，而不是看类型名。

???+ question "面试追问：内存序在实际项目中怎么用？"
    最常见的模式是「release 发布、acquire 消费」：初始化数据后用 `store(release)` 置 ready，读者 `load(acquire)` 后访问数据。纯计数用 `relaxed`。只有在需要所有原子操作呈现单一全局顺序时才用 `seq_cst`；放松内存序必须能证明不存在需要跨线程可见的顺序依赖。

???+ question "面试追问：条件变量为什么会虚假唤醒？"
    底层实现（如 futex）在信号中断、超时、多核竞争等情况下可能返回而未被 notify；标准因此允许 spurious wakeup。正确写法是始终用谓词版本的 `wait(lk, pred)`，它在内部循环检查谓词，虚假唤醒会被自动过滤。

## 小结

并发编程的难点不在 API，而在**证明正确性**：每个共享变量要么被锁保护，要么是原子类型，要么只读；每个等待都有谓词和唤醒路径；每个线程都有明确的 join/detach 归属。写线程池时把停止语义、异常传播、锁外执行这三件事处理干净，就已经超过大多数面试答案。

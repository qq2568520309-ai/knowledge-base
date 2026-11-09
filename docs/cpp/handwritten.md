---
title: 手撕代码题库
tags:
  - C++
  - 面试
  - 手撕
---

# C++ 手撕代码题库

12 道高频手撕题：考点、可编译的完整实现、复杂度与追问。代码统一 C++17，
单文件即可编译：`g++ -std=c++17 -O2 -Wall -pthread xxx.cpp`。建议先手写再对照。

## 1. 手写 strcpy / strncpy

**考点**：判空、返回值支持链式、结尾 `'\0'` 的复制；`strncpy` 不保证终止，必须补零。

```cpp
#include <cassert>
#include <cstddef>

char* my_strcpy(char* d, const char* s) {
    assert(d && s);
    char* r = d;
    while ((*d++ = *s++) != '\0') { }
    return r;
}
char* my_strncpy(char* d, const char* s, std::size_t n) {
    assert(d && s);
    char* r = d;
    std::size_t i = 0;
    for (; i < n && s[i]; ++i) d[i] = s[i];
    for (; i < n; ++i) d[i] = '\0';
    return r;
}
```

**复杂度** O(n) / O(1)。**追问**：dst 与 src 重叠时？`strcpy` 未定义，重叠必须用 `memmove`。

## 2. 手写 memcpy / memmove

**考点**：按字节拷贝、`void*` 转 `unsigned char*`、重叠时按方向选择。

```cpp
#include <cstddef>

void* my_memcpy(void* dst, const void* src, std::size_t n) {
    auto* d = static_cast<unsigned char*>(dst);
    const auto* s = static_cast<const unsigned char*>(src);
    while (n--) *d++ = *s++;          // 重叠时结果未定义
    return dst;
}
void* my_memmove(void* dst, const void* src, std::size_t n) {
    auto* d = static_cast<unsigned char*>(dst);
    const auto* s = static_cast<const unsigned char*>(src);
    if (d == s || n == 0) return dst;
    if (d < s) { while (n--) *d++ = *s++; }
    else { d += n; s += n; while (n--) *--d = *--s; }
    return dst;
}
```

**复杂度** O(n) / O(1)。**追问**：`d < s` 比较不同对象在标准里未定义，工程上转 `uintptr_t` 比较。

## 3. 手写 String 类

**考点**：三/五法则、深拷贝、移动后置空、copy-and-swap、自赋值。

```cpp
#include <cstring>
#include <cstddef>
#include <utility>

class String {
public:
    String() : size_(0), data_(new char[1]{'\0'}) {}
    String(const char* s) : size_(s ? std::strlen(s) : 0), data_(new char[size_ + 1]) {
        std::memcpy(data_, s ? s : "", size_);
        data_[size_] = '\0';
    }
    String(const String& o) : size_(o.size_), data_(new char[o.size_ + 1]) {
        std::memcpy(data_, o.data_, size_ + 1);
    }
    String(String&& o) noexcept : size_(o.size_), data_(o.data_) {
        o.size_ = 0;
        o.data_ = new char[1]{'\0'};
    }
    String& operator=(String o) noexcept { swap(o); return *this; }   // 拷贝/移动共用
    ~String() { delete[] data_; }
    void swap(String& o) noexcept { std::swap(size_, o.size_); std::swap(data_, o.data_); }
    String& operator+=(const String& o) {
        char* buf = new char[size_ + o.size_ + 1];
        std::memcpy(buf, data_, size_);
        std::memcpy(buf + size_, o.data_, o.size_ + 1);
        delete[] data_;
        data_ = buf;
        size_ += o.size_;
        return *this;
    }
    friend String operator+(String a, const String& b) { a += b; return a; }
    const char* c_str() const noexcept { return data_; }
    std::size_t size() const noexcept { return size_; }
private:
    std::size_t size_;
    char* data_;
};
```

**复杂度** 拼接 O(n+m)，其余 O(1)/O(n)。**追问**：按值传参为什么能同时吃掉拷贝和移动？——由实参值类别决定调用哪个构造。

## 4. 手写简化 shared_ptr

**考点**：控制块、原子引用计数、拷贝/移动、`reset`、自定义删除器。

```cpp
#include <atomic>
#include <cstddef>
#include <utility>

template <typename T>
class SharedPtr {
public:
    SharedPtr() noexcept = default;
    explicit SharedPtr(T* p) : ptr_(p), ctrl_(p ? new Control{1, nullptr} : nullptr) {}
    SharedPtr(T* p, void (*del)(T*)) : ptr_(p), ctrl_(p ? new Control{1, del} : nullptr) {}
    SharedPtr(const SharedPtr& o) noexcept : ptr_(o.ptr_), ctrl_(o.ctrl_) {
        if (ctrl_) ctrl_->strong.fetch_add(1, std::memory_order_relaxed);
    }
    SharedPtr(SharedPtr&& o) noexcept : ptr_(o.ptr_), ctrl_(o.ctrl_) { o.ptr_ = nullptr; o.ctrl_ = nullptr; }
    SharedPtr& operator=(SharedPtr o) noexcept { swap(o); return *this; }
    ~SharedPtr() { release(); }
    void swap(SharedPtr& o) noexcept { std::swap(ptr_, o.ptr_); std::swap(ctrl_, o.ctrl_); }
    void reset(T* p = nullptr) {
        auto del = ctrl_ ? ctrl_->deleter : nullptr;
        SharedPtr(p, del).swap(*this);
    }
    T* get() const noexcept { return ptr_; }
    T& operator*() const noexcept { return *ptr_; }
    T* operator->() const noexcept { return ptr_; }
    explicit operator bool() const noexcept { return ptr_ != nullptr; }
    long use_count() const noexcept { return ctrl_ ? ctrl_->strong.load() : 0; }
private:
    struct Control {
        std::atomic<long> strong;
        void (*deleter)(T*);
    };
    void release() noexcept {
        if (ctrl_ && ctrl_->strong.fetch_sub(1, std::memory_order_acq_rel) == 1) {
            if (ctrl_->deleter) ctrl_->deleter(ptr_);
            else delete ptr_;
            delete ctrl_;
        }
        ptr_ = nullptr;
        ctrl_ = nullptr;
    }
    T* ptr_ = nullptr;
    Control* ctrl_ = nullptr;
};
```

**复杂度** 拷贝/析构 O(1)。**追问**：`make_shared` 的优化怎么加？——对象与控制块同块内存，一次分配，但 `weak_ptr` 存活时内存不释放。

## 5. 手写简化 vector

**考点**：三指针、扩容、placement new / 显式析构、`move_if_noexcept`、强异常安全。

```cpp
#include <cstddef>
#include <new>
#include <utility>

template <typename T>
class Vector {
public:
    Vector() = default;
    Vector(const Vector& o) { reserve(o.size_); for (std::size_t i = 0; i < o.size_; ++i) emplace_back(o.data_[i]); }
    Vector(Vector&& o) noexcept : data_(o.data_), size_(o.size_), cap_(o.cap_) { o.data_ = nullptr; o.size_ = o.cap_ = 0; }
    Vector& operator=(Vector o) noexcept { swap(o); return *this; }
    ~Vector() { clear(); ::operator delete(data_); }
    void swap(Vector& o) noexcept { std::swap(data_, o.data_); std::swap(size_, o.size_); std::swap(cap_, o.cap_); }
    void reserve(std::size_t n) {
        if (n <= cap_) return;
        T* buf = static_cast<T*>(::operator new(n * sizeof(T)));
        for (std::size_t i = 0; i < size_; ++i) {
            new (buf + i) T(std::move_if_noexcept(data_[i]));
            data_[i].~T();
        }
        ::operator delete(data_);
        data_ = buf;
        cap_ = n;
    }
    template <typename... Args>
    T& emplace_back(Args&&... args) {
        if (size_ == cap_) reserve(cap_ ? cap_ * 2 : 1);
        T* p = new (data_ + size_) T(std::forward<Args>(args)...);
        ++size_;
        return *p;
    }
    void push_back(const T& v) { emplace_back(v); }
    void push_back(T&& v) { emplace_back(std::move(v)); }
    void pop_back() { data_[--size_].~T(); }
    void clear() noexcept { while (size_) data_[--size_].~T(); }
    T& operator[](std::size_t i) { return data_[i]; }
    const T& operator[](std::size_t i) const { return data_[i]; }
    std::size_t size() const noexcept { return size_; }
    std::size_t capacity() const noexcept { return cap_; }
private:
    T* data_ = nullptr;
    std::size_t size_ = 0;
    std::size_t cap_ = 0;
};
```

**复杂度** `push_back` 均摊 O(1)、扩容 O(n)。**追问**：为什么用 `move_if_noexcept`？——移动可能抛时退回拷贝，保住强异常安全。

## 6. 手写单例的四种写法

**考点**：线程安全、懒加载、双检锁的内存序、静态析构顺序。

```cpp
#include <atomic>
#include <memory>
#include <mutex>

// ① 饿汉：main 之前构造，天然线程安全
class Eager {
public:
    static Eager& instance() { return inst_; }
private:
    Eager() = default;
    static Eager inst_;
};
Eager Eager::inst_;

// ② 懒汉 + 双检锁
class Lazy {
public:
    static Lazy& instance() {
        Lazy* p = inst_.load(std::memory_order_acquire);
        if (!p) {
            std::lock_guard<std::mutex> lk(mtx_);
            p = inst_.load(std::memory_order_relaxed);
            if (!p) { p = new Lazy(); inst_.store(p, std::memory_order_release); }
        }
        return *p;
    }
private:
    Lazy() = default;
    static std::atomic<Lazy*> inst_;
    static std::mutex mtx_;
};
std::atomic<Lazy*> Lazy::inst_{nullptr};
std::mutex Lazy::mtx_;

// ③ 局部静态：C++11 起初始化线程安全，首选
class Meyers {
public:
    static Meyers& instance() { static Meyers inst; return inst; }
private:
    Meyers() = default;
};

// ④ call_once：兼容旧编译器
class Once {
public:
    static Once& instance() {
        std::call_once(flag_, [] { inst_.reset(new Once()); });
        return *inst_;
    }
private:
    Once() = default;
    static std::once_flag flag_;
    static std::unique_ptr<Once> inst_;
};
std::once_flag Once::flag_;
std::unique_ptr<Once> Once::inst_;
```

**复杂度** 首次 O(1) + 一次加锁。**追问**：怎么安全销毁？——Meyers 版随静态析构自动销毁，但要小心跨 TU 的析构顺序。

## 7. 手写线程池

**考点**：任务队列、条件变量、`packaged_task` 传递返回值与异常、优雅关闭。

```cpp
#include <condition_variable>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <queue>
#include <stdexcept>
#include <thread>
#include <type_traits>
#include <vector>

class ThreadPool {
public:
    explicit ThreadPool(std::size_t n = std::thread::hardware_concurrency()) {
        if (n == 0) n = 1;
        for (std::size_t i = 0; i < n; ++i) workers_.emplace_back([this] { loop(); });
    }
    ~ThreadPool() { shutdown(); }
    ThreadPool(const ThreadPool&) = delete;
    ThreadPool& operator=(const ThreadPool&) = delete;

    template <typename F, typename... Args>
    auto submit(F&& f, Args&&... args) -> std::future<std::invoke_result_t<F, Args...>> {
        using R = std::invoke_result_t<F, Args...>;
        auto task = std::make_shared<std::packaged_task<R()>>(std::bind(std::forward<F>(f), std::forward<Args>(args)...));
        auto fut = task->get_future();
        {
            std::lock_guard<std::mutex> lk(mtx_);
            if (stop_) throw std::runtime_error("pool stopped");
            tasks_.emplace([task] { (*task)(); });
        }
        cv_.notify_one();
        return fut;
    }
private:
    void loop() {
        for (;;) {
            std::function<void()> job;
            {
                std::unique_lock<std::mutex> lk(mtx_);
                cv_.wait(lk, [this] { return stop_ || !tasks_.empty(); });
                if (stop_ && tasks_.empty()) return;
                job = std::move(tasks_.front());
                tasks_.pop();
            }
            job();                      // packaged_task 会把异常存进 future
        }
    }
    void shutdown() {
        { std::lock_guard<std::mutex> lk(mtx_); stop_ = true; }
        cv_.notify_all();
        for (auto& t : workers_) if (t.joinable()) t.join();
        workers_.clear();
    }
    std::vector<std::thread> workers_;
    std::queue<std::function<void()>> tasks_;
    std::mutex mtx_;
    std::condition_variable cv_;
    bool stop_ = false;
};
```

**复杂度** 提交 O(1)。**追问**：怎么支持优先级？——队列换成 `priority_queue`，或按优先级分多个队列调度。

## 8. 手写生产者-消费者有界队列

**考点**：两个条件变量、谓词等待、关闭时唤醒全部、`push` 返回失败而非永久阻塞。

```cpp
#include <condition_variable>
#include <cstddef>
#include <deque>
#include <mutex>
#include <utility>

template <typename T>
class BoundedQueue {
public:
    explicit BoundedQueue(std::size_t cap) : cap_(cap) {}
    bool push(T v) {
        std::unique_lock<std::mutex> lk(m_);
        not_full_.wait(lk, [this] { return closed_ || q_.size() < cap_; });
        if (closed_) return false;
        q_.push(std::move(v));
        not_empty_.notify_one();
        return true;
    }
    bool pop(T& out) {
        std::unique_lock<std::mutex> lk(m_);
        not_empty_.wait(lk, [this] { return closed_ || !q_.empty(); });
        if (q_.empty()) return false;
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
    std::size_t cap_;
    std::deque<T> q_;
    std::mutex m_;
    std::condition_variable not_empty_, not_full_;
    bool closed_ = false;
};
```

**复杂度** 单次操作 O(1)。**追问**：为什么 `close` 要两个 `notify_all`？——阻塞的生产者和消费者都要醒来检查 `closed_`。

## 9. 手写 LRU Cache

**考点**：`list` 存访问顺序、`unordered_map` 存迭代器、`splice` 实现 O(1) 提升。

```cpp
#include <cstddef>
#include <list>
#include <unordered_map>
#include <utility>

class LRUCache {
public:
    explicit LRUCache(std::size_t cap) : cap_(cap) {}
    int get(int key) {
        auto it = map_.find(key);
        if (it == map_.end()) return -1;
        items_.splice(items_.begin(), items_, it->second);   // 提到表头
        return it->second->second;
    }
    void put(int key, int value) {
        auto it = map_.find(key);
        if (it != map_.end()) {
            it->second->second = value;
            items_.splice(items_.begin(), items_, it->second);
            return;
        }
        if (map_.size() == cap_) {
            map_.erase(items_.back().first);
            items_.pop_back();
        }
        items_.emplace_front(key, value);
        map_[key] = items_.begin();
    }
private:
    std::size_t cap_;
    std::list<std::pair<int, int>> items_;    // front 是最近使用
    std::unordered_map<int, std::list<std::pair<int, int>>::iterator> map_;
};
```

**复杂度** `get/put` 均摊 O(1)、空间 O(capacity)。**追问**：并发怎么改？——整体加锁，或分段锁 + 每段独立 LRU。

## 10. 手写 RAII 锁与 scope_guard

**考点**：构造获取、析构释放、禁止拷贝、支持移动、`dismiss` 取消。

```cpp
#include <functional>
#include <utility>

template <typename Lock>
class LockGuard {
public:
    explicit LockGuard(Lock& lk) : lk_(lk) { lk_.lock(); }
    ~LockGuard() { lk_.unlock(); }
    LockGuard(const LockGuard&) = delete;
    LockGuard& operator=(const LockGuard&) = delete;
private:
    Lock& lk_;
};

class ScopeGuard {
public:
    explicit ScopeGuard(std::function<void()> f) : f_(std::move(f)) {}
    ~ScopeGuard() { if (active_) f_(); }
    ScopeGuard(const ScopeGuard&) = delete;
    ScopeGuard& operator=(const ScopeGuard&) = delete;
    ScopeGuard(ScopeGuard&& o) noexcept : f_(std::move(o.f_)), active_(o.active_) { o.active_ = false; }
    void dismiss() noexcept { active_ = false; }
private:
    std::function<void()> f_;
    bool active_ = true;
};
```

**复杂度** O(1)。**追问**：析构能抛异常吗？——不能，`noexcept` 中抛出会 `std::terminate`，清理逻辑必须自己吞异常。

## 11. 手写简单对象池

**考点**：预分配、free list、placement new 与显式析构、对齐。

```cpp
#include <cstddef>
#include <new>
#include <utility>

template <typename T, std::size_t N>
class ObjectPool {
public:
    ObjectPool() {
        for (std::size_t i = 0; i < N; ++i) free_[i] = &slots_[i];
        top_ = N;
    }
    template <typename... Args>
    T* create(Args&&... args) {
        if (top_ == 0) return nullptr;
        void* mem = free_[--top_];
        return new (mem) T(std::forward<Args>(args)...);
    }
    void destroy(T* p) {
        p->~T();
        free_[top_++] = p;
    }
    std::size_t available() const noexcept { return top_; }
private:
    alignas(T) unsigned char slots_[N][sizeof(T)];
    void* free_[N];
    std::size_t top_ = 0;
};
```

**复杂度** 创建/销毁 O(1)、空间 O(N)。**追问**：池销毁时仍存活的对象怎么办？——需自己记录并显式析构，或用 `unique_ptr` + 自定义删除器。

## 12. 手写简化 function（类型擦除）

**考点**：虚函数做类型擦除、模板构造、拷贝/移动、`operator()` 转发。

```cpp
#include <memory>
#include <type_traits>
#include <utility>

template <typename Sig> class Function;

template <typename R, typename... Args>
class Function<R(Args...)> {
    struct Base {
        virtual ~Base() = default;
        virtual R invoke(Args... args) = 0;
        virtual std::unique_ptr<Base> clone() const = 0;
    };
    template <typename F>
    struct Impl : Base {
        explicit Impl(F f) : f_(std::move(f)) {}
        R invoke(Args... args) override { return f_(std::forward<Args>(args)...); }
        std::unique_ptr<Base> clone() const override { return std::make_unique<Impl>(*this); }
        F f_;
    };
public:
    Function() = default;
    template <typename F, typename = std::enable_if_t<!std::is_same_v<std::decay_t<F>, Function>>>
    Function(F&& f) : impl_(std::make_unique<Impl<std::decay_t<F>>>(std::forward<F>(f))) {}
    Function(const Function& o) : impl_(o.impl_ ? o.impl_->clone() : nullptr) {}
    Function(Function&&) noexcept = default;
    Function& operator=(Function o) noexcept { swap(o); return *this; }
    R operator()(Args... args) const { return impl_->invoke(std::forward<Args>(args)...); }
    explicit operator bool() const noexcept { return impl_ != nullptr; }
    void swap(Function& o) noexcept { impl_.swap(o.impl_); }
private:
    std::unique_ptr<Base> impl_;
};
```

**复杂度** 调用多一次间接跳转，构造一次堆分配。**追问**：`std::function` 的小对象优化？——小可调用对象直接存内部缓冲，避免堆分配。

延伸阅读：[面试八股 · 基础篇](interview-basics.md)、[面试八股 · 进阶篇](interview-advanced.md)、[现代 C++](modern-cpp.md)。

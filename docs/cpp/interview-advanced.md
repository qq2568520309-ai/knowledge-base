---
title: 面试八股 · 进阶篇
tags:
  - C++
  - 面试
---

# C++ 面试八股 · 进阶篇

基础篇之后的深水区：对象模型、移动语义与智能指针、模板、并发、性能与工程系统，共 54 题。
这一层的题不再是「是什么」，而是「为什么这样设计、代价在哪、编译器到底生成了什么」。
配合 [内存模型](memory.md)、[模板](templates.md)、[现代 C++](modern-cpp.md)、[并发编程](concurrency.md) 阅读效果更好。

!!! tip "回答策略"
    先说结论，再补一句实现机制，最后给一个代价或边界条件。面试官追问的往往就是「代价」那一句。

## 一、对象模型与虚函数进阶

???+ question "1. 多重继承下对象布局是怎样的？this 指针为什么要调整？"
    对象按继承声明顺序依次放置各基类子对象：`class D : B1, B2` 中 B1 在偏移 0，B2 在 `sizeof(B1)` 对齐后的位置，最后是 D 自己的成员。
    因此 `D*` 转 `B2*` 不是零开销，需要加上偏移；反向转换要减偏移，编译器生成 thunk 完成 this 调整后再跳转。
    结论：多继承下不同基类指针的数值可能不同，`static_cast` 会调整，`reinterpret_cast` 不会，这就是它危险的原因之一。

???+ question "2. 虚继承在内存里是怎么实现的？"
    虚基类子对象在整个对象中只保留一份，通常放在对象末尾（Itanium ABI），具体偏移在编译期无法确定。
    实现方式是在 vtable 中存放虚基类偏移（vbase offset），或额外放一个 vbptr 指向虚基类表，访问时先取偏移再寻址。
    代价：多一次间接寻址、对象更大、构造顺序由最派生类统一负责，中间类的虚基类初始化会被忽略。

???+ question "3. 每个类的 vtable 是共享的吗？多个翻译单元里怎么保证只有一份？"
    同一个类在所有对象间共享同一张 vtable；不同类各有一张，模板的每个实例化也各有一张。
    内联函数和模板的 vtable 会在多个 TU 中生成，链接器通过 COMDAT/weak symbol 去重，只保留一份。
    跨共享库时靠符号可见性（`-fvisibility=hidden`）和动态链接器的唯一化来避免重复，否则 `type_info` 比较都可能失效。

???+ question "4. RTTI 在底层是怎么存的？dynamic_cast 怎么做检查？"
    vtable 中额外存一个指向 `std::type_info` 的指针（Itanium ABI 放在 vtable 的 -1 槽），`typeid` 对多态类型就取它。
    `dynamic_cast` 需要源类型多态，运行时调用 `__dynamic_cast`，沿继承图（含虚基类）搜索目标类型并计算偏移。
    这解释了它的两个限制：非多态类型不能 `dynamic_cast`，且开销明显大于 `static_cast`。

???+ question "5. 虚函数调用到底慢在哪？"
    一次间接调用：先读 vptr，再按偏移取函数指针，再跳转，比直接调用多两次内存访问且难以内联。
    无法内联会连带失去常量传播、死代码消除等优化；间接分支还可能分支预测失败、拖累 i-cache。
    实际影响通常很小，热点路径上可用 `final`、LTO、PGO 帮助编译器去虚化（devirtualization）。

???+ question "6. 什么是空基类优化（EBO）？"
    空类作为基类时可以不占空间，编译器保证其地址与派生类首成员不同即可，所以 `sizeof(Derived) == sizeof(int)` 很常见。
    空类作为成员仍占 1 字节（需要唯一地址）；C++20 用 `[[no_unique_address]]` 对成员做同样的优化。
    标准库大量利用 EBO：无状态分配器、比较器、删除器都不增加对象大小。

???+ question "7. 虚函数可以是 inline 的吗？"
    可以。类内定义的虚函数隐含 `inline`，编译器在「静态类型可知」的调用点（对象直接调用、`final` 类、LTO 后）能内联展开。
    通过基类指针/引用的多态调用通常无法内联，因为目标要到运行期才确定。
    所以 `inline` 与 `virtual` 不冲突，只是内联的机会变少。

???+ question "8. 构造和析构过程中 vptr 处于什么状态？"
    进入基类构造函数前 vptr 被设为基类 vtable，执行完基类构造、进入派生类构造体前再改为派生类 vtable。
    析构时反向：派生类析构体执行完后 vptr 改回基类 vtable，再执行基类析构。
    这正是「构造/析构中调用虚函数不会多态」的机制来源，也是不要在构造中把 `this` 交给外部的原因。

???+ question "9. 纯虚析构函数为什么必须提供定义？"
    纯虚析构让类成为抽象类，但派生类析构时仍会沿继承链调用基类析构，链接器需要它的函数体。
    写法：类内 `virtual ~Base() = 0;`，类外 `Base::~Base() = default;`，漏掉就是链接错误。
    常见用途：既想禁止实例化，又需要一个可被调用的析构实现。

???+ question "10. RAII 与异常安全等级怎么讲？"
    RAII 把资源生命周期绑定到对象生命周期：构造获取、析构释放，栈展开时析构函数自动执行，所以异常也安全。
    异常安全分四级：no-throw（承诺不抛）、strong（要么成功要么回滚，copy-and-swap 实现）、basic（不泄漏、对象仍有效）、none。
    工程上至少做到 basic；修改容器整体状态的操作尽量用 copy-and-swap 提供 strong。

## 二、移动语义与智能指针进阶

???+ question "11. 引用折叠规则是什么？"
    只有一种组合得到右值引用：`&& + && = &&`；其余 `& + &`、`& + &&`、`&& + &` 都折叠成左值引用。
    它出现在模板推导、`auto&&`、`decltype` 与 typedef 中，是万能引用和 `std::forward` 的实现基础。
    记法：只要有一个 `&`，结果就是左值引用。

???+ question "12. 万能引用和右值引用怎么区分？"
    形式是 `T&&` 且 `T` 需要推导时才叫万能引用（forwarding reference），例如函数模板参数、`auto&&`。
    `const T&&`、`std::vector<T>&&`、类模板中已确定的 `T&&` 都只是普通右值引用，只能绑定右值。
    推导规则：传左值时 `T` 推成 `U&`，经引用折叠得到 `U&`；传右值时 `T` 推成 `U`，得到 `U&&`。

    !!! tip "追问"
        `auto&&` 也是万能引用，推导规则与模板参数完全一致；但 `const auto&&` 就退化为普通右值引用。

???+ question "13. std::forward 和 std::move 有什么区别？"
    `move` 无条件把实参转成右值引用，用于「我确定不再需要它了」；`forward<T>` 是条件转换，`T` 为左值引用时返回左值，否则返回右值。
    `forward` 只能用于模板转发场景，且必须显式写出模板参数 `T`，否则推导不出原始值类别。
    对同一参数多次 `forward`/`move` 后继续使用，是被 move 后使用的经典错误。

???+ question "14. 对象被移动之后处于什么状态？"
    标准说法是「有效但未指定」（valid but unspecified）：可以析构、可以赋值、可以调用不依赖值的前置条件操作。
    标准库容器保证 `empty()` 等不变量仍成立，但元素个数、内容不确定；不要读它的值。
    自己实现移动时把源指针置空、大小清零，既安全又便于断言检查。

???+ question "15. 为什么移动构造函数要标 noexcept？"
    `vector` 扩容要提供强异常安全：用 `move_if_noexcept`，若移动构造可能抛且拷贝可用，就退化为拷贝。
    移动构造标 `noexcept` 才会真正走移动，否则大对象扩容会安静地变慢（甚至拷贝失败）。
    含 `string/vector` 成员的类，默认移动构造的 `noexcept` 依赖成员，必要时显式写 `noexcept = default`。

    !!! tip "追问"
        没标 `noexcept` 会怎样？`vector` 扩容时改走拷贝，结果正确但明显变慢，且可能因拷贝失败而抛出。

???+ question "16. RVO、NRVO 和复制省略是什么关系？"
    RVO 针对返回纯右值临时对象，C++17 起强制省略，直接在目标位置构造，不产生拷贝/移动。
    NRVO 针对返回具名局部变量，是允许但非强制的优化，主流编译器在 `-O2` 下都会做。
    因此不要写 `return std::move(x);`——它把返回值变成右值引用表达式，反而阻止 NRVO。

???+ question "17. shared_ptr 的控制块里有什么？"
    控制块含强引用计数、弱引用计数、删除器、分配器，以及（分离分配时）指向对象的指针；`shared_ptr` 自身是「对象指针 + 控制块指针」两个指针。
    强计数归零时销毁对象并调用删除器，弱计数归零时才释放控制块。
    这就是 `weak_ptr` 能在对象销毁后仍安全判断 `expired()` 的原因。

???+ question "18. make_shared 相比 shared_ptr(new T) 的取舍？"
    优点是单次分配（对象与控制块同块）、少一次 `new`、缓存局部性好、异常安全。
    代价是只要还有 `weak_ptr`，整块内存（含对象空间）都不能释放；也无法传自定义删除器。
    对象很大且 `weak_ptr` 生命周期长时，用 `shared_ptr<T>(new T)` 分离分配更省内存。

???+ question "19. enable_shared_from_this 的原理和坑？"
    基类里存一个 `weak_ptr`（libstdc++/MSVC 都是），`shared_ptr` 构造时检测到该基类就把它初始化为自身。
    `shared_from_this()` 把这个 weak 提升为 shared；对象不是由 `shared_ptr` 管理时，C++17 起抛 `std::bad_weak_ptr`。
    因此不要在构造函数里调用它——此时控制块还没建立。

???+ question "20. weak_ptr 是怎么做到不增加引用计数的？"
    它存对象指针和控制块指针，只增加弱计数；`lock()` 用原子操作检查强计数是否非零，非零则递增并返回 `shared_ptr`。
    这个检查和递增必须是原子的，否则会和另一线程的销毁竞争，所以不能写成「先 `expired()` 再解引用」。
    `weak_ptr` 常用于缓存、观察者列表和打破循环引用。

???+ question "21. shared_ptr 是线程安全的吗？"
    引用计数的增减是原子的，多个线程各自拷贝/销毁自己的 `shared_ptr` 副本安全。
    但同一个 `shared_ptr` 对象的读写（赋值、`reset`）不是线程安全的，需要加锁或用 C++20 的 `std::atomic<std::shared_ptr<T>>`。
    它管理的对象本身也完全不做同步，多线程访问对象仍需自己保护。

    !!! tip "追问"
        `shared_ptr` 为什么不能像 `unique_ptr` 那样零开销？—— 需要控制块存两份计数，原子操作本身也有成本。

???+ question "22. unique_ptr 的大小由什么决定？删除器放在哪？"
    默认删除器 `default_delete` 是空类，受 EBO 影响不占空间，所以 `sizeof(unique_ptr<T>) == sizeof(T*)`。
    有状态删除器（函数指针 8 字节、捕获的 lambda 更大）会成为 unique_ptr 的成员，直接增大对象；这也是它零开销的边界。
    `shared_ptr` 的删除器放在控制块里，不影响自身大小（始终两个指针）。

## 三、模板进阶

???+ question "23. 模板的实例化和两阶段查找是怎样的？"
    隐式实例化发生在使用点；`template class X<int>;` 是显式实例化定义，`extern template class X<int>;` 是显式实例化声明，用于减少重复实例化。
    名字查找分两阶段：定义点查找非依赖名，实例化点（含 ADL）查找依赖名，所以依赖名要在实例化点可见。
    成员函数按需实例化，只有被调用的成员才会生成代码，这也是模板错误常常「晚出现」的原因。

???+ question "24. 全特化和偏特化有什么区别？"
    全特化 `template<> class X<int> {...};` 为某一组具体实参提供完全独立的实现。
    偏特化 `template<class T> class X<T*>` 只对部分参数模式特化，且只能用于类模板；函数模板只能靠重载实现类似效果。
    匹配时最特化的版本优先；偏特化参与重载决议的顺序比全特化复杂，写的时候尽量让模式互斥。

???+ question "25. SFINAE 是什么？现在还推荐用吗？"
    Substitution Failure Is Not An Error：模板实参替换失败只是把该候选从重载集中移除，不报错。
    典型用法 `std::enable_if_t<std::is_integral_v<T>, int> = 0` 或检测成员是否存在，实现编译期分派。
    它只对「立即上下文」的替换失败生效，函数体里的错误仍是硬错误；C++20 起优先用 concepts，报错更可读。

???+ question "26. type_traits 是怎么实现的？"
    本质是模板 + 特化：`is_pointer<T>` 主模板继承 `false_type`，`is_pointer<T*>` 偏特化继承 `true_type`。
    部分 traits（`is_trivially_copyable`、`is_standard_layout`）依赖编译器内建（intrinsic），标准库无法纯靠语言实现。
    `enable_if`、`conditional`、`decay` 都是在这套机制上做类型计算。

???+ question "27. concepts 相比 SFINAE 好在哪？"
    C++20 的 concept 把约束写成具名谓词：`template<std::integral T> T gcd(T, T);`，可读性和报错质量都远好于 `enable_if`。
    约束参与重载决议并支持包含关系（subsumption），更特化的约束优先；还能用于类模板、变量模板和 `auto`。
    它仍然是编译期检查，不产生运行时开销。

???+ question "28. CRTP 是什么？用来做什么？"
    Curiously Recurring Template Pattern：`template<class D> struct Base { void f() { static_cast<D*>(this)->impl(); } };`，派生类把自己作为模板参数传入。
    它实现静态多态：编译期绑定、可内联、零虚表开销，用于 mixin、计数器、接口注入。
    代价是不能存放异构集合，且派生类必须完整定义后基类成员才能实例化。

???+ question "29. 可变参数模板和折叠表达式怎么用？"
    `template<class... Ts> void f(Ts... args)`，用 `sizeof...(Ts)` 取个数，C++17 折叠表达式 `(args + ...)` 一行展开。
    转发时写 `f(std::forward<Ts>(args)...)`，逗号折叠 `(print(args), ...)` 可依次处理每个参数。
    C++11 时代要靠递归 + 空参重载终止，代码更长但思路相同。

???+ question "30. 模板代码膨胀怎么缓解？"
    每个实例化都会生成一份代码，类型多、编译单元多时代码体积和编译时间都会爆炸。
    手段：把不依赖模板参数的逻辑抽到非模板基类或普通函数、用 `extern template` 抑制重复实例化、用类型擦除（`function`、`any`）换体积。
    但要权衡：这些手段通常以运行时间接调用为代价。

## 四、并发

???+ question "31. thread 的 join 和 detach 有什么区别？析构时要注意什么？"
    `join` 阻塞等待线程结束并回收资源；`detach` 让线程在后台独立运行，失去同步手段。
    `std::thread` 析构时若仍 `joinable()` 会直接 `std::terminate`，所以必须显式 join/detach，或用 RAII 包装。
    `detach` 后线程若访问已销毁的局部变量就是悬空引用，C++20 的 `std::jthread` 析构自动 join 更安全。

???+ question "32. C++ 标准库有哪些 mutex？"
    `mutex`：最常用；`recursive_mutex`：同线程可重复加锁，容易掩盖设计问题；`timed_mutex`：支持 `try_lock_for/until`。
    `recursive_timed_mutex` 是两者结合；C++17 的 `shared_mutex` 提供读写锁（`shared_lock` 读、`unique_lock` 写）。
    选型原则：能用普通 mutex 就别用递归锁，读多写少才考虑读写锁。

???+ question "33. lock_guard、unique_lock、scoped_lock 怎么选？"
    `lock_guard` 最轻：构造加锁、析构解锁，不能手动解锁、不能移动，适合简单临界区。
    `unique_lock` 灵活：可延迟加锁、手动 lock/unlock、可移动，条件变量必须用它；代价是多一个标志位。
    `scoped_lock`（C++17）一次锁多个 mutex 并用死锁避免算法，替代 `std::lock` + `lock_guard` 的组合。

    | 特性 | `lock_guard` | `unique_lock` | `scoped_lock` |
    | --- | --- | --- | --- |
    | 手动解锁 | 不支持 | 支持 | 不支持 |
    | 可移动 | 否 | 是 | 否 |
    | 多锁防死锁 | 否 | 否 | 是 |
    | 条件变量 | 不能配合 | 必须用它 | 不能配合 |

???+ question "34. 死锁的四个必要条件是什么？工程上怎么避免？"
    互斥、占有且等待、不可抢占、循环等待，四者同时成立才可能死锁，破坏任意一个即可。
    实践：固定全局加锁顺序、用 `scoped_lock` 一次性锁多个、需要多个锁时用 `try_lock` 加超时回退。
    另外别在持锁时调用未知回调、别在锁内做阻塞 IO，锁粒度尽量小。

???+ question "35. 条件变量为什么会虚假唤醒？怎么写才正确？"
    `wait` 可能在没有任何 `notify` 的情况下返回（实现允许），也可能被其他线程的 notify 误唤醒。
    必须用谓词版本：`cv.wait(lk, [&]{ return !q.empty() || stop; });`，它内部就是 while 循环检查。
    修改共享状态要在持锁时进行，`notify_one/all` 可以在解锁后调用以减少唤醒抖动。

???+ question "36. 内存序有哪几种？acquire/release 建立的是什么关系？"
    `relaxed` 只保证原子性和修改顺序；`acquire`/`release` 建立同步关系；`acq_rel` 用于读改写；`seq_cst` 是默认的全局一致顺序。
    典型模式：写线程 `store(release)` 发布数据，读线程 `load(acquire)` 后就能看到之前的所有写，即 happens-before。
    无锁编程必须能说清每条访问的序，否则默认用 `seq_cst` 保正确。

???+ question "37. volatile 和 atomic 有什么区别？"
    `volatile` 只阻止编译器优化掉访问，不保证原子性、不建立内存序、不阻止 CPU 重排，不能用于线程同步。
    `std::atomic` 保证原子读写并可选内存序，是并发编程的唯一正确工具。
    `volatile` 的正当用途是 MMIO 寄存器和信号处理里的 `sig_atomic_t`，与多线程无关。

???+ question "38. future、promise、async、packaged_task 怎么配合？"
    `promise` 是写端，`set_value/set_exception` 后对应 `future` 就绪；`future` 是读端，`get()` 只能调一次。
    `packaged_task` 把可调用对象包装成可异步执行的任务，自动把返回值/异常存进 future。
    `async` 是高层封装，`launch::async` 强制新线程，`launch::deferred` 延迟到 `get()` 才执行；默认策略可能都不做，需显式指定。

???+ question "39. 线程池的核心设计是什么？"
    固定数量 worker + 任务队列（`std::function<void()>`）+ mutex/条件变量 + stop 标志；`submit` 用 `packaged_task` 包装并返回 `future`。
    关闭时先置 stop、`notify_all`，worker 把队列剩余任务执行完再退出，最后 join。
    异常必须被捕获（`packaged_task` 会把异常存进 future），否则线程会因未捕获异常而终止。

???+ question "40. 什么是伪共享（false sharing）？怎么解决？"
    两个线程分别写同一 cache line 内的不同变量，缓存一致性协议让该行在核间来回失效，性能骤降。
    解决：用 `alignas(64)` 把热变量按 cache line 隔离，或让每个线程写自己的局部计数最后汇总。
    典型受害者是高频更新的原子计数器和数组中的相邻槽位。

## 五、性能与底层

???+ question "41. 从性能角度，虚函数值不值得用？"
    代价是间接调用、无法内联、可能的分支预测失败和额外的 vptr 空间；但在大多数业务代码里占比很小。
    只有 profile 证明它是热点时才优化，手段有 `final`、LTO、PGO 去虚化，或改 CRTP、`variant + visit`、tag + switch。
    过早去虚化会让代码变难维护，收益却可能不到 1%。

???+ question "42. 怎么写缓存友好的代码？"
    顺序访问连续内存、减少指针追逐（链表、树在热路径上不友好）、把热数据与冷数据分开存放。
    数据结构选择上优先 `vector`，需要多字段时比较 AoS 与 SoA；循环嵌套按行优先遍历二维数组。
    必要时用软件预取（`__builtin_prefetch`）和分块（blocking）改善局部性。

???+ question "43. inline 对优化到底意味着什么？"
    内联消除调用开销，更重要的是把函数体暴露给调用点，从而做常量传播、死代码消除、标量替换等优化。
    过度内联会让代码膨胀、i-cache 命中率下降；现代编译器按成本模型决定，`inline` 关键字只是提示。
    强制内联是编译器扩展（`__attribute__((always_inline))`、`__forceinline`），慎用。

???+ question "44. C++ 异常的开销在哪里？"
    主流实现是零开销异常（table-based）：不抛异常时没有运行时检查，代价是二进制里的 unwind 表和代码体积。
    抛异常时开销很大：栈展开、逐帧查找 handler，通常微秒级，所以不要用异常做流程控制。
    禁用异常用 `-fno-exceptions`，此时 `new` 失败不会抛 `bad_alloc`，标准库行为也会改变。

???+ question "45. 内存池解决什么问题？怎么实现？"
    减少 `malloc/free` 调用次数与内存碎片，提高分配速度，保证局部性；高频小对象场景收益最大。
    固定大小对象池：预分配大块、切成等长 slot 串成 free list，分配/释放 O(1)；变长可用 size class + 分级 free list。
    难点是对齐、线程安全（thread-local pool）、与析构语义配合（placement new + 显式析构）。

???+ question "46. cache line 多大？它如何影响程序性能？"
    主流 x86/ARM 是 64 字节；CPU 以行为单位搬运数据，相邻变量会被一起读入。
    好处是顺序访问极快，坏处是伪共享、以及「数组元素跨行」导致的额外读取。
    设计并发数据结构和热路径结构时要按行思考：谁和谁在同一行、谁会被哪个核写。

???+ question "47. 未定义行为为什么会影响优化？举一个例子。"
    编译器可以假设 UB 不会发生，据此删除分支、假设指针不别名、假设循环会终止。
    经典例子：有符号整数溢出是 UB，`if (x + 1 < x)` 可能被优化成 `false`；违反严格别名（用 `int*` 读 `float` 内存）会产生错误结果。
    正确做法：用无符号或 `__builtin_add_overflow`，用 `memcpy`/`std::bit_cast` 做类型双关。

???+ question "48. 线上内存泄漏和性能瓶颈怎么定位？"
    泄漏：ASan（`-fsanitize=address`）、Valgrind、heaptrack 抓分配栈，或重载 `operator new/delete` 记录计数与调用点。
    性能：先 `perf record`/火焰图找热点，再看缓存 miss、分支 miss、系统调用；用 `chrono` 做微基准，注意预热与防止优化掉。
    原则是先测量再优化，一次只改一个变量。

## 六、工程与系统

???+ question "49. 什么是 ABI 兼容？哪些改动会破坏它？"
    ABI 是二进制层面的约定：名字修饰、对象布局、vtable 布局、调用约定、异常机制、STL 实现细节。
    破坏兼容：增删虚函数（改变 vtable 顺序）、增删成员（改变大小与偏移）、改函数签名、换编译器/标准库版本。
    保持兼容的手段：pimpl 隐藏实现、只暴露纯 C 接口、预留虚函数槽位、版本化符号。

???+ question "50. 动态库是怎么加载和解析符号的？"
    Linux 用 `dlopen/dlsym/dlclose`，Windows 用 `LoadLibrary/GetProcAddress`；加载时重定位、解析未定义符号。
    符号解析遵循「先全局后局部」的顺序，`LD_PRELOAD` 可以劫持符号，这也是打补丁和 mock 的手段。
    插件架构要注意初始化顺序、`RTLD_LOCAL` 隔离、以及卸载后函数指针失效。

???+ question "51. LTO 和 PGO 分别是什么？"
    LTO（Link Time Optimization）：链接期拿到所有 TU 的中间表示，做跨文件内联、去虚化、常量传播，代价是构建变慢。
    PGO（Profile Guided Optimization）：用真实负载跑出 profile，指导分支布局、内联与寄存器分配，通常有 5%-15% 提升。
    两者常配合使用，但会让构建可复现性变差，需要把 profile 纳入构建流程管理。

???+ question "52. 编译期计算有哪些手段？"
    `constexpr` 函数（C++14 起支持循环与局部变量）、`constexpr` 变量、`if constexpr`（C++17）做编译期分支。
    C++20 引入 `consteval`（必须编译期求值）和 `constinit`（保证静态初始化），还有 `concept` 做约束。
    编译期计算能消除运行时开销，但会增加编译时间与二进制复杂度，适度使用。

???+ question "53. ODR 是什么？违反会怎样？"
    One Definition Rule：函数、变量、类类型、模板在整个程序中只能有一个定义（`inline` 函数/变量与模板允许每 TU 一份相同定义）。
    违反的常见后果：链接期 multiple definition；更隐蔽的是不同 TU 看到不同的类定义，布局不一致导致静默内存错乱（UB）。
    头文件里定义非 `inline` 全局变量、`#pragma pack` 不一致、条件编译改变类布局，都是经典肇事者。

???+ question "54. 常见未定义行为清单有哪些？"
    越界访问、空指针/悬空指针解引用、有符号整数溢出、除零、读取未初始化变量、对象生命周期结束后访问、数据竞争。
    还有：`delete` 非 `new` 指针、`delete[]` 与 `new` 不匹配、修改字符串字面量、严格别名违反、`va_arg` 类型不匹配、`memcpy` 重叠。
    面试技巧：说出「编译器可以做任何事，包括看起来正常」，再举一个被优化掉的例子即可。

## 收尾

- 进阶题的高分回答都包含「编译器生成了什么」和「代价是什么」两部分。
- 拿不准的题先讲结论与边界，再承认实现相关（Itanium ABI / MSVC ABI 差异），比硬编细节更稳。

继续看：[面试八股 · 基础篇](interview-basics.md)、[手撕代码题库](handwritten.md)、[性能与调试](performance.md)。

import Darwin

/// 本机的 host 端口。`mach_host_self()` 每调用一次，进程就多持有一个发送权引用，
/// 采样每隔一两秒跑一轮，常驻几周会一直累积；这里只取一次，全进程复用
let hostPort: mach_port_t = mach_host_self()

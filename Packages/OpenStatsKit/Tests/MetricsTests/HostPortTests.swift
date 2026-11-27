import Darwin
import Testing
@testable import Metrics

/// 常驻采样不能让 Mach 端口的引用数随采样次数增长（issue #20）
@Suite(.serialized) struct HostPortTests {
    private func sendRefs(_ port: mach_port_t) -> mach_port_urefs_t {
        var refs: mach_port_urefs_t = 0
        mach_port_get_refs(mach_task_self_, port, MACH_PORT_RIGHT_SEND, &refs)
        return refs
    }

    @Test func measuringNoticesAnUnreleasedHostPort() {
        // 对照：不归还的 mach_host_self() 确实会让引用数加一，说明下面的测量看得见泄漏
        let before = sendRefs(hostPort)
        let leaked = mach_host_self()
        #expect(sendRefs(hostPort) == before + 1)
        mach_port_deallocate(mach_task_self_, leaked)
        #expect(sendRefs(hostPort) == before)
    }

    @Test func samplingDoesNotAccumulatePortReferences() {
        var set: processor_set_name_t = 0
        #expect(processor_set_default(hostPort, &set) == KERN_SUCCESS)
        defer { mach_port_deallocate(mach_task_self_, set) }

        var cpu = CPUSampler()
        let memory = MemorySampler()
        _ = cpu.sample()
        let hostBefore = sendRefs(hostPort)
        let setBefore = sendRefs(set)
        #expect(hostBefore > 0)
        #expect(setBefore > 0)

        for _ in 0..<500 {
            // 两次采样挨得太近时 CPU 采样没有差值可算，返回空是正常的，这里只关心端口
            _ = cpu.sample()
            _ = memory.sample()
            _ = SystemCounts.read()
            _ = CPUTicks.read()
        }
        #expect(sendRefs(hostPort) == hostBefore)
        #expect(sendRefs(set) == setBefore)
    }
}

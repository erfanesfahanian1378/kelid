import Darwin

/// Reads the process's `phys_footprint` — the same figure the Jetsam
/// mechanism uses to decide whether to kill an over-budget keyboard
/// extension (PLAN.md §2.1 C1, §6.13). Backs the debug overlay's memory
/// reading and the Phase 1 diagnostics line.
public enum MemoryProbe {
    public static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}

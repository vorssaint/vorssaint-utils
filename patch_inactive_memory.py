with open('Sources/Vorssaint/Services/InactiveAppService.swift', 'r') as f:
    content = f.read()

# Replace the memory check
memory_check = """
                let footprint = InactiveAppService.physicalFootprint(of: pid) ?? 0
                let memoryMB = Int(footprint / (1024 * 1024))
"""

import re
content = re.sub(r'                let usage = ProcessUsageService\.shared\.snapshot\.processes\.first\(where: \{ \$0\.pid == pid \}\)\n                let memoryMB = \(usage\?\.memoryBytes \?\? 0\) / \(1024 \* 1024\)', memory_check, content)

# Add the helper
helper = """
    private static func physicalFootprint(of pid: pid_t) -> Double? {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0, info.ri_phys_footprint > 0 else { return nil }
        return Double(info.ri_phys_footprint)
    }
}
"""
content = content.replace('}\n', '}\n' + helper)
# Wait, replacing `}\n` might add it multiple times. Let's find the end of the file.
lines = content.split('\n')
for i in range(len(lines)-1, -1, -1):
    if lines[i] == '}':
        lines[i] = helper
        break
content = '\n'.join(lines)

with open('Sources/Vorssaint/Services/InactiveAppService.swift', 'w') as f:
    f.write(content)

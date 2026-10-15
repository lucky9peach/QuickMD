import Cocoa

// 把 QuickMD 设为 Markdown 默认打开方式（用户级，无需密码）
let bundleID = "com.quickmd.app" as CFString
let utis = ["net.daringfireball.markdown", "public.markdown"]
for uti in utis as [CFString] {
    for role in [LSRolesMask.viewer, LSRolesMask.editor] {
        let st = LSSetDefaultRoleHandlerForContentType(uti, role, bundleID)
        print("设置 [\(uti)] role=\(role.rawValue): \(st == noErr ? "OK" : "fail \(st)")")
    }
}
print("--- 验证 ---")
for uti in utis as [CFString] {
    for (name, role) in [("viewer", LSRolesMask.viewer), ("editor", LSRolesMask.editor)] {
        if let h = LSCopyDefaultRoleHandlerForContentType(uti, role)?.takeRetainedValue() {
            print("[\(uti)] \(name) = \(h)")
        } else { print("[\(uti)] \(name) = (未知)") }
    }
}

import AppKit
import CoreGraphics
import ApplicationServices

// Characterises the SkyLight window transform: which coordinate convention it
// uses, whether bounds reporting follows, and whether foreign windows need TCC.

typealias CGSConnectionID = UInt32
let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)!
func sym<T>(_ name: String, as type: T.Type) -> T? {
    guard let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}
typealias MainConnectionFn = @convention(c) () -> CGSConnectionID
typealias SetTransformFn = @convention(c) (CGSConnectionID, UInt32, CGAffineTransform) -> Int32
typealias GetTransformFn = @convention(c) (CGSConnectionID, UInt32, UnsafeMutablePointer<CGAffineTransform>) -> Int32

let mainConnection = sym("CGSMainConnectionID", as: MainConnectionFn.self)!
let setTransform = sym("CGSSetWindowTransform", as: SetTransformFn.self)!
let getTransform = sym("CGSGetWindowTransform", as: GetTransformFn.self)!

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "Transform probe"
window.setFrameOrigin(NSPoint(x: 500, y: 400))
window.makeKeyAndOrderFront(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.5))

let wid = UInt32(window.windowNumber)
let cid = mainConnection()

func serverBounds(_ id: UInt32) -> CGRect {
    guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
          let entry = list.first,
          let dict = entry[kCGWindowBounds as String] as? [String: Any],
          let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return .zero }
    return rect
}

print("AX frame: \(window.frame)")
print("server  : \(serverBounds(wid))")

func apply(_ name: String, _ t: CGAffineTransform) {
    let err = setTransform(cid, wid, t)
    RunLoop.main.run(until: Date().addingTimeInterval(0.35))
    var readBack = CGAffineTransform.identity
    _ = getTransform(cid, wid, &readBack)
    print("\(name): err=\(err) readback(a=\(readBack.a), tx=\(readBack.tx), ty=\(readBack.ty)) server=\(serverBounds(wid)) ax=\(window.frame)")
}

apply("identity", .identity)
apply("translate(+200,+100)", CGAffineTransform(translationX: 200, y: 100))
apply("scale(0.5)", CGAffineTransform(scaleX: 0.5, y: 0.5))
apply("scale(0.5)+translate(300,150)", CGAffineTransform(scaleX: 0.5, y: 0.5).concatenating(CGAffineTransform(translationX: 300, y: 150)))
apply("scale(2)", CGAffineTransform(scaleX: 2, y: 2))
apply("restore", .identity)

// Foreign window: Finder's front window.
let finder = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }
if let pid = finder?.processIdentifier {
    let axApp = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
       let windows = value as? [AXUIElement],
       let target = windows.first {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(target, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(target, kAXSizeAttribute as CFString, &sizeRef)
        var p = CGPoint.zero
        var s = CGSize.zero
        if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &p) }
        if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &s) }
        print("finder AX frame: \(p) \(s) trusted=\(AXIsProcessTrusted())")

        let finderWindows = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
        if let first = finderWindows.first, let number = first[kCGWindowNumber as String] as? UInt32 {
            print("finder server before: \(serverBounds(number))")
            let err = setTransform(cid, number, CGAffineTransform(scaleX: 0.75, y: 0.75))
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            print("finder transform err=\(err) server after: \(serverBounds(number))")
            _ = setTransform(cid, number, .identity)
        } else {
            print("no finder window found")
        }
    } else {
        print("could not read finder windows (trusted=\(AXIsProcessTrusted()))")
    }
}

import AppKit
import CoreGraphics

// Which private calls report a window's real on-screen rect while a transform
// is installed? CGSGetWindowBounds is what yabai uses for frames.

typealias CGSConnectionID = UInt32
let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)!
func sym<T>(_ name: String, as type: T.Type) -> T? {
    guard let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

typealias MainConnectionFn = @convention(c) () -> CGSConnectionID
typealias SetTransformFn = @convention(c) (CGSConnectionID, UInt32, CGAffineTransform) -> Int32
typealias GetBoundsFn = @convention(c) (CGSConnectionID, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
typealias GetPointFn = @convention(c) (CGSConnectionID, UInt32, UnsafeMutablePointer<CGPoint>) -> Int32
typealias GetSizeFn = @convention(c) (CGSConnectionID, UInt32, UnsafeMutablePointer<CGSize>) -> Int32

let mainConnection = sym("CGSMainConnectionID", as: MainConnectionFn.self)!
let setTransform = sym("CGSSetWindowTransform", as: SetTransformFn.self)!
let getWindowBounds = sym("CGSGetWindowBounds", as: GetBoundsFn.self)
let getWindowOrigin = sym("CGSGetWindowOrigin", as: GetPointFn.self)
let getWindowSize = sym("CGSGetWindowSize", as: GetSizeFn.self)
let getScreenRect = sym("CGSGetScreenRectForWindow", as: GetBoundsFn.self)

print("symbols: bounds=\(getWindowBounds != nil) origin=\(getWindowOrigin != nil) size=\(getWindowSize != nil) screenRect=\(getScreenRect != nil)")

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "Bounds probe"
window.setFrameOrigin(NSPoint(x: 500, y: 400))
window.makeKeyAndOrderFront(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.5))

let wid = UInt32(window.windowNumber)
let cid = mainConnection()

func dump(_ label: String) {
    var b = CGRect.zero
    var o = CGPoint.zero
    var s = CGSize.zero
    var sr = CGRect.zero
    let eb = getWindowBounds?(cid, wid, &b) ?? -999
    let eo = getWindowOrigin?(cid, wid, &o) ?? -999
    let es = getWindowSize?(cid, wid, &s) ?? -999
    let esr = getScreenRect?(cid, wid, &sr) ?? -999
    print("\(label): bounds(err=\(eb))=\(b) origin(err=\(eo))=\(o) size(err=\(es))=\(s) screenRect(err=\(esr))=\(sr) ax=\(window.frame)")
}

func apply(_ label: String, _ t: CGAffineTransform) {
    _ = setTransform(cid, wid, t)
    RunLoop.main.run(until: Date().addingTimeInterval(0.35))
    dump(label)
}

dump("before")
apply("identity", .identity)
apply("translate(200,100)", CGAffineTransform(translationX: 200, y: 100))
apply("scale0.5", CGAffineTransform(scaleX: 0.5, y: 0.5))
apply("scale0.5 then translate(600,300)", CGAffineTransform(scaleX: 0.5, y: 0.5).concatenating(CGAffineTransform(translationX: 600, y: 300)))
apply("translate(600,300) then scale0.5", CGAffineTransform(translationX: 600, y: 300).concatenating(CGAffineTransform(scaleX: 0.5, y: 0.5)))
apply("restore", .identity)

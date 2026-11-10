import AppKit
import CoreGraphics

// Try the window server's own capture APIs: if any of these returns an image
// while a transform is installed, it is both an oracle for the transform
// convention and a way to build thumbnail/canvas previews without Screen
// Recording permission.

typealias CGSConnectionID = UInt32
let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)!
func sym<T>(_ name: String, as type: T.Type) -> T? {
    guard let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

typealias MainConnectionFn = @convention(c) () -> CGSConnectionID
typealias SetTransformFn = @convention(c) (CGSConnectionID, UInt32, CGAffineTransform) -> Int32
typealias HWCaptureFn = @convention(c) (CGSConnectionID, UnsafePointer<UInt32>, Int, UInt32) -> CGImage?
typealias CreateSnapshotFn = @convention(c) (CGSConnectionID, UInt32, CGRect, UInt32, UnsafeMutablePointer<Unmanaged<CGImage>?>) -> Int32

let mainConnection = sym("CGSMainConnectionID", as: MainConnectionFn.self)!
let setTransform = sym("CGSSetWindowTransform", as: SetTransformFn.self)!
let hwCapture = sym("CGSHWCaptureWindowList", as: HWCaptureFn.self)
let createSnapshot = sym("CGSCreateWindowSnapshot", as: CreateSnapshotFn.self)

let allSymbols = ["CGSHWCaptureWindowList", "CGSCreateWindowSnapshot", "CGSCaptureWindowsContents", "CGSGetWindowSnapshot", "CGSCopyWindowImage"]
for name in allSymbols {
    print("\(name): \(dlsym(handle, name) != nil ? "present" : "missing")")
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "Capture probe"
let label = NSTextField(labelWithString: "CAPTURE")
label.font = .systemFont(ofSize: 60, weight: .heavy)
label.alignment = .center
label.frame = NSRect(x: 0, y: 110, width: 400, height: 80)
window.contentView?.addSubview(label)
window.setFrameOrigin(NSPoint(x: 500, y: 400))
window.makeKeyAndOrderFront(nil)
RunLoop.main.run(until: Date().addingTimeInterval(0.5))

let wid = UInt32(window.windowNumber)
let cid = mainConnection()

import ImageIO
import UniformTypeIdentifiers

func save(_ image: CGImage?, _ path: String) {
    guard let image else { print("no image for \(path)"); return }
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        print("could not create destination for \(path)")
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    if CGImageDestinationFinalize(destination) {
        print("wrote \(path) \(image.width)x\(image.height)")
    } else {
        print("could not finalize \(path)")
    }
}

// Baseline snapshot (no transform).
if let createSnapshot {
    var out: Unmanaged<CGImage>?
    let err = withUnsafeMutablePointer(to: &out) { pointer in
        createSnapshot(cid, wid, CGRect(x: 0, y: 0, width: 400, height: 332), 0, pointer)
    }
    print("CGSCreateWindowSnapshot err=\(err)")
    save(out?.takeRetainedValue(), "/tmp/snapshot-before.png")
}

if let hwCapture {
    var id = wid
    let image = withUnsafePointer(to: &id) { hwCapture(cid, $0, 1, 0) }
    save(image, "/tmp/hwcapture-before.png")
}

// Install a 0.5 transform and capture again.
_ = setTransform(cid, wid, CGAffineTransform(scaleX: 0.5, y: 0.5))
RunLoop.main.run(until: Date().addingTimeInterval(0.4))

if let createSnapshot {
    var out: Unmanaged<CGImage>?
    let err = withUnsafeMutablePointer(to: &out) { pointer in
        createSnapshot(cid, wid, CGRect(x: 0, y: 0, width: 400, height: 332), 0, pointer)
    }
    print("CGSCreateWindowSnapshot after err=\(err)")
    save(out?.takeRetainedValue(), "/tmp/snapshot-after.png")
}

if let hwCapture {
    var id = wid
    let image = withUnsafePointer(to: &id) { hwCapture(cid, $0, 1, 0) }
    save(image, "/tmp/hwcapture-after.png")
}

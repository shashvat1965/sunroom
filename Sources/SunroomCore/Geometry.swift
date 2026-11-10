import Foundation
import CoreGraphics

// MARK: - CanvasPoint

/// A point in canvas space. Canvas space is an unbounded plane whose origin is
/// arbitrary; the document stores nodes in this space so panning and zooming
/// never mutate node geometry.
public struct CanvasPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    public static let zero = CanvasPoint(x: 0, y: 0)

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: CanvasPoint) -> Double {
        CanvasPoint(x: other.x - x, y: other.y - y).length
    }

    public func rounded(to scale: Double) -> CanvasPoint {
        guard scale > 0 else { return self }
        return CanvasPoint(x: (x / scale).rounded() * scale, y: (y / scale).rounded() * scale)
    }

    public static func + (lhs: CanvasPoint, rhs: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: CanvasPoint, rhs: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: CanvasPoint, rhs: Double) -> CanvasPoint {
        CanvasPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func / (lhs: CanvasPoint, rhs: Double) -> CanvasPoint {
        CanvasPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    public static prefix func - (value: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: -value.x, y: -value.y)
    }
}

// MARK: - CanvasSize

public struct CanvasSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.width = Double(size.width)
        self.height = Double(size.height)
    }

    public static let zero = CanvasSize(width: 0, height: 0)

    public var cgSize: CGSize { CGSize(width: width, height: height) }

    public var aspectRatio: Double { height == 0 ? 1 : width / height }
}

// MARK: - CanvasRect

/// An axis-aligned rectangle in canvas space. `standardized` keeps width and
/// height non-negative, which the editor relies on for hit-testing.
public struct CanvasRect: Codable, Hashable, Sendable {
    public var origin: CanvasPoint
    public var size: CanvasSize

    public init(origin: CanvasPoint, size: CanvasSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: CanvasPoint(x: x, y: y), size: CanvasSize(width: width, height: height))
    }

    public init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    /// Builds the smallest rectangle containing both corners, in any order.
    public init(corner a: CanvasPoint, corner b: CanvasPoint) {
        self.init(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    public static let zero = CanvasRect(x: 0, y: 0, width: 0, height: 0)

    public var cgRect: CGRect { CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height) }

    public var minX: Double { min(origin.x, origin.x + size.width) }
    public var minY: Double { min(origin.y, origin.y + size.height) }
    public var maxX: Double { max(origin.x, origin.x + size.width) }
    public var maxY: Double { max(origin.y, origin.y + size.height) }

    public var width: Double { abs(size.width) }
    public var height: Double { abs(size.height) }

    public var center: CanvasPoint {
        CanvasPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    public var standardized: CanvasRect {
        CanvasRect(x: minX, y: minY, width: width, height: height)
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public var area: Double { width * height }

    public func contains(_ point: CanvasPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func intersects(_ other: CanvasRect) -> Bool {
        !(other.minX > maxX || other.maxX < minX || other.minY > maxY || other.maxY < minY)
    }

    public func intersection(_ other: CanvasRect) -> CanvasRect? {
        guard intersects(other) else { return nil }
        let x0 = Swift.max(minX, other.minX)
        let y0 = Swift.max(minY, other.minY)
        let x1 = Swift.min(maxX, other.maxX)
        let y1 = Swift.min(maxY, other.maxY)
        return CanvasRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func union(_ other: CanvasRect) -> CanvasRect {
        CanvasRect(
            x: Swift.min(minX, other.minX),
            y: Swift.min(minY, other.minY),
            width: Swift.max(maxX, other.maxX) - Swift.min(minX, other.minX),
            height: Swift.max(maxY, other.maxY) - Swift.min(minY, other.minY)
        )
    }

    public func insetBy(_ amount: Double) -> CanvasRect {
        CanvasRect(x: minX + amount, y: minY + amount, width: max(0, width - amount * 2), height: max(0, height - amount * 2))
    }

    public func expandedBy(_ amount: Double) -> CanvasRect {
        insetBy(-amount)
    }

    public func offsetBy(dx: Double, dy: Double) -> CanvasRect {
        CanvasRect(x: minX + dx, y: minY + dy, width: width, height: height)
    }

    public func offsetBy(_ delta: CanvasPoint) -> CanvasRect {
        offsetBy(dx: delta.x, dy: delta.y)
    }

    public func translated(to newOrigin: CanvasPoint) -> CanvasRect {
        CanvasRect(origin: newOrigin, size: size)
    }

    /// Returns a rect with the given edge pinned, changing only that edge.
    public func withMinX(_ value: Double) -> CanvasRect {
        CanvasRect(x: value, y: minY, width: maxX - value, height: height)
    }

    public func withMinY(_ value: Double) -> CanvasRect {
        CanvasRect(x: minX, y: value, width: width, height: maxY - value)
    }

    public func withMaxX(_ value: Double) -> CanvasRect {
        CanvasRect(x: minX, y: minY, width: value - minX, height: height)
    }

    public func withMaxY(_ value: Double) -> CanvasRect {
        CanvasRect(x: minX, y: minY, width: width, height: value - minY)
    }

    public func scaled(by factor: Double) -> CanvasRect {
        CanvasRect(
            x: center.x - width * factor / 2,
            y: center.y - height * factor / 2,
            width: width * factor,
            height: height * factor
        )
    }

    public static func bounding(_ rects: [CanvasRect]) -> CanvasRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result
    }

    /// True when `other` is entirely inside the receiver.
    public func encloses(_ other: CanvasRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    }
}

// MARK: - Free functions

public enum Geometry {
    /// Distance from a point to a rect (0 when inside).
    public static func distance(from point: CanvasPoint, to rect: CanvasRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Clamps a value into a closed range.
    public static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }

    /// Normalizes an angle in degrees into (-180, 180].
    public static func normalizedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value <= -180 { value += 360 }
        if value > 180 { value -= 360 }
        return value
    }
}

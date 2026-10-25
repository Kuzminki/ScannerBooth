import CoreGraphics

struct NormalizedPoint: Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat

    func clamped() -> NormalizedPoint {
        NormalizedPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

struct DocumentQuad: Equatable, Sendable {
    var topLeft: NormalizedPoint
    var topRight: NormalizedPoint
    var bottomRight: NormalizedPoint
    var bottomLeft: NormalizedPoint

    static let imageBounds = DocumentQuad(
        topLeft: .init(x: 0, y: 0),
        topRight: .init(x: 1, y: 0),
        bottomRight: .init(x: 1, y: 1),
        bottomLeft: .init(x: 0, y: 1)
    )

    var points: [NormalizedPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    func point(at index: Int) -> NormalizedPoint { points[index] }

    func replacing(pointAt index: Int, with point: NormalizedPoint) -> DocumentQuad {
        var copy = self
        switch index {
        case 0: copy.topLeft = point
        case 1: copy.topRight = point
        case 2: copy.bottomRight = point
        case 3: copy.bottomLeft = point
        default: break
        }
        return copy
    }

    var area: CGFloat {
        let vertices = points
        var sum: CGFloat = 0
        for index in vertices.indices {
            let next = vertices[(index + 1) % vertices.count]
            sum += vertices[index].x * next.y - next.x * vertices[index].y
        }
        return abs(sum) / 2
    }

    var isValid: Bool {
        let vertices = points
        var direction: CGFloat = 0
        for index in vertices.indices {
            let a = vertices[index]
            let b = vertices[(index + 1) % vertices.count]
            let c = vertices[(index + 2) % vertices.count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 0.0001 { continue }
            if direction == 0 { direction = cross }
            else if cross * direction < 0 { return false }
        }
        return area > 0.015 && direction != 0
    }
}

func imagePoint(fromVision point: CGPoint) -> NormalizedPoint {
    NormalizedPoint(x: point.x, y: 1 - point.y)
}

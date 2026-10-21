import CoreGraphics
import Foundation

/// A force-directed layout in the plane, like thaali's d3 simulations: linked
/// nodes pull toward a rest length, nearby nodes push apart, and a weak pull
/// holds everything toward the origin. Each step cools it until it settles.
/// Repulsion is summed over a Barnes–Hut quadtree, a far cluster counting as
/// one body, so a step costs about n log n.
struct ForceLayout: Sendable {
    /// Two linked nodes, by index.
    struct Link: Hashable, Sendable {
        let a: Int
        let b: Int
    }

    let links: [Link]
    private(set) var positions: [CGPoint]
    private var velocities: [CGVector]
    private let degrees: [Int]
    /// How hot the layout still is; forces scale with it.
    private(set) var alpha: Double

    var linkLength: Double = 46
    var repulsion: Double = 1400
    /// The farthest repulsion reaches.
    var reach: Double = 360
    /// How wide a cluster may look before it is opened rather than counted as one body.
    var theta: Double = 0.9
    var gravity: Double = 0.015
    var friction: Double = 0.58
    var cooling: Double = 0.982
    static let settledAlpha = 0.004

    var settled: Bool { alpha < Self.settledAlpha }

    /// Nodes start where `seed` puts them, the rest on a sunflower spiral
    /// around the origin, the first nearest. A layout that mostly keeps old
    /// positions starts cooler, at `alpha`.
    init(count: Int, links: [Link], seed: [Int: CGPoint] = [:], alpha: Double = 1) {
        self.links = links
        self.alpha = alpha
        positions = (0..<count).map { index in
            if let known = seed[index] { return known }
            let radius = 9 * (0.5 + Double(index)).squareRoot()
            let angle = Double(index) * .pi * (3 - 5.0.squareRoot())
            return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
        velocities = Array(repeating: .zero, count: count)
        var degrees = Array(repeating: 0, count: count)
        for link in links {
            degrees[link.a] += 1
            degrees[link.b] += 1
        }
        self.degrees = degrees
    }

    /// Advances the layout one tick and cools it.
    mutating func step() {
        let count = positions.count
        guard count > 0, !settled else { return }
        var force = Array(repeating: CGVector.zero, count: count)
        let tree = QuadTree(positions)
        for i in 0..<count {
            force[i] = tree.push(on: i, positions: positions, strength: repulsion * alpha, reach: reach, theta: theta)
        }

        for link in links where link.a != link.b {
            let x = positions[link.b].x - positions[link.a].x
            let y = positions[link.b].y - positions[link.a].y
            let distance = max((x * x + y * y).squareRoot(), 0.01)
            let strength = 0.6 / Double(min(degrees[link.a], degrees[link.b]))
            let pull = (distance - linkLength) / distance * strength * alpha
            let share = Double(degrees[link.a]) / Double(degrees[link.a] + degrees[link.b])
            force[link.a].dx += x * pull * (1 - share)
            force[link.a].dy += y * pull * (1 - share)
            force[link.b].dx -= x * pull * share
            force[link.b].dy -= y * pull * share
        }

        for index in 0..<count {
            force[index].dx -= positions[index].x * gravity * alpha
            force[index].dy -= positions[index].y * gravity * alpha
            velocities[index].dx = (velocities[index].dx + force[index].dx) * friction
            velocities[index].dy = (velocities[index].dy + force[index].dy) * friction
            positions[index].x += velocities[index].dx
            positions[index].y += velocities[index].dy
        }
        alpha *= cooling
    }

    /// The smallest rectangle around every node.
    var bounds: CGRect {
        guard let first = positions.first else { return .zero }
        return positions.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}

/// A Barnes–Hut quadtree over the layout's points: each cell knows its mass
/// and center of mass, so a cell far enough away pushes as one body.
private struct QuadTree {
    private struct Cell {
        var minX: Double
        var minY: Double
        var size: Double
        var mass: Double = 0
        var x: Double = 0
        var y: Double = 0
        /// The point a leaf holds, or -1.
        var point = -1
        /// Index of the first of four children, or -1 for a leaf.
        var children = -1
    }

    /// Cells this small stop splitting and hold coincident points together.
    private static let smallest = 1e-3
    private var cells: [Cell] = []

    init(_ positions: [CGPoint]) {
        guard let first = positions.first else { return }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in positions {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        cells.reserveCapacity(positions.count * 3)
        cells.append(Cell(minX: minX, minY: minY, size: max(maxX - minX, maxY - minY, 1) * 1.01))
        for index in positions.indices { insert(index, positions) }
        summarize(0, positions)
    }

    /// The push on point `i` from every other point within `reach`.
    func push(on i: Int, positions: [CGPoint], strength: Double, reach: Double, theta: Double) -> CGVector {
        guard !cells.isEmpty else { return .zero }
        let p = positions[i]
        var fx = 0.0
        var fy = 0.0
        var stack = [0]
        while let at = stack.popLast() {
            let cell = cells[at]
            let isLeaf = cell.children < 0
            let mass = isLeaf && cell.point == i ? cell.mass - 1 : cell.mass
            guard mass > 0 else { continue }
            var dx = p.x - cell.x
            var dy = p.y - cell.y
            var squared = dx * dx + dy * dy
            if !isLeaf && cell.size * cell.size >= theta * theta * squared {
                stack.append(contentsOf: cell.children..<(cell.children + 4))
                continue
            }
            guard squared < reach * reach else { continue }
            if squared == 0 {
                dx = Double(i % 13 + 1) * 0.01
                dy = Double(i % 11 + 1) * 0.01
                squared = dx * dx + dy * dy
            }
            let distance = squared.squareRoot()
            let force = strength * mass / max(squared, 25)
            fx += dx / distance * force
            fy += dy / distance * force
        }
        return CGVector(dx: fx, dy: fy)
    }

    private mutating func insert(_ index: Int, _ positions: [CGPoint]) {
        let point = positions[index]
        var at = 0
        while true {
            if cells[at].children >= 0 {
                at = child(of: at, for: point)
            } else if cells[at].mass == 0 {
                cells[at].point = index
                cells[at].mass = 1
                return
            } else if cells[at].size < Self.smallest {
                cells[at].mass += 1
                return
            } else {
                let resident = cells[at].point
                cells[at].point = -1
                cells[at].mass = 0
                split(at)
                let home = child(of: at, for: positions[resident])
                cells[home].point = resident
                cells[home].mass = 1
                at = child(of: at, for: point)
            }
        }
    }

    private mutating func split(_ at: Int) {
        let half = cells[at].size / 2
        let x = cells[at].minX
        let y = cells[at].minY
        cells[at].children = cells.count
        cells.append(Cell(minX: x, minY: y, size: half))
        cells.append(Cell(minX: x + half, minY: y, size: half))
        cells.append(Cell(minX: x, minY: y + half, size: half))
        cells.append(Cell(minX: x + half, minY: y + half, size: half))
    }

    private func child(of at: Int, for point: CGPoint) -> Int {
        let half = cells[at].size / 2
        let right = point.x >= cells[at].minX + half ? 1 : 0
        let lower = point.y >= cells[at].minY + half ? 2 : 0
        return cells[at].children + right + lower
    }

    /// Fills in each cell's mass and center of mass from its children.
    private mutating func summarize(_ at: Int, _ positions: [CGPoint]) {
        let first = cells[at].children
        guard first >= 0 else {
            if cells[at].point >= 0 {
                cells[at].x = positions[cells[at].point].x
                cells[at].y = positions[cells[at].point].y
            }
            return
        }
        var mass = 0.0
        var x = 0.0
        var y = 0.0
        for child in first..<(first + 4) {
            summarize(child, positions)
            mass += cells[child].mass
            x += cells[child].x * cells[child].mass
            y += cells[child].y * cells[child].mass
        }
        cells[at].mass = mass
        if mass > 0 {
            cells[at].x = x / mass
            cells[at].y = y / mass
        }
    }
}

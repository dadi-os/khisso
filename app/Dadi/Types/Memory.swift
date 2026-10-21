import Foundation

/// One live node of Yaad's memory network from POST /graph.
struct MemoryNode: Decodable, Sendable, Hashable, Identifiable {
    /// What a node is about.
    enum Kind: String, Decodable, Sendable, CaseIterable {
        case person
        case memory
        case plan
        case place
    }

    let id: String
    let kind: Kind
    let title: String
    let body: String?
    let occurredAt: Date?
    let accessCount: Int
    /// The Hath agent that made it, if an agent did.
    let agentId: String?
    let createdAt: Date
}

/// A current, directed edge between two live nodes.
struct MemoryEdge: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let srcId: String
    let dstId: String
    let type: String
}

/// POST /graph without seeds: every live node and every current edge between them.
struct MemoryGraph: Decodable, Sendable {
    let nodes: [MemoryNode]
    let edges: [MemoryEdge]
}

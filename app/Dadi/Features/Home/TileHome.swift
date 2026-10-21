#if os(macOS)
import SwiftUI

/// The Mac's Home, as thaali's: a four by four grid of live tiles, each
/// opening its page. Agents and Timeline take two by two, Memory and Ghar two
/// by one, Chaavi and System one by two. The tiles rise in one after another.
struct TileHome: View {
    let services: Services
    /// Agents with a lane running, from Hath's live events.
    let running: Set<String>
    let open: (HomeView.Page) -> Void

    @State private var appeared = false

    private let gap: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let unit = CGSize(width: (proxy.size.width - gap * 3) / 4, height: (proxy.size.height - gap * 3) / 4)
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    tile("Agents", .agents, order: 0) { AgentsTile(hath: services.hath, running: running) }
                    tile("Timeline", .timeline, order: 1) { TodayTile(yaad: services.yaad) }
                }
                .frame(height: unit.height * 2 + gap)
                HStack(spacing: gap) {
                    VStack(spacing: gap) {
                        tile("Memory", .memory, order: 2) { MemoryTile(yaad: services.yaad) }
                        tile("Ghar", .ghar, order: 3) { GharTile(ghar: services.ghar) }
                    }
                    .frame(width: unit.width * 2 + gap)
                    tile("Chaavi", .chaavi, order: 4) { ChaaviTile(chaavi: services.chaavi) }
                    tile("System", .system, order: 5) { SystemTile(nas: services.nas) }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
        .navigationTitle("Home")
        .onAppear { appeared = true }
    }

    private func tile<Content: View>(_ title: String, _ page: HomeView.Page, order: Int, @ViewBuilder content: () -> Content) -> some View {
        Tile(title: title, action: { open(page) }, content: content())
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .scaleEffect(appeared ? 1 : 0.97)
            .animation(Motion.settle.delay(Double(order) * 0.07), value: appeared)
    }
}

/// A Home tile: its name in small capitals over live content, lifting under
/// the pointer and pressing in when clicked.
private struct Tile<Content: View>: View {
    let title: String
    let action: () -> Void
    let content: Content

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(.inkFaint)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.sageDeep)
                        .opacity(hovering ? 1 : 0)
                        .offset(x: hovering ? 0 : -4, y: hovering ? 0 : 4)
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.boneRaised.opacity(hovering ? 0.92 : 0.72), in: .rect(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(hovering ? Color.sageLine : .rule, lineWidth: 1))
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .contentShape(.rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(TilePress())
        .shadow(color: .ink.opacity(hovering ? 0.12 : 0.04), radius: hovering ? 24 : 8, y: hovering ? 12 : 3)
        .offset(y: hovering ? -2 : 0)
        .onHover { hovering = $0 }
        .animation(Motion.snap, value: hovering)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
    }
}

/// A tile pressing in a little while held.
private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

/// Polls `load` every `every` while the tile is on screen.
@MainActor
private func poll(every: Duration, _ load: @MainActor () async -> Void) async {
    while !Task.isCancelled {
        await load()
        do { try await Task.sleep(for: every) } catch { return }
    }
}

/// A tile's quiet line for a failed load.
private struct TileProblem: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.danger)
            .lineLimit(3)
    }
}

/// The agent graph, small and still, with how many agents there are and how
/// many are working.
private struct AgentsTile: View {
    let hath: HathClient
    let running: Set<String>

    @State private var agents: [AgentRecord] = []
    @State private var problem: String?

    var body: some View {
        let active = agents.filter(\.active)
        let working = active.filter { $0.isRunning || running.contains($0.id) }.count
        ZStack(alignment: .bottomLeading) {
            AgentGraph(agents: active, running: running, selection: .constant(nil), interactive: false)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(active.count)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.ink)
                    .contentTransition(.numericText())
                Text(working > 0 ? "agents · \(working) working" : "agents")
                    .font(.subheadline)
                    .foregroundStyle(working > 0 ? Color.sageText : .inkMuted)
            }
            .animation(Motion.settle, value: working)
            if let problem { TileProblem(message: problem) }
        }
        .task {
            await poll(every: .seconds(5)) {
                do {
                    agents = try await hath.agents()
                    problem = nil
                } catch is CancellationError {
                    return
                } catch {
                    problem = error.localizedDescription
                }
            }
        }
    }
}

/// Today's plan: the date, what is happening now, and the day's blocks in
/// order, done and past ones faded.
private struct TodayTile: View {
    let yaad: YaadClient

    @State private var blocks: [PlannerBlock] = []
    @State private var loaded = false
    @State private var problem: String?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 14) {
                Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.ink)
                if let problem {
                    TileProblem(message: problem)
                } else if loaded && blocks.isEmpty {
                    Text("Nothing planned today.").font(.callout).foregroundStyle(.inkMuted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(blocks) { block in
                        let current = block.startAt <= now && now < block.endAt
                        let settled = PlannerLayout.isSettled(block, now: now)
                        HStack(spacing: 12) {
                            Image(systemName: block.doneAt != nil ? "checkmark.circle.fill" : PlannerLayout.symbol(block.icon))
                                .font(.callout)
                                .foregroundStyle(current ? Color.bone : .sageDeep)
                                .frame(width: 30, height: 30)
                                .background(current ? AnyShapeStyle(Color.sageDeep) : AnyShapeStyle(Color.sage.opacity(0.14)), in: .circle)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(block.title)
                                    .font(.subheadline.weight(current ? .semibold : .medium))
                                    .foregroundStyle(.ink)
                                    .lineLimit(1)
                                Text("\(block.startAt.formatted(date: .omitted, time: .shortened)) – \(block.endAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.inkMuted)
                            }
                            Spacer(minLength: 0)
                            if current {
                                Text("Now")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.sageText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.sage.opacity(0.18), in: .capsule)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(current ? Color.sage.opacity(0.1) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
                        .opacity(settled && !current ? 0.45 : 1)
                    }
                }
            }
        }
        .task {
            await poll(every: .seconds(30)) {
                let start = Calendar.current.startOfDay(for: .now)
                guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
                do {
                    blocks = try await yaad.planner(from: start, to: end).sorted { $0.startAt < $1.startAt }
                    problem = nil
                } catch is CancellationError {
                    return
                } catch {
                    problem = error.localizedDescription
                }
                loaded = true
            }
        }
    }
}

/// How many people, memories, plans and places Yaad holds.
private struct MemoryTile: View {
    let yaad: YaadClient

    @State private var counts: [MemoryNode.Kind: Int] = [:]
    @State private var problem: String?

    var body: some View {
        if let problem {
            TileProblem(message: problem)
        }
        HStack(spacing: 0) {
            ForEach(MemoryNode.Kind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: MemoryStyle.symbol(kind))
                        .font(.caption)
                        .foregroundStyle(MemoryStyle.color(kind))
                    Text("\(counts[kind] ?? 0)")
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.ink)
                        .contentTransition(.numericText())
                    Text(MemoryStyle.plural(kind))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(Motion.settle, value: counts)
        .task {
            await poll(every: .seconds(60)) {
                do {
                    let graph = try await yaad.graph()
                    counts = Dictionary(grouping: graph.nodes, by: \.kind).mapValues(\.count)
                    problem = nil
                } catch is CancellationError {
                    return
                } catch {
                    problem = error.localizedDescription
                }
            }
        }
    }
}

/// How many lights are on, and each room's devices as dots that glow when on.
private struct GharTile: View {
    let ghar: GharClient

    @State private var devices: [GharDevice] = []
    @State private var problem: String?

    var body: some View {
        let switchable = devices.filter { $0.isOn != nil }
        let on = switchable.filter { $0.isOn == true }
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(on.count)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.ink)
                    .contentTransition(.numericText())
                Text("of \(switchable.count) on").font(.caption.weight(.medium)).foregroundStyle(.inkMuted)
            }
            if let problem {
                TileProblem(message: problem)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(rooms, id: \.room.id) { room in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(room.room.name).font(.caption.weight(.semibold)).foregroundStyle(.ink).lineLimit(1)
                            HStack(spacing: 6) {
                                ForEach(room.devices) { device in
                                    let lit = device.isOn == true
                                    Image(systemName: GharStyle.symbol(device.kind, on: lit))
                                        .font(.caption)
                                        .foregroundStyle(lit ? GharStyle.glow(device) : .inkFaint)
                                        .shadow(color: lit ? GharStyle.glow(device).opacity(0.7) : .clear, radius: 5)
                                        .help(device.name)
                                }
                            }
                        }
                        .padding(10)
                        .background(.bone.opacity(0.6), in: .rect(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .animation(Motion.settle, value: on.count)
        .task {
            await poll(every: .seconds(4)) {
                do {
                    devices = try await ghar.devices()
                    problem = nil
                } catch is CancellationError {
                    return
                } catch {
                    problem = error.localizedDescription
                }
            }
        }
    }

    private var rooms: [(room: GharRoom, devices: [GharDevice])] {
        Dictionary(grouping: devices, by: \.room)
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.room.name < $1.room.name }
    }
}

/// The vault by count only: logins, other secrets, one-time codes, and its
/// top-level folders. Never a secret value.
private struct ChaaviTile: View {
    let chaavi: ChaaviClient

    @State private var items: [ChaaviItem] = []
    @State private var folders: [ChaaviFolder] = []
    @State private var problem: String?

    var body: some View {
        let logins = items.filter { $0.type == "login" }
        VStack(alignment: .leading, spacing: 16) {
            if let problem {
                TileProblem(message: problem)
            }
            count(logins.count, "Passwords", symbol: "key.fill")
            count(items.count - logins.count, "Other secrets", symbol: "lock.doc.fill")
            count(logins.filter { $0.login?.hasTotp == true }.count, "One-time codes", symbol: "clock.badge.checkmark")
            Rectangle().fill(.rule).frame(height: 1)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(FolderTree.children(of: nil, folders: folders, items: items).prefix(6)) { folder in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").font(.caption2).foregroundStyle(.sageDeep)
                        Text(folder.name).font(.caption.weight(.medium)).foregroundStyle(.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(folder.count)").font(.caption.monospacedDigit()).foregroundStyle(.inkFaint)
                    }
                }
            }
        }
        .animation(Motion.settle, value: items.count)
        .task {
            await poll(every: .seconds(60)) {
                do {
                    async let nextItems = chaavi.items()
                    async let nextFolders = chaavi.folders()
                    (items, folders) = try await (nextItems, nextFolders)
                    problem = nil
                } catch is CancellationError {
                    return
                } catch {
                    problem = error.localizedDescription
                }
            }
        }
    }

    private func count(_ value: Int, _ title: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.sageDeep).frame(width: 16)
            Text("\(value)")
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.ink)
                .contentTransition(.numericText())
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.inkMuted)
        }
    }
}

/// The box's health and its processor, memory and disk as rings.
private struct SystemTile: View {
    let nas: NasClient

    @State private var status: NasStatus?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let problem {
                TileProblem(message: problem)
            }
            if let status {
                let healthy = status.services.allSatisfy(\.healthy)
                Label(healthy ? "Healthy" : "\(status.services.filter { !$0.healthy }.count) down", systemImage: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(healthy ? Color.sageDeep : .danger)
                    .symbolEffect(.bounce, value: healthy)
                VStack(spacing: 14) {
                    Ring(title: "CPU", percent: status.cpu.usedPercent, diameter: 58)
                    Ring(title: "Memory", percent: status.memory.usedPercent, diameter: 58)
                    Ring(title: "Disk", percent: status.disk.usedPercent, diameter: 58)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            await poll(every: .seconds(2)) {
                do {
                    status = try await nas.status()
                    problem = nil
                } catch is CancellationError {
                    return
                } catch {
                    problem = error.localizedDescription
                }
            }
        }
    }
}
#endif

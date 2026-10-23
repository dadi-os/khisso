import SwiftUI

/// One room: a brightness slab for the whole room with its switch, its lights,
/// the groups among them, and renaming the room or moving lights into it.
/// The "…" menu also deletes the room; Ghar refuses while devices are still
/// in it, and the page says so.
struct RoomPage: View {
    let store: GharStore
    let roomId: String

    @Environment(\.dismiss) private var dismiss
    @State private var focused: GharDevice?
    @State private var filling = false
    @State private var grouping = false
    @State private var renaming = false
    @State private var deleting = false
    @State private var name = ""
    @State private var switched = 0

    var body: some View {
        let room = store.room(roomId)
        let devices = room.map { room in GharLayout.sections(store.devices, rooms: [room]).first?.devices ?? [] } ?? []
        let placed = room.map { $0.name != GharLayout.unassigned } ?? false
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !devices.isEmpty {
                    RoomSlab(devices: devices) { on in
                        store.setOn(on, devices)
                    } commit: { level in
                        store.setLevel(level, devices)
                    }
                    .padding(.top, 14)
                    Text("Drag up or down to set every light in the room at once.")
                        .font(.system(size: 12))
                        .foregroundStyle(.inkMuted)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                }
                if let problem = store.problem {
                    HStack(alignment: .top) {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.danger)
                        Spacer()
                        Button { withAnimation(Motion.snap) { store.problem = nil } } label: {
                            Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                    .padding(.top, 16)
                }
                heading("Lights")
                    .padding(.top, 22)
                if devices.isEmpty {
                    Text("No lights here yet. Move some in.")
                        .font(.system(size: 15))
                        .foregroundStyle(.inkMuted)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(devices) { device in
                        LightTile(device: device, height: 116)
                            .onTapGesture {
                                guard device.online, device.has("on_off") else {
                                    focused = device
                                    return
                                }
                                switched += 1
                                store.toggle(device)
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                switched += 1
                                focused = device
                            }
                    }
                }
                .animation(Motion.settle, value: devices.map(\.id))
                if !devices.isEmpty {
                    heading("Groups here")
                        .padding(.top, 24)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(GharLayout.groups(devices)) { group in
                                groupChip(group)
                            }
                            Button { grouping = true } label: {
                                GharChip(title: "New group", dashed: true, height: 38)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background { FieldBloom() }
        .safeAreaBar(edge: .top) { topBar(room: room, placed: placed) }
        .safeAreaBar(edge: .bottom) {
            if let room, placed {
                HStack(spacing: 10) {
                    Button { name = room.name; renaming = true } label: {
                        Text("Rename room").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GharButtonStyle(height: 46))
                    Button { filling = true } label: {
                        Text("Move lights here").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GharButtonStyle(prominent: true, height: 46))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: switched)
        .sheet(item: $focused) { device in
            LightSheet(store: store, deviceId: device.id)
                .fittedSheet()
                .presentationBackground(Color.boneRaised)
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $filling) {
            if let room {
                DevicePicker(store: store, title: "Move lights here", action: "Move here", devices: store.devices.filter { $0.room.id != room.id }) { _, chosen in
                    await store.move(chosen, to: room)
                }
                .fittedSheet()
                .presentationBackground(Color.boneRaised)
            }
        }
        .sheet(isPresented: $grouping) {
            DevicePicker(store: store, title: "New group", action: "Make group", devices: devices, naming: "Group name, like Nightstands") { name, chosen in
                await store.addGroup(name, to: chosen)
            }
            .fittedSheet()
            .presentationBackground(Color.boneRaised)
        }
        .alert("Rename room", isPresented: $renaming) {
            TextField("Room name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let next = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let room, !next.isEmpty, next != room.name else { return }
                Task { await store.rename(room, to: next) }
            }
        }
        .confirmationDialog("Delete \(room?.name ?? "")?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete room", role: .destructive) {
                guard let room else { return }
                Task { await store.delete(room) }
            }
        } message: {
            Text(devices.isEmpty ? "The room has no devices." : "Ghar only deletes an empty room. Move its \(devices.count == 1 ? "device" : "\(devices.count) devices") out first.")
        }
        .onChange(of: room == nil) { _, gone in
            if gone && store.loaded { dismiss() }
        }
    }

    private func topBar(room: GharRoom?, placed: Bool) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Back to Ghar")
            Spacer()
            if let room {
                NameBubble(title: GharLayout.name(of: room))
            }
            Spacer()
            Menu {
                Button("Rename room", systemImage: "pencil") {
                    name = room?.name ?? ""
                    renaming = true
                }
                Button("Move lights here", systemImage: "arrow.down.to.line") { filling = true }
                Divider()
                Button("Delete room", systemImage: "trash", role: .destructive) { deleting = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .opacity(placed ? 1 : 0)
            .disabled(!placed)
            .accessibilityLabel("Room options")
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.inkMuted)
            .padding(.bottom, 10)
    }

    /// A group's chip: its name and how many of its lights are here. Tapping
    /// it switches those lights, and its mark glows in their light while any
    /// is on.
    private func groupChip(_ group: GharGroup) -> some View {
        let summary = GharLayout.summary(group.devices)
        return Button {
            switched += 1
            store.setOn(summary.on == 0, group.devices)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "circle.grid.2x1")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(summary.color.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(Color.sageDeep))
                Text("\(group.name) · \(group.devices.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.sageDeep)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Color.bone, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.sageLine.opacity(0.7), lineWidth: 1))
            .animation(Motion.snap, value: summary.on)
        }
        .buttonStyle(.plain)
        .accessibilityValue(GharLayout.status(summary))
        .accessibilityHint("Switches the group's lights in this room")
    }
}

/// The room's brightness as a tall slab that fills from the bottom in the
/// room's mixed light. Dragging up or down sets every light; it follows the
/// finger and sends the level when let go.
private struct RoomSlab: View {
    let devices: [GharDevice]
    let switchRoom: (Bool) -> Void
    let commit: (Int) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var dragging: Double?

    var body: some View {
        let summary = GharLayout.summary(devices)
        let lit = summary.on > 0 || dragging != nil
        let light = summary.color ?? .white(kelvin: 2700)
        let level = dragging ?? Double(summary.on > 0 ? summary.level ?? 100 : 0)
        let tinted = lit && scheme == .light
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.rule)
                Rectangle()
                    .fill(scheme == .dark ? light.color.opacity(0.6) : light.mixed(with: .white, by: 0.35).color)
                    .frame(height: proxy.size.height * level / 100)
                VStack(alignment: .leading) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GharLayout.status(summary))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(tinted ? light.mixed(with: .black, by: 0.65).color : Color.ink)
                                .contentTransition(.numericText())
                            if let colors = GharLayout.colorNames(devices) {
                                Text(colors)
                                    .font(.system(size: 13))
                                    .foregroundStyle(tinted ? light.mixed(with: .black, by: 0.52).color : Color.inkMuted)
                            }
                        }
                        Spacer()
                        if summary.total > 0 {
                            GharSwitch(isOn: summary.on > 0, label: "Switch the whole room") { switchRoom(summary.on == 0) }
                        }
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(lit ? "\(Int(level))%" : "Off")
                            .font(.system(size: 52, weight: .bold))
                            .tracking(-1.5)
                            .foregroundStyle(tinted ? GharInk.deep(light) : Color.ink)
                            .contentTransition(.numericText())
                        if lit {
                            Text("brightness")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(tinted ? light.mixed(with: .black, by: 0.6).color : Color.inkMuted)
                        }
                    }
                }
                .padding(20)
            }
            .clipShape(shape)
            .contentShape(shape)
            .animation(dragging == nil ? Motion.settle : nil, value: level)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag in dragging = min(100, max(1, (1 - drag.location.y / proxy.size.height) * 100)) }
                    .onEnded { _ in
                        if let dragging { commit(Int(dragging.rounded())) }
                        dragging = nil
                    }
            )
        }
        .frame(height: 176)
        .sensoryFeedback(.selection, trigger: Int(level / 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room brightness")
        .accessibilityValue(summary.on > 0 ? "\(Int(level)) percent" : "Off")
        .accessibilityAdjustableAction { direction in
            commit(Int(min(100, max(1, level + (direction == .increment ? 10 : -10)))))
        }
    }
}

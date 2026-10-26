import SwiftUI

/// Ghar: what is on at a glance, All off and Evening, chips to narrow to a
/// room or a group (the drawer narrows it too), then each room on the field
/// with its switch, its brightness and its lights as tiles. Tap a tile to
/// switch it, hold it for the light sheet, tap a room's name for the room
/// page. The page reads Ghar again whenever Ghar announces a change, so
/// changes made elsewhere show up at once.
struct GharPage: View {
    /// What the chips narrow the page to.
    enum Filter: Hashable {
        case everywhere
        case room(String)
        case group(String)
    }

    let store: GharStore
    /// What the page is narrowed to, shared with the drawer.
    @Binding var filter: Filter

    @Environment(LiveData.self) private var live
    @State private var focused: GharDevice?
    @State private var opened: GharRoom?
    @State private var filling: GharRoom?
    @State private var naming = false
    @State private var roomName = ""
    @State private var switched = 0
    @Namespace private var zoom
    @Namespace private var chip

    var body: some View {
        let sections = GharLayout.sections(store.devices, rooms: store.rooms)
        let groups = GharLayout.groups(store.devices)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(GharLayout.headline(GharLayout.summary(store.devices)))
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(.ink)
                        .contentTransition(.numericText())
                    Text(GharLayout.whereabouts(sections))
                        .font(.system(size: 15))
                        .foregroundStyle(.inkMuted)
                }
                .padding(.top, 18)
                .padding(.bottom, 6)
                .animation(Motion.snap, value: store.devices)

                HStack(spacing: 8) {
                    Button("All off") {
                        switched += 1
                        store.setOn(false, store.devices)
                    }
                    Button {
                        switched += 1
                        store.evening()
                    } label: {
                        Label {
                            Text("Evening")
                        } icon: {
                            Image(systemName: "moon").foregroundStyle(Color(red: 0.722, green: 0.420, blue: 0.180))
                        }
                    }
                }
                .buttonStyle(GharButtonStyle())
                .padding(.top, 14)
                .padding(.bottom, 4)

                chips(sections: sections, groups: groups)
                    .padding(.top, 16)

                if let error = store.error {
                    notice(error)
                }
                if let problem = store.problem {
                    notice(problem) { withAnimation(Motion.snap) { store.problem = nil } }
                }

                switch filter {
                case .group(let name):
                    if let group = groups.first(where: { $0.name == name }) {
                        groupSection(group)
                    }
                case .room(let id):
                    ForEach(sections.filter { $0.id == id }) { roomSection($0) }
                case .everywhere:
                    ForEach(sections) { roomSection($0) }
                }

                if store.loaded && sections.isEmpty && store.error == nil {
                    ContentUnavailableView("No devices yet", systemImage: "house", description: Text("Add devices from the Ghar page on your Mac or the box."))
                        .foregroundStyle(.inkMuted)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.load() }
        .sensoryFeedback(.impact(weight: .medium), trigger: switched)
        .sheet(item: $focused) { device in
            LightSheet(store: store, deviceId: device.id)
                .fittedSheet()
                .presentationBackground(Color.boneRaised)
                .presentationCornerRadius(34)
        }
        .sheet(item: $filling) { room in
            DevicePicker(store: store, title: "Move lights to \(room.name)", action: "Move here", devices: store.devices.filter { $0.room.id != room.id }) { _, chosen in
                await store.move(chosen, to: room)
            }
            .fittedSheet()
            .presentationBackground(Color.boneRaised)
        }
        .fullScreenCover(item: $opened) { room in
            RoomPage(store: store, roomId: room.id)
                .navigationTransition(.zoom(sourceID: room.id, in: zoom))
        }
        .alert("New room", isPresented: $naming) {
            TextField("Room name", text: $roomName)
            Button("Cancel", role: .cancel) { roomName = "" }
            Button("Make room") {
                let name = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
                roomName = ""
                guard !name.isEmpty else { return }
                Task { await store.createRoom(named: name) }
            }
        }
        .onChange(of: store.rooms) {
            if case .room(let id) = filter, store.room(id) == nil { filter = .everywhere }
        }
        .task(id: live.ghar) { await store.load() }
    }

    private func chips(sections: [GharSection], groups: [GharGroup]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chipButton(.everywhere, title: "Everywhere")
                ForEach(sections) { section in
                    chipButton(.room(section.id), title: GharLayout.name(of: section.room))
                        .contextMenu {
                            Button("Open room", systemImage: "arrow.up.left.and.arrow.down.right") { opened = section.room }
                        }
                }
                ForEach(groups) { group in
                    chipButton(.group(group.name), title: group.name, symbol: "circle.grid.2x1")
                        .contextMenu {
                            Button("Turn on", systemImage: "lightbulb.fill") { switched += 1; store.setOn(true, group.devices) }
                            Button("Turn off", systemImage: "lightbulb") { switched += 1; store.setOn(false, group.devices) }
                        }
                }
                Button {
                    naming = true
                } label: {
                    GharChip(title: "New room", symbol: "plus", dashed: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }

    private func chipButton(_ target: Filter, title: String, symbol: String? = nil) -> some View {
        let selected = filter == target
        return Button {
            withAnimation(Motion.snap) { filter = target }
        } label: {
            GharChip(title: title, symbol: symbol, selected: selected)
                .background {
                    if selected { Capsule().fill(Color.sageDeep).matchedGeometryEffect(id: "chip", in: chip) }
                }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }

    /// A room on the field: its name (which opens the room page), what is on,
    /// its switch, its brightness and its tiles, ending with a tile that
    /// moves lights in.
    private func roomSection(_ section: GharSection) -> some View {
        let summary = GharLayout.summary(section.devices)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { opened = section.room } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(GharLayout.name(of: section.room))
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(.ink)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.inkFaint)
                        }
                        Text(GharLayout.status(summary))
                            .font(.system(size: 13))
                            .foregroundStyle(.inkMuted)
                            .contentTransition(.numericText())
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: section.id, in: zoom)
                .accessibilityHint("Opens the room")
                Spacer()
                if summary.total > 0 {
                    GharSwitch(isOn: summary.on > 0, label: "Switch \(GharLayout.name(of: section.room))") {
                        store.setOn(summary.on == 0, section.devices)
                    }
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 10)
            if section.devices.contains(where: { $0.has("level") }) {
                LevelBar(summary: summary) { store.setLevel($0, section.devices) }
                    .padding(.bottom, 14)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(section.devices) { tile($0) }
                if section.placed {
                    Button { filling = section.room } label: { addTile }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add lights to \(section.room.name)")
                }
            }
            .animation(Motion.settle, value: section.devices.map(\.id))
        }
    }

    /// A group on the field when its chip is chosen: its lights from every
    /// room, with a switch and brightness for all of them.
    private func groupSection(_ group: GharGroup) -> some View {
        let summary = GharLayout.summary(group.devices)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.ink)
                    Text(GharLayout.status(summary))
                        .font(.system(size: 13))
                        .foregroundStyle(.inkMuted)
                        .contentTransition(.numericText())
                }
                Spacer()
                if summary.total > 0 {
                    GharSwitch(isOn: summary.on > 0, label: "Switch \(group.name)") {
                        store.setOn(summary.on == 0, group.devices)
                    }
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 10)
            if group.devices.contains(where: { $0.has("level") }) {
                LevelBar(summary: summary) { store.setLevel($0, group.devices) }
                    .padding(.bottom, 14)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(group.devices) { tile($0) }
            }
        }
    }

    private func tile(_ device: GharDevice) -> some View {
        LightTile(device: device)
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
            .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private var addTile: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
            Text("Add lights").font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.sageDeep)
        .frame(maxWidth: .infinity, minHeight: 124)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.sageLine, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .contentShape(.rect(cornerRadius: 26))
    }

    private func notice(_ text: String, dismiss: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top) {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.danger)
            Spacer()
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.top, 16)
        .transition(.opacity)
    }
}

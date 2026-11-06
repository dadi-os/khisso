import SwiftUI

/// Ghar: what is on at a glance, All off and Evening, chips to narrow to a tag
/// (the drawer narrows it too), then the chosen tag on the field with its
/// switch, its brightness and its lights as tiles. A device carries any number
/// of tags and shows under each. Tap a tile to switch it, hold it for the
/// light sheet, tap a tag's name for the tag page. The page reads Ghar again
/// whenever Ghar announces a change, so changes made elsewhere show up at
/// once.
struct GharPage: View {
    /// What the chips narrow the page to. A tag is held by its id, which
    /// survives a rename.
    enum Filter: Hashable {
        case everywhere
        case tag(String)
        case untagged
    }

    let store: GharStore
    /// What the page is narrowed to, shared with the drawer.
    @Binding var filter: Filter

    @Environment(LiveData.self) private var live
    @State private var focused: GharDevice?
    @State private var opened: GharDevice.Tag?
    @State private var filling: GharDevice.Tag?
    @State private var naming = false
    @State private var switched = 0
    @Namespace private var zoom
    @Namespace private var chip

    var body: some View {
        let tags = GharLayout.tags(store.devices)
        let loose = GharLayout.untagged(store.devices)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(GharLayout.headline(GharLayout.summary(store.devices)))
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(.ink)
                        .contentTransition(.numericText())
                    Text(GharLayout.whereabouts(store.devices))
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

                chips(tags: tags, hasUntagged: !loose.isEmpty)
                    .padding(.top, 16)

                if let error = store.error {
                    notice(error)
                }
                if let problem = store.problem {
                    notice(problem) { withAnimation(Motion.snap) { store.problem = nil } }
                }

                switch filter {
                case .tag(let id):
                    if let set = tags.first(where: { $0.id == id }) {
                        field(title: set.name, devices: set.devices, tag: set.tag)
                    }
                case .untagged:
                    field(title: "Untagged", devices: loose, tag: nil)
                case .everywhere:
                    field(title: "Everywhere", devices: store.devices, tag: nil)
                }

                if !store.loaded && store.error == nil {
                    SkeletonRows(count: 4, height: 132)
                }
                if store.loaded && store.devices.isEmpty && store.error == nil {
                    EmptyState(title: "No devices yet", detail: "Add devices from the Ghar page on your Mac or the box.")
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
        .sheet(item: $filling) { tag in
            DevicePicker(store: store, title: "Add lights to \(tag.name)", action: "Add", devices: store.devices.filter { !$0.tags.contains(tag) }) { _, chosen in
                await store.addTag(tag.name, to: chosen)
            }
            .fittedSheet()
            .presentationBackground(Color.boneRaised)
        }
        .sheet(isPresented: $naming) {
            DevicePicker(store: store, title: "New tag", action: "Make tag", devices: store.devices, naming: "Tag name, like Ankur's bed lights") { name, chosen in
                await store.addTag(name, to: chosen)
            }
            .fittedSheet()
            .presentationBackground(Color.boneRaised)
        }
        .fullScreenCover(item: $opened) { tag in
            TagPage(store: store, tagId: tag.id)
                .navigationTransition(.zoom(sourceID: tag.id, in: zoom))
        }
        .onChange(of: store.devices) {
            switch filter {
            case .tag(let id): if store.tag(id) == nil { filter = .everywhere }
            case .untagged: if GharLayout.untagged(store.devices).isEmpty { filter = .everywhere }
            case .everywhere: break
            }
        }
        .task(id: live.ghar) { await store.load() }
    }

    private func chips(tags: [GharTagSet], hasUntagged: Bool) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chipButton(.everywhere, title: "Everywhere")
                ForEach(tags) { set in
                    chipButton(.tag(set.id), title: set.name, symbol: "tag")
                        .contextMenu {
                            Button("Open tag", systemImage: "arrow.up.left.and.arrow.down.right") { opened = set.tag }
                            Button("Turn on", systemImage: "lightbulb.fill") { switched += 1; store.setOn(true, set.devices) }
                            Button("Turn off", systemImage: "lightbulb") { switched += 1; store.setOn(false, set.devices) }
                        }
                }
                if hasUntagged && !tags.isEmpty {
                    chipButton(.untagged, title: "Untagged")
                }
                Button {
                    naming = true
                } label: {
                    GharChip(title: "New tag", symbol: "plus", dashed: true)
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

    /// What the chips chose, on the field: its name (a tag's opens the tag
    /// page), what is on, its switch, its brightness and its tiles. A tag ends
    /// with a tile that adds lights to it.
    private func field(title: String, devices: [GharDevice], tag: GharDevice.Tag?) -> some View {
        let summary = GharLayout.summary(devices)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let tag {
                    Button { opened = tag } label: { heading(title, status: summary, chevron: true) }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: tag.id, in: zoom)
                        .accessibilityHint("Opens the tag")
                } else {
                    heading(title, status: summary, chevron: false)
                }
                Spacer()
                if summary.total > 0 {
                    GharSwitch(isOn: summary.on > 0, label: "Switch \(title)") {
                        store.setOn(summary.on == 0, devices)
                    }
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 10)
            if devices.contains(where: { $0.has("level") }) {
                LevelBar(summary: summary) { store.setLevel($0, devices) }
                    .padding(.bottom, 14)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(devices) { tile($0) }
                if let tag {
                    Button { filling = tag } label: { addTile }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a device to \(tag.name)")
                }
            }
            .animation(Motion.settle, value: devices.map(\.id))
        }
    }

    private func heading(_ title: String, status summary: GharSummary, chevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.ink)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.inkFaint)
                }
            }
            Text(GharLayout.status(summary))
                .font(.system(size: 13))
                .foregroundStyle(.inkMuted)
                .contentTransition(.numericText())
        }
        .contentShape(.rect)
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
            Text("Add a device here").font(.system(size: 14, weight: .semibold))
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

import SwiftUI

/// One tag: a brightness slab for every light carrying it with its switch,
/// those lights, the other tags among them, and renaming the tag or adding
/// lights to it. The "…" menu also deletes the tag, which only takes the tag
/// off its lights; they stay.
struct TagPage: View {
    let store: GharStore
    let tagId: String

    @Environment(\.dismiss) private var dismiss
    @State private var focused: GharDevice?
    @State private var filling = false
    @State private var renaming = false
    @State private var deleting = false
    @State private var making = false
    @State private var name = ""
    @State private var switched = 0

    var body: some View {
        let tag = store.tag(tagId)
        let devices = store.devices(tagged: tagId)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !devices.isEmpty {
                    TagSlab(devices: devices) { on in
                        store.setOn(on, devices)
                    } commit: { level in
                        store.setLevel(level, devices)
                    }
                    .padding(.top, 14)
                    Text("Drag up or down to set every light in this tag at once.")
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
                    Text("No lights carry this tag.")
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
                    heading("Also tagged")
                        .padding(.top, 24)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(GharLayout.tags(devices).filter { $0.id != tagId }) { set in
                                tagChip(set)
                            }
                            Button { making = true } label: {
                                GharChip(title: "New tag", dashed: true, height: 38)
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
        .safeAreaBar(edge: .top) { topBar(tag: tag) }
        .safeAreaBar(edge: .bottom) {
            if let tag {
                HStack(spacing: 10) {
                    Button { name = tag.name; renaming = true } label: {
                        Text("Rename tag").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GharButtonStyle(height: 46))
                    Button { filling = true } label: {
                        Text("Add lights").frame(maxWidth: .infinity)
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
            if let tag {
                DevicePicker(store: store, title: "Add lights to \(tag.name)", action: "Add", devices: store.devices.filter { !$0.tags.contains(tag) }) { _, chosen in
                    await store.addTag(tag.name, to: chosen)
                }
                .fittedSheet()
                .presentationBackground(Color.boneRaised)
            }
        }
        .sheet(isPresented: $making) {
            DevicePicker(store: store, title: "New tag", action: "Make tag", devices: devices, naming: "Tag name, like Nightstands") { name, chosen in
                await store.addTag(name, to: chosen)
            }
            .fittedSheet()
            .presentationBackground(Color.boneRaised)
        }
        .alert("Rename tag", isPresented: $renaming) {
            TextField("Tag name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let next = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let tag, !next.isEmpty, next != tag.name else { return }
                Task { await store.rename(tag, to: next) }
            }
        }
        .confirmationDialog("Delete \(tag?.name ?? "")?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete tag", role: .destructive) {
                guard let tag else { return }
                Task { await store.delete(tag) }
            }
        } message: {
            Text("The tag comes off its \(devices.count == 1 ? "device" : "\(devices.count) devices"). The devices stay.")
        }
        .onChange(of: tag == nil) { _, gone in
            if gone && store.loaded { dismiss() }
        }
    }

    private func topBar(tag: GharDevice.Tag?) -> some View {
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
            if let tag {
                NameBubble(title: tag.name)
            }
            Spacer()
            Menu {
                Button("Rename tag", systemImage: "pencil") {
                    name = tag?.name ?? ""
                    renaming = true
                }
                Button("Add lights", systemImage: "plus") { filling = true }
                Divider()
                Button("Delete tag", systemImage: "trash", role: .destructive) { deleting = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Tag options")
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

    /// Another tag among these lights: its name and how many of them carry
    /// it. Tapping it switches those lights, and its mark glows in their
    /// light while any is on.
    private func tagChip(_ set: GharTagSet) -> some View {
        let summary = GharLayout.summary(set.devices)
        return Button {
            switched += 1
            store.setOn(summary.on == 0, set.devices)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(summary.color.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(Color.sageDeep))
                Text("\(set.name) · \(set.devices.count)")
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
        .accessibilityHint("Switches the lights that carry this tag here")
    }
}

/// The tag's brightness as a tall slab that fills from the bottom in the
/// lights' mixed light. Dragging up or down sets every light; it follows the
/// finger and sends the level when let go.
private struct TagSlab: View {
    let devices: [GharDevice]
    let switchTag: (Bool) -> Void
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
                            GharSwitch(isOn: summary.on > 0, label: "Switch the whole tag") { switchTag(summary.on == 0) }
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
        .accessibilityLabel("Tag brightness")
        .accessibilityValue(summary.on > 0 ? "\(Int(level)) percent" : "Off")
        .accessibilityAdjustableAction { direction in
            commit(Int(min(100, max(1, level + (direction == .increment ? 10 : -10)))))
        }
    }
}

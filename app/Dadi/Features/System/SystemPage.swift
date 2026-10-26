import SwiftUI

/// System: the box at a glance. Rings for its processor, memory and disk, how
/// long it has been up, each module's health, every device on dadi but the
/// box, and the latest errors in the logs. The meters and devices refresh
/// every two seconds while open, as in thaali; the slower log read keeps its
/// own pace so it never holds them up. The drawer jumps to a section; holding
/// a module shows its errors or copies its status, holding a device copies
/// its address, and holding an error copies its line.
struct SystemPage: View {
    /// The page's sections, which the drawer jumps to.
    enum Section: String, CaseIterable, Hashable {
        case overview = "Overview"
        case services = "Services"
        case drives = "Drives"
        case devices = "Devices on dadi"
        case errors = "Recent errors"
    }

    let store: SystemStore
    /// The section the drawer asked for; the page scrolls to it and clears it.
    @Binding var focus: Section?

    @State private var opened: NasLogEntry?
    /// The module whose errors the list is narrowed to.
    @State private var errorsFrom: String?
    @State private var copies = 0

    private let refresh: Duration = .seconds(2)
    private let logRefresh: Duration = .seconds(10)

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let problem = store.problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.danger)
                    }
                    if let status = store.status {
                        overview(status)
                            .id(Section.overview)
                        section(.services) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                                ForEach(status.services, id: \.name) { service in
                                    serviceCard(service)
                                        .contextMenu {
                                            Button {
                                                withAnimation(Motion.settle) { errorsFrom = service.name }
                                                focus = .errors
                                            } label: { Label("Show its errors", systemImage: "exclamationmark.bubble") }
                                            Button { copy("\(service.name.capitalized): \(service.healthy ? "healthy" : "down")") } label: { Label("Copy status", systemImage: "doc.on.doc") }
                                        }
                                }
                            }
                        }
                        section(.drives) {
                            VStack(spacing: 10) {
                                ForEach(status.disks, id: \.name) { disk in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(disk.model ?? disk.name).font(.subheadline.weight(.semibold)).foregroundStyle(.ink).lineLimit(1)
                                            Spacer()
                                            Text("\(ByteCountFormatter.string(fromByteCount: disk.freeBytes, countStyle: .file)) free")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.inkMuted)
                                        }
                                        ProgressView(value: disk.usedPercent, total: 100).tint(disk.usedPercent > 85 ? .danger : .sage)
                                        Text(disk.mount).font(.caption2.monospaced()).foregroundStyle(.inkFaint)
                                    }
                                    .padding(14)
                                    .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                    } else if store.problem == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    if !store.devices.isEmpty {
                        section(.devices) {
                            VStack(spacing: 0) {
                                ForEach(store.devices) { device in
                                    deviceRow(device)
                                        .contextMenu {
                                            if let address = device.ipAddresses.first {
                                                Button { copy(address) } label: { Label("Copy address", systemImage: "doc.on.doc") }
                                            }
                                            Button { copy(device.nodeName) } label: { Label("Copy name", systemImage: "textformat") }
                                        }
                                    if device.id != store.devices.last?.id { Rectangle().fill(.rule).frame(height: 1) }
                                }
                            }
                            .padding(.horizontal, 14)
                            .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 16, style: .continuous))
                        }
                    }
                    if !store.errors.isEmpty {
                        section(.errors) {
                            VStack(spacing: 8) {
                                if let errorsFrom {
                                    Button { withAnimation(Motion.settle) { self.errorsFrom = nil } } label: {
                                        Label("From \(errorsFrom.capitalized)", systemImage: "xmark.circle.fill")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.sageText)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(.sage.opacity(0.16), in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel("Show errors from every module")
                                    if shownErrors.isEmpty {
                                        Text("No recent errors from \(errorsFrom.capitalized).")
                                            .font(.footnote)
                                            .foregroundStyle(.inkMuted)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                ForEach(shownErrors, id: \.self) { entry in
                                    errorRow(entry)
                                        .contextMenu {
                                            Button { copy(entry.raw) } label: { Label("Copy line", systemImage: "doc.on.doc") }
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .animation(Motion.settle, value: store.status)
                .animation(Motion.settle, value: errorsFrom)
            }
            .onChange(of: focus) {
                guard let focus else { return }
                withAnimation(Motion.settle) { reader.scrollTo(focus, anchor: .top) }
                self.focus = nil
            }
        }
        .refreshable { await store.load() }
        .sensoryFeedback(.success, trigger: copies)
        .sheet(item: Binding(get: { opened.map(LogSheetItem.init) }, set: { opened = $0?.entry })) { item in
            LogDetail(entry: item.entry)
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
        }
        .navigationTitle("System")
        .task {
            while !Task.isCancelled {
                await store.load()
                do { try await Task.sleep(for: refresh) } catch { return }
            }
        }
        .task {
            while !Task.isCancelled {
                await store.loadErrors()
                do { try await Task.sleep(for: logRefresh) } catch { return }
            }
        }
    }

    /// The errors to list: every module's, or the chosen module's.
    private var shownErrors: [NasLogEntry] {
        guard let errorsFrom else { return store.errors }
        return store.errors.filter { $0.service == errorsFrom }
    }

    private func serviceCard(_ service: NasStatus.Service) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(service.healthy ? Color.sage : .danger)
                .frame(width: 9, height: 9)
                .shadow(color: (service.healthy ? Color.sage : .danger).opacity(0.6), radius: 4)
            Text(service.name.capitalized).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
            Spacer()
            Text(service.healthy ? "Healthy" : "Down")
                .font(.caption)
                .foregroundStyle(service.healthy ? Color.inkMuted : .danger)
        }
        .padding(14)
        .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect(cornerRadius: 16))
    }

    private func deviceRow(_ device: NasClientDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(device.nodeName))
                .font(.body.weight(.medium))
                .foregroundStyle(device.online ? Color.sageDeep : .inkFaint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.nodeName).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                Text(device.pending ? "Setup code not used yet" : (device.ipAddresses.first ?? ""))
                    .font(.caption.monospaced())
                    .foregroundStyle(.inkMuted)
            }
            Spacer()
            Text(device.online ? "Online" : "Offline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(device.online ? Color.sageText : .inkFaint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((device.online ? Color.sage : .inkFaint).opacity(0.14), in: .capsule)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func errorRow(_ entry: NasLogEntry) -> some View {
        Button { opened = entry } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.service).font(.caption.weight(.bold)).foregroundStyle(.danger)
                    if let code = entry.code {
                        Text(code).font(.caption2.monospaced()).foregroundStyle(.inkMuted)
                    }
                    Spacer()
                    Text(entry.time, style: .relative).font(.caption2).foregroundStyle(.inkFaint)
                }
                Text(entry.msg).font(.footnote).foregroundStyle(.ink).lineLimit(2).multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.danger.opacity(0.06), in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func overview(_ status: NasStatus) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                let healthy = store.healthy
                Image(systemName: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(healthy ? Color.sageDeep : .danger)
                    .symbolEffect(.bounce, value: healthy)
                VStack(alignment: .leading, spacing: 1) {
                    Text(healthy ? "dadi is healthy" : "Something's down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text("Up \(SystemPage.uptime(status.uptimeSeconds))")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
                Spacer()
            }
            HStack(spacing: 0) {
                Ring(title: "CPU", percent: status.cpu.usedPercent)
                Ring(title: "Memory", percent: status.memory.usedPercent)
                Ring(title: "Disk", percent: status.disk.usedPercent)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    /// How long the box has been up: "11 days, 4 hours".
    static func uptime(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 2))
    }

    private func section<Content: View>(_ section: Section, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.rawValue.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.inkFaint)
            content()
        }
        .id(section)
    }

    private func icon(_ name: String) -> String {
        let lower = name.lowercased()
        if lower == "os" { return "server.rack" }
        if lower.contains("phone") { return "iphone" }
        if lower.contains("mac") { return "laptopcomputer" }
        if lower.contains("watch") { return "applewatch" }
        return "desktopcomputer"
    }

    /// Puts `value` on this device's clipboard.
    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        copies += 1
    }
}

/// An animated ring for a percentage, sage until it runs hot.
private struct Ring: View {
    let title: String
    let percent: Double
    private let diameter: CGFloat = 74

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.sage.opacity(0.16), lineWidth: diameter / 8.2)
                Circle()
                    .trim(from: 0, to: percent / 100)
                    .stroke(percent > 85 ? Color.danger : percent > 65 ? .clay : .sageDeep, style: StrokeStyle(lineWidth: diameter / 8.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.settle, value: percent)
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: diameter / 5, weight: .bold).monospacedDigit())
                    .foregroundStyle(.ink)
                    .contentTransition(.numericText())
            }
            .frame(width: diameter, height: diameter)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(Int(percent)) percent used")
    }
}

/// Identifies a log entry for the sheet.
private struct LogSheetItem: Identifiable {
    let entry: NasLogEntry
    var id: String { entry.raw }
}

/// A log entry's whole line: its message, code, and every field it carried.
private struct LogDetail: View {
    let entry: NasLogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(entry.service).font(.headline).foregroundStyle(.danger)
                    if let code = entry.code { Text(code).font(.caption.monospaced()).foregroundStyle(.inkMuted) }
                    Spacer()
                    Text(entry.time, format: .dateTime.month().day().hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.inkFaint)
                }
                Text(entry.msg).font(.body.weight(.medium)).foregroundStyle(.ink)
                Text(pretty)
                    .font(.caption.monospaced())
                    .foregroundStyle(.ink)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.sage.opacity(0.08), in: .rect(cornerRadius: 12))
            }
            .padding(24)
        }
    }

    /// The raw JSON line indented for reading.
    private var pretty: String {
        guard let data = entry.raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return entry.raw
        }
        return String(decoding: out, as: UTF8.self)
    }
}

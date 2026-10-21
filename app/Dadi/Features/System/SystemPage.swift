import SwiftUI

/// System: the box at a glance. Rings for its processor, memory and disk, how
/// long it has been up, each module's health, every device on dadi, and the
/// latest errors in the logs. Refreshes every five seconds while open.
struct SystemPage: View {
    let nas: NasClient

    @State private var status: NasStatus?
    @State private var devices: [NasClientDevice] = []
    @State private var errors: [NasLogEntry] = []
    @State private var problem: String?
    @State private var opened: NasLogEntry?

    private let refresh: Duration = .seconds(5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.danger)
                }
                if let status {
                    overview(status)
                    section("Services") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                            ForEach(status.services, id: \.name) { service in
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
                            }
                        }
                    }
                    section("Drives") {
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
                                    ProgressView(value: disk.usedPercent, total: 100).tint(.sage)
                                    Text(disk.mount).font(.caption2.monospaced()).foregroundStyle(.inkFaint)
                                }
                                .padding(14)
                                .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                } else if problem == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
                if !devices.isEmpty {
                    section("Devices on dadi") {
                        VStack(spacing: 0) {
                            ForEach(devices) { device in
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
                                if device.id != devices.last?.id { Rectangle().fill(.rule).frame(height: 1) }
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(.boneRaised.opacity(0.7), in: .rect(cornerRadius: 16, style: .continuous))
                    }
                }
                if !errors.isEmpty {
                    section("Recent errors") {
                        VStack(spacing: 8) {
                            ForEach(errors, id: \.self) { entry in
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
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .animation(Motion.settle, value: status)
        }
        .refreshable { await load() }
        .sheet(item: Binding(get: { opened.map(LogSheetItem.init) }, set: { opened = $0?.entry })) { item in
            LogDetail(entry: item.entry)
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
        }
        .navigationTitle("System")
        .task {
            while !Task.isCancelled {
                await load()
                do { try await Task.sleep(for: refresh) } catch { return }
            }
        }
    }

    private func overview(_ status: NasStatus) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                let healthy = status.services.allSatisfy(\.healthy)
                Image(systemName: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(healthy ? Color.sageDeep : .danger)
                    .symbolEffect(.bounce, value: healthy)
                VStack(alignment: .leading, spacing: 1) {
                    Text(healthy ? "dadi is healthy" : "Something's down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text("Up \(Duration.seconds(status.uptimeSeconds).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 2)))")
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.inkFaint)
            content()
        }
    }

    private func icon(_ name: String) -> String {
        let lower = name.lowercased()
        if lower == "os" { return "server.rack" }
        if lower.contains("phone") { return "iphone" }
        if lower.contains("mac") { return "laptopcomputer" }
        if lower.contains("watch") { return "applewatch" }
        return "desktopcomputer"
    }

    private func load() async {
        do {
            async let nextStatus = nas.status()
            async let nextDevices = nas.devices()
            async let nextErrors = nas.logs(level: "error", limit: 8)
            let (s, d, e) = try await (nextStatus, nextDevices, nextErrors)
            status = s
            devices = d.sorted { ($0.online ? 0 : 1, $0.nodeName) < ($1.online ? 0 : 1, $1.nodeName) }
            errors = e
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// An animated ring for a percentage, sage until it runs hot.
private struct Ring: View {
    let title: String
    let percent: Double

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.sage.opacity(0.16), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: percent / 100)
                    .stroke(percent > 85 ? Color.danger : percent > 65 ? .clay : .sageDeep, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.settle, value: percent)
                Text("\(Int(percent.rounded()))%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.ink)
                    .contentTransition(.numericText())
            }
            .frame(width: 74, height: 74)
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

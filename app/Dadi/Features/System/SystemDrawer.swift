import SwiftUI

/// System's drawer: the box's health at a glance, then the page's sections
/// with what each holds (how many modules are down, devices online, recent
/// errors), each jumping the page to it.
struct SystemDrawer: View {
    let store: SystemStore
    /// Jumps the page to a section and closes the drawer.
    let choose: (SystemPage.Section) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let status = store.status {
                HStack(spacing: 12) {
                    Image(systemName: store.healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(store.healthy ? Color.sageDeep : .danger)
                        .symbolEffect(.bounce, value: store.healthy)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.healthy ? "dadi is healthy" : "Something's down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.ink)
                        Text("Up \(SystemPage.uptime(status.uptimeSeconds))")
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)
                    }
                    Spacer()
                }
                .padding(12)
                .background((store.healthy ? Color.sage : .danger).opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SECTIONS")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.inkFaint)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                ForEach(SystemPage.Section.allCases, id: \.self) { section in
                    Button { choose(section) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(section))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.sageDeep)
                                .frame(width: 22)
                            Text(section.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.ink)
                            Spacer()
                            Text(detail(section))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(alarming(section) ? Color.danger : .inkMuted)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .contentShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let problem = store.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 14)
        .animation(Motion.snap, value: store.status)
    }

    private func symbol(_ section: SystemPage.Section) -> String {
        switch section {
        case .overview: "gauge.with.dots.needle.50percent"
        case .services: "square.stack.3d.up"
        case .drives: "internaldrive"
        case .tasks: "rectangle.stack"
        case .devices: "iphone.gen3"
        case .errors: "exclamationmark.bubble"
        }
    }

    /// What a section holds, in a word or two.
    private func detail(_ section: SystemPage.Section) -> String {
        guard let status = store.status else { return "" }
        switch section {
        case .overview:
            return "CPU \(Int(status.cpu.usedPercent.rounded()))%"
        case .services:
            let down = status.services.filter { !$0.healthy }.count
            return down == 0 ? "All healthy" : "\(down) down"
        case .drives:
            return "\(Int(status.disk.usedPercent.rounded()))% used"
        case .tasks:
            let working = store.tasks.filter { $0.status == "working" }.count
            return store.tasks.isEmpty ? "None" : "\(working) working"
        case .devices:
            return "\(store.devices.filter(\.online).count) online"
        case .errors:
            return store.errors.isEmpty ? "None" : "\(store.errors.count)"
        }
    }

    /// Whether a section's detail needs attention.
    private func alarming(_ section: SystemPage.Section) -> Bool {
        guard let status = store.status else { return false }
        switch section {
        case .services: return !store.healthy
        case .drives: return status.disk.usedPercent > 85
        default: return false
        }
    }
}

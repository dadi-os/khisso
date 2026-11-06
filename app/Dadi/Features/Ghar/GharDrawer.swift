import SwiftUI

/// Ghar's drawer: All off and Evening, then Everywhere and every tag with the
/// light it gives, what is on and its switch, then the untagged devices.
/// Tapping a row narrows the page to it; its switch works from here without
/// leaving.
struct GharDrawer: View {
    let store: GharStore
    let filter: GharPage.Filter
    /// Narrows the page and closes the drawer.
    let choose: (GharPage.Filter) -> Void

    @State private var switched = 0

    var body: some View {
        let tags = GharLayout.tags(store.devices)
        let loose = GharLayout.untagged(store.devices)
        VStack(alignment: .leading, spacing: 18) {
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
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 2) {
                heading("TAGS")
                row(title: "Everywhere", summary: GharLayout.summary(store.devices), target: .everywhere, devices: store.devices)
                ForEach(tags) { set in
                    row(title: set.name, summary: GharLayout.summary(set.devices), target: .tag(set.id), devices: set.devices)
                }
                if !loose.isEmpty && !tags.isEmpty {
                    row(title: "Untagged", summary: GharLayout.summary(loose), target: .untagged, devices: loose)
                }
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.danger)
                    .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 14)
        .animation(Motion.snap, value: store.devices)
        .sensoryFeedback(.impact(weight: .medium), trigger: switched)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(.inkFaint)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
    }

    /// Everywhere, a tag or the untagged devices: a dot in the light it gives, its name and what is on,
    /// and its switch; lit sage while the page shows it.
    private func row(title: String, summary: GharSummary, target: GharPage.Filter, devices: [GharDevice]) -> some View {
        let current = filter == target
        let lit = summary.on > 0
        return HStack(spacing: 12) {
            Button { choose(target) } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(lit ? (summary.color ?? .white(kelvin: 2700)).color : Color.sageLine.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .shadow(color: lit ? (summary.color ?? .white(kelvin: 2700)).color.opacity(0.9) : .clear, radius: 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ink)
                            .lineLimit(1)
                        Text(GharLayout.status(summary))
                            .font(.caption)
                            .foregroundStyle(.inkMuted)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if summary.total > 0 {
                GharSwitch(isOn: lit, label: "Switch \(title)") {
                    switched += 1
                    store.setOn(!lit, devices)
                }
                .scaleEffect(0.82)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(current ? Color.sage.opacity(0.16) : .clear, in: .rect(cornerRadius: 16, style: .continuous))
        .animation(Motion.snap, value: current)
    }
}

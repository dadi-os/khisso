import SwiftUI

/// First run: paste the setup code made in dadiOS Preferences → Devices. The
/// first join has to happen on the box's network, where Headscale answers.
struct JoinView: View {
    let connection: Connection

    @State private var code = ""
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("દાદી")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Join dadi").font(.title2.weight(.semibold))
                Text("On your box, open Preferences → Devices, add this device, and paste its setup code here. Be on the same network as the box for this first join.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            TextField("Setup code", text: $code, axis: .vertical)
                .lineLimit(3...6)
                .font(.callout.monospaced())
                .textFieldStyle(.plain)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .frame(maxWidth: 460)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Button("Join") {
                do {
                    try connection.join(pasted: code)
                    problem = nil
                } catch {
                    problem = error.localizedDescription
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding(24)
        .tint(Color(red: 0.36, green: 0.42, blue: 0.32))
    }
}

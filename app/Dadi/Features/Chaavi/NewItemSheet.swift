import SwiftUI

/// A new login or secure note for Chaavi. A login starts with a password
/// Chaavi generates (make another, longer or shorter, with or without
/// symbols, or type your own), its website, username and an optional
/// one-time-code key; either kind takes a folder, a star and notes. Save
/// writes it with POST /v1/items and closes; Chaavi's refusal shows here.
struct NewItemSheet: View {
    let store: ChaaviStore

    /// The two kinds this sheet makes.
    private enum Kind: String, CaseIterable {
        case login = "Login"
        case note = "Secure note"
    }

    /// Chaavi's shortest and longest generated passwords.
    private static let lengths = 12...64

    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.login
    @State private var name = ""
    @State private var website = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showing = false
    @State private var length = 20
    @State private var symbols = true
    @State private var totp = ""
    @State private var folderId: String?
    @State private var favorite = false
    @State private var notes = ""
    @State private var generating = false
    @State private var saving = false
    @State private var problem: String?
    @State private var saved = 0
    @State private var made = 0
    @FocusState private var naming: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind.animation(Motion.snap)) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField("Name", text: $name)
                        .focused($naming)
                        .submitLabel(.next)
                    if kind == .login {
                        TextField("Website", text: $website)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Username or email", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                if kind == .login {
                    passwordSection
                    Section {
                        TextField("One-time code key", text: $totp, axis: .vertical)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Paste the setup key or otpauth:// link the site shows when you turn on two-factor sign-in.")
                    }
                }
                Section {
                    Picker("Folder", selection: $folderId) {
                        Text("None").tag(String?.none)
                        ForEach(store.folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { folder in
                            Text(folder.name).tag(String?.some(folder.id))
                        }
                    }
                    Toggle("Favorite", isOn: $favorite)
                        .tint(.sageDeep)
                }
                Section(kind == .note ? "Note" : "Notes") {
                    TextField(kind == .note ? "What to keep safe" : "Anything else", text: $notes, axis: .vertical)
                        .lineLimit(kind == .note ? 6...14 : 2...6)
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.danger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.boneRaised.ignoresSafeArea())
            .tint(.sageDeep)
            .navigationTitle(kind == .login ? "New login" : "New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                            .disabled(!ready)
                    }
                }
            }
            .animation(Motion.snap, value: problem)
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: made)
        .task {
            naming = true
            await generate()
        }
    }

    /// The password: shown in full or as dots, made again on a tap, sized by
    /// the stepper and with or without symbols, each change making a new one.
    private var passwordSection: some View {
        Section {
            HStack(spacing: 10) {
                Group {
                    if showing {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .contentTransition(.opacity)
                Button { showing.toggle() } label: {
                    Image(systemName: showing ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showing ? "Hide password" : "Show password")
                Button { Task { await generate() } } label: {
                    if generating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(generating)
                .accessibilityLabel("Make another password")
            }
            Stepper(value: $length, in: Self.lengths, step: 2) {
                HStack {
                    Text("Length")
                    Spacer()
                    Text("\(length)").monospacedDigit().foregroundStyle(.inkMuted).contentTransition(.numericText())
                }
            }
            .onChange(of: length) { Task { await generate() } }
            Toggle("Symbols", isOn: $symbols)
                .tint(.sageDeep)
                .onChange(of: symbols) { Task { await generate() } }
        } header: {
            Text("Password")
        } footer: {
            Text(strength)
        }
    }

    /// The password's length and mix in words.
    private var strength: String {
        let mix = password.contains(where: { !$0.isLetter && !$0.isNumber }) ? "with symbols" : "letters and numbers"
        return password.isEmpty ? "Chaavi makes one when you open this." : "\(password.count) characters, \(mix)."
    }

    private var ready: Bool {
        !name.trimmed.isEmpty && !saving && (kind == .note ? !notes.trimmed.isEmpty : !password.isEmpty)
    }

    /// Asks Chaavi for a new password at the chosen length and mix.
    private func generate() async {
        generating = true
        defer { generating = false }
        do {
            password = try await store.chaavi.generate(length: length, symbols: symbols)
            made += 1
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = "Couldn't make a password: \(error.localizedDescription)"
        }
    }

    private func save() {
        var item = ChaaviNewItem(type: kind == .login ? "login" : "note", name: name.trimmed)
        item.folderId = folderId
        item.favorite = favorite ? true : nil
        item.notes = notes.trimmed.isEmpty ? nil : notes.trimmed
        if kind == .login {
            item.login = ChaaviNewItem.Login(
                username: username.trimmed.isEmpty ? nil : username.trimmed,
                password: password,
                totp: totp.trimmed.isEmpty ? nil : totp.trimmed,
                uris: website.trimmed.isEmpty ? nil : [ChaaviNewItem.Uri(uri: website.trimmed)]
            )
        }
        saving = true
        problem = nil
        Task {
            defer { saving = false }
            do {
                try await store.create(item)
                saved += 1
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}

private extension String {
    /// The string without leading or trailing whitespace.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

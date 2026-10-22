import Foundation
import Security

/// A device's provisioning from a setup code made in dadiOS Preferences →
/// Devices: base64 JSON with the Headscale control URL, a preauth key and the
/// device's name on dadi.
struct SetupCode: Codable, Sendable, Equatable {
    let controlUrl: String
    let authKey: String
    let nodeName: String

    /// Why a pasted setup code was rejected.
    enum Problem: LocalizedError, Equatable {
        case empty
        case unreadable
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .empty: "Paste a setup code from dadi."
            case .unreadable: "That isn't a dadi setup code. Check you copied the whole thing."
            case .missing(let field): "The setup code has no \(field). Make a new one in Preferences → Devices."
            }
        }
    }

    /// Decodes a pasted setup code.
    init(pasted: String) throws {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Problem.empty }
        guard let data = Data(base64Encoded: trimmed),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Problem.unreadable
        }
        func field(_ key: String) throws -> String {
            guard let value = raw[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw Problem.missing(key)
            }
            return value
        }
        controlUrl = try field("control_url")
        authKey = try field("auth_key")
        nodeName = try field("node_name")
    }
}

/// The saved setup code, kept in the Keychain for this device only. The
/// iPhone uses the data protection Keychain; the Mac uses the login Keychain,
/// whose items only this app's signature can read, because the data
/// protection Keychain on macOS needs a provisioning profile that a free
/// Personal Team build made from the command line does not carry.
enum SetupStore {
    private static let service = "com.dadi.khisso"
    private static let account = "setup"

    /// The attributes that name the item, for every call.
    private static var base: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(iOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    /// The saved setup code, or nil when this device has not joined dadi.
    static func load() throws -> SetupCode? {
        var query = base
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError(status: errSecDecode) }
            return try JSONDecoder().decode(SetupCode.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Saves code, replacing any earlier one.
    static func save(_ code: SetupCode) throws {
        try delete()
        var item = base
        item[kSecValueData as String] = try JSONEncoder().encode(code)
        #if os(iOS)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Removes the saved setup code, if any.
    static func delete() throws {
        let status = SecItemDelete(base as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// A Keychain call that failed with `status`.
struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Keychain: \(text)"
    }
}

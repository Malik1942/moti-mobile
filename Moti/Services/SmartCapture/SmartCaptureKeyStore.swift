import Foundation
import Security

/// Stores the Smart Capture (Gemini) API key.
///
/// Primary store: iOS Keychain (`kSecClassGenericPassword`), encrypted by the
/// OS and tied to the app + device. The user pastes their key into the Settings
/// UI; the key is never embedded in the binary, never in `UserDefaults`, never
/// in `Info.plist`.
///
/// DEBUG fallback: when the Keychain is empty and the build is DEBUG, the store
/// returns `DevSecrets.geminiAPIKey` from `Moti/Secrets.swift` (gitignored).
/// This lets a developer iterate without re-entering the key on every reinstall,
/// while keeping the production path key-free.
enum SmartCaptureKeyStore {

    private static let service = "com.malik.Moti.SmartCapture"
    private static let account = "GeminiAPIKey"

    /// The currently active API key, or `nil` if none is configured.
    ///
    /// Reads Keychain first. In DEBUG builds, falls back to `DevSecrets.geminiAPIKey`.
    static var apiKey: String? {
        if let stored = readFromKeychain(), !stored.isEmpty {
            return stored
        }
        #if DEBUG
        if let dev = DevSecrets.geminiAPIKey,
           !dev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dev
        }
        #endif
        return nil
    }

    /// True when an API key is available from any configured source.
    static var isConfigured: Bool {
        apiKey?.isEmpty == false
    }

    /// True when the Keychain itself holds a key (independent of the DEBUG fallback).
    static var hasKeychainKey: Bool {
        readFromKeychain()?.isEmpty == false
    }

    // MARK: - Proxy configuration
    //
    // Proxy mode is used when both a base URL and a shared secret are configured.
    // In that case Smart Capture skips the direct Gemini call and talks to the
    // MotiProxy Cloudflare Worker instead — the real Gemini key never ships in
    // the binary. See MotiProxy/README.md.

    /// The MotiProxy base URL, if configured. Read from `DevSecrets.proxyBaseURL`.
    static var proxyBaseURL: URL? {
        guard
            let raw = DevSecrets.proxyBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let url = URL(string: raw)
        else { return nil }
        return url
    }

    /// Shared secret presented to MotiProxy in `Authorization: Bearer`.
    static var proxySharedSecret: String? {
        let candidate = DevSecrets.proxySharedSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (candidate?.isEmpty == false) ? candidate : nil
    }

    /// True when both proxy URL and proxy shared secret are configured.
    static var isProxyConfigured: Bool {
        proxyBaseURL != nil && proxySharedSecret != nil
    }

    /// Persists the key to Keychain. Passing `nil` or an empty string clears it.
    @discardableResult
    static func setKey(_ key: String?) -> Bool {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = trimmed, !value.isEmpty else {
            return clear()
        }
        return writeToKeychain(value)
    }

    /// Deletes any stored Keychain key. The DEBUG fallback (if any) is untouched.
    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Keychain primitives

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard
            status == errSecSuccess,
            let data = result as? Data,
            let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }

    private static func writeToKeychain(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Try update first; fall back to add when no item exists yet.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            // Available once the device has been unlocked once after boot — the
            // app process can read the key in the background after the first
            // foreground unlock.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }
}

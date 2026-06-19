import Foundation
import CryptoKit
import Security

/// At-rest encryption for clipboard content. Sensitive text/blobs are encrypted
/// with AES-GCM before they reach SQLite, using a 256-bit key kept in the login
/// Keychain (generated on first use, never leaves the device). Search and display
/// operate on the decrypted in-memory `ClipItem`s, so functionality is unchanged.
///
/// Failure is always non-destructive: if encryption or decryption fails, the
/// original value is returned rather than risking history loss.
enum Crypto {
    private static let marker = "enc1:"            // prefix on encrypted payloads
    private static let markerData = Data("enc1:".utf8)
    private static let service = "ai.axiotic.ditto"
    private static let account = "db-key-v1"

    /// Process-wide key. In the signed app it is loaded from / created in the
    /// Keychain; if the Keychain is unavailable (e.g. unit tests) an ephemeral
    /// key is generated so round-trips still work within the process.
    private static let key: SymmetricKey = loadOrCreateKey()

    // MARK: Strings

    /// "<plain>" → "enc1:<base64>". Returns the input unchanged on failure.
    static func seal(_ plain: String) -> String {
        guard let data = plain.data(using: .utf8) else { return plain }
        do {
            let box = try AES.GCM.seal(data, using: key)
            guard let combined = box.combined else { NSLog("Ditto Crypto: nil combined"); return plain }
            return marker + combined.base64EncodedString()
        } catch {
            NSLog("Ditto Crypto: seal failed: \(error)")
            return plain
        }
    }

    /// "enc1:<base64>" → "<plain>". Legacy plaintext (no marker) passes through,
    /// so existing un-encrypted histories keep working during migration.
    static func open(_ stored: String) -> String {
        guard stored.hasPrefix(marker) else { return stored }
        guard let data = Data(base64Encoded: String(stored.dropFirst(marker.count))),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: key),
              let s = String(data: opened, encoding: .utf8) else { return stored }
        return s
    }

    // MARK: Data (e.g. RTF blobs)

    static func seal(_ plain: Data?) -> Data? {
        guard let plain, let box = try? AES.GCM.seal(plain, using: key),
              let combined = box.combined else { return plain }
        return markerData + combined
    }

    static func open(_ stored: Data?) -> Data? {
        guard let stored else { return nil }
        guard stored.starts(with: markerData) else { return stored }
        let body = stored.dropFirst(markerData.count)
        guard let box = try? AES.GCM.SealedBox(combined: body),
              let opened = try? AES.GCM.open(box, using: key) else { return stored }
        return opened
    }

    // MARK: Keychain-backed key

    private static func loadOrCreateKey() -> SymmetricKey {
        if let existing = readKey() { return existing }
        let fresh = SymmetricKey(size: .bits256)
        storeKey(fresh)
        return fresh
    }

    private static func readKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func storeKey(_ key: SymmetricKey) {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)   // best-effort; failure → ephemeral key
    }
}

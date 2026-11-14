import Foundation
import Security

public enum SecretStoreError: Error, LocalizedError, Equatable, Sendable {
    case unhandledStatus(OSStatus)
    case invalidDataEncoding

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain 操作失败（\(status)）：\(message)"
            }
            return "Keychain 操作失败（状态码 \(status)）。"
        case .invalidDataEncoding:
            return "Keychain 返回的数据无法解码为 UTF-8 字符串。"
        }
    }
}

public enum SiftSecretKey {
    public static let classifierAPIKey = "classifier.apiKey"
    public static let geminiAPIKey = "classifier.apiKey.gemini"

    public static func apiKey(for providerId: String) -> String {
        let trimmed = providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? classifierAPIKey : "classifier.apiKey.\(trimmed)"
    }
}

public protocol SecretStore: Sendable {
    func readSecret(key: String) throws -> String?
    func writeSecret(key: String, value: String) throws
    func deleteSecret(key: String) throws
}

/// 生产环境密钥存储：使用 macOS Keychain（`kSecClassGenericPassword`, service `"NaichengDeng.Sift"`）。
public struct KeychainSecretStore: SecretStore, Sendable {
    public static let defaultService = "NaichengDeng.Sift"

    public let service: String

    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    public func readSecret(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidDataEncoding
        }
        return string
    }

    public func writeSecret(key: String, value: String) throws {
        if value.isEmpty {
            try deleteSecret(key: key)
            return
        }

        let encoded = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = encoded
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        if addStatus == errSecDuplicateItem {
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: encoded,
            ]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecretStoreError.unhandledStatus(updateStatus)
            }
            return
        }
        throw SecretStoreError.unhandledStatus(addStatus)
    }

    public func deleteSecret(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unhandledStatus(status)
        }
    }
}

/// 单元与 UI 测试专用内存密钥存储：线程安全且绝不触发系统 Keychain 授权弹窗。
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]

    public init(initialSecrets: [String: String] = [:]) {
        self.storage = initialSecrets
    }

    public func readSecret(key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func writeSecret(key: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if value.isEmpty {
            storage.removeValue(forKey: key)
        } else {
            storage[key] = value
        }
    }

    public func deleteSecret(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

// The slice of Security and CommonCrypto that BackupCrypto calls, so its code compiles
// unchanged. Keychain items are files in the app's private directory, which Android
// sandboxes per app; nothing syncs, because Android has no iCloud Keychain.
// TODO(android): back the key with the Android Keystore instead of a plain private file.

import _CryptoExtras
import Crypto
import Foundation

typealias OSStatus = Int32
typealias CFTypeRef = Any
typealias CFDictionary = [String: Any]

nonisolated let errSecSuccess: OSStatus = 0
nonisolated let errSecDuplicateItem: OSStatus = -25299
nonisolated let errSecItemNotFound: OSStatus = -25300
nonisolated let errSecParam: OSStatus = -50

nonisolated let kSecClass = "class"
nonisolated let kSecClassGenericPassword = "genp"
nonisolated let kSecAttrService = "svce"
nonisolated let kSecAttrAccount = "acct"
nonisolated let kSecAttrSynchronizable = "sync"
nonisolated let kSecAttrSynchronizableAny = "syna"
nonisolated let kSecAttrAccessible = "pdmn"
nonisolated let kSecAttrAccessibleAfterFirstUnlock = "ck"
nonisolated let kSecValueData = "v_Data"
nonisolated let kSecReturnData = "r_Data"
nonisolated let kSecMatchLimit = "m_Limit"
nonisolated let kSecMatchLimitOne = "m_LimitOne"
nonisolated let kCFBooleanTrue: Bool? = true
nonisolated let kSecRandomDefault: Int? = nil

private nonisolated func keychainFile(_ attributes: [String: Any]) -> URL? {
    guard let service = attributes[kSecAttrService] as? String,
          let account = attributes[kSecAttrAccount] as? String,
          let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return nil }
    let directory = support.appending(path: "keychain", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "\(service).\(account)")
}

nonisolated func SecItemAdd(_ attributes: CFDictionary, _: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let file = keychainFile(attributes), let data = attributes[kSecValueData] as? Data else { return errSecParam }
    if FileManager.default.fileExists(atPath: file.path) { return errSecDuplicateItem }
    do {
        try data.write(to: file, options: [.atomic, .withoutOverwriting])
        return errSecSuccess
    } catch {
        return FileManager.default.fileExists(atPath: file.path) ? errSecDuplicateItem : errSecParam
    }
}

nonisolated func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    guard let file = keychainFile(query) else { return errSecParam }
    guard let data = try? Data(contentsOf: file) else { return errSecItemNotFound }
    result?.pointee = data
    return errSecSuccess
}

nonisolated func SecRandomCopyBytes(_: Int?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> Int32 {
    var generator = SystemRandomNumberGenerator()
    let buffer = bytes.assumingMemoryBound(to: UInt8.self)
    for index in 0 ..< count {
        buffer[index] = generator.next()
    }
    return errSecSuccess
}

// MARK: - CommonCrypto

typealias CCPBKDFAlgorithm = UInt32
typealias CCPseudoRandomAlgorithm = UInt32
nonisolated let kCCPBKDF2: UInt32 = 2
nonisolated let kCCPRFHmacAlgSHA256: UInt32 = 3
nonisolated let kCCSuccess: Int32 = 0
nonisolated let kCCParamError: Int32 = -4300

/// PBKDF2-HMAC-SHA256 through swift-crypto, with CommonCrypto's signature.
nonisolated func CCKeyDerivationPBKDF(
    _ algorithm: CCPBKDFAlgorithm,
    _ password: UnsafePointer<CChar>?,
    _ passwordLength: Int,
    _ salt: UnsafePointer<UInt8>?,
    _ saltLength: Int,
    _ prf: CCPseudoRandomAlgorithm,
    _ rounds: UInt32,
    _ derivedKey: UnsafeMutablePointer<UInt8>?,
    _ derivedKeyLength: Int,
) -> Int32 {
    guard algorithm == kCCPBKDF2, prf == kCCPRFHmacAlgSHA256, let derivedKey else { return kCCParamError }
    let passwordBytes = password.map { Data(bytes: $0, count: passwordLength) } ?? Data()
    let saltBytes = salt.map { Data(bytes: $0, count: saltLength) } ?? Data()
    guard let key = try? KDF.Insecure.PBKDF2.deriveKey(
        from: passwordBytes, salt: saltBytes, using: .sha256,
        outputByteCount: derivedKeyLength, unsafeUncheckedRounds: Int(rounds),
    ) else { return kCCParamError }
    key.withUnsafeBytes { raw in
        for index in 0 ..< derivedKeyLength {
            derivedKey[index] = raw[index]
        }
    }
    return kCCSuccess
}

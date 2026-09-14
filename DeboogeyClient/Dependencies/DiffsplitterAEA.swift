//
//  DiffsplitterAEA.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation
import CryptoKit
import AppleArchive
import System

nonisolated enum DiffsplitterAEA {
    static let magic = Data("AEA1".utf8)
    private static let prologueProbeBytes = 256 * 1024

    enum AEAError: LocalizedError {
        case unreadable
        case keyRequired
        case decryptFailed(String)
        case invalidKey

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return L10n.t("The Apple Encrypted Archive could not be read.")
            case .keyRequired:
                return L10n.t("This Apple Encrypted Archive needs a decryption key.")
            case .decryptFailed(let detail):
                return L10n.f("Could not decrypt the Apple Encrypted Archive: %@", detail)
            case .invalidKey:
                return L10n.t("The decryption key is invalid.")
            }
        }
    }

    static func isAEAExtension(of url: URL) -> Bool {
        url.pathExtension.lowercased() == "aea"
    }

    static func looksLike(_ data: Data) -> Bool {
        data.count >= 4 && data.starts(with: magic)
    }

    static func looksLikeFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4), header.count == 4 else { return false }
        return header == magic
    }

    static func summarize(at url: URL) throws -> [String] {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let probe = try handle.read(upToCount: min(prologueProbeBytes, max(size, 0))) ?? Data()
        var lines: [String] = [
            "format: AEA",
            "path: \(url.lastPathComponent)",
            "size: \(size)"
        ]
        if looksLike(probe) {
            lines.append("magic: AEA1")
        } else {
            lines.append("magic: unknown")
        }
        if let meta = try? openContext(at: url) {
            if let idData = meta.archiveIdentifier, !idData.isEmpty {
                let idString = idData.map { String(format: "%02x", $0) }.joined()
                lines.append("id: \(idString)")
            }
            lines.append("profile: \(meta.profile.rawValue)")
            lines.append("encryption-mode: \(meta.encryptionMode.rawValue)")
            if let auth = meta.authData, !auth.isEmpty {
                let keys = authDataKeys(in: auth)
                if !keys.isEmpty {
                    lines.append("auth-data-keys:")
                    for key in keys.sorted() {
                        lines.append("  \(key)")
                    }
                } else {
                    lines.append("auth-data-bytes: \(auth.count)")
                }
            }
        } else {
            let authKeys = authDataKeys(in: probe)
            if !authKeys.isEmpty {
                lines.append("auth-data-keys:")
                for key in authKeys.sorted() {
                    lines.append("  \(key)")
                }
            }
        }
        lines.append("prologue-sha256: \(sha256Hex(probe))")
        lines.append("prologue-bytes: \(probe.count)")
        return lines
    }

    static func summarize(_ data: Data) throws -> [String] {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Diffsplitter-aea-summary-\(UUID().uuidString)")
        try data.write(to: temp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temp) }
        return try summarize(at: temp)
    }

    static func normalizeKeyValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("base64:") || lower.hasPrefix("hex:") {
            return trimmed
        }
        if trimmed.range(of: #"^[A-Za-z0-9+/=_-]+$"#, options: .regularExpression) != nil {
            return "base64:\(trimmed)"
        }
        if trimmed.range(of: #"^[0-9A-Fa-f]+$"#, options: .regularExpression) != nil,
           trimmed.count % 2 == 0 {
            return "hex:\(trimmed)"
        }
        return "base64:\(trimmed)"
    }

    static func decrypt(
        input: URL,
        output: URL,
        keyValue: String?
    ) throws {
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: output)

        guard let keyValue, let normalized = normalizeKeyValue(keyValue),
              let symmetric = try? makeSymmetricKey(from: normalized) else {
            if (try? decryptWithOptionalKey(input: input, output: output, key: nil)) == true {
                return
            }
            throw DiffsplitterContainer.ContainerError.aeaKeyRequired
        }
        do {
            try decryptWithKey(input: input, output: output, key: symmetric)
        } catch let error as AEAError {
            throw DiffsplitterContainer.ContainerError.aeaDecryptFailed(error.localizedDescription)
        } catch let error as DiffsplitterContainer.ContainerError {
            throw error
        } catch {
            throw DiffsplitterContainer.ContainerError.aeaDecryptFailed(error.localizedDescription)
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw DiffsplitterContainer.ContainerError.aeaDecryptFailed("aea produced no output")
        }
    }

    static func decryptedOutputURL(for input: URL, in directory: URL) -> URL {
        var name = input.lastPathComponent
        if name.lowercased().hasSuffix(".aea") {
            name = String(name.dropLast(4))
        }
        if name.isEmpty { name = "aea-payload" }
        return directory.appendingPathComponent(name)
    }

    private static func openContext(at url: URL) throws -> ArchiveEncryptionContext {
        guard let fileIn = ArchiveByteStream.fileStream(
            path: FilePath(url.path),
            mode: .readOnly,
            options: [.noFollow],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw AEAError.unreadable
        }
        defer { try? fileIn.close() }
        guard let context = ArchiveEncryptionContext(from: fileIn) else {
            throw AEAError.unreadable
        }
        return context
    }

    private static func decryptWithOptionalKey(input: URL, output: URL, key: SymmetricKey?) throws -> Bool {
        do {
            try decryptWithKey(input: input, output: output, key: key)
            return FileManager.default.fileExists(atPath: output.path)
        } catch {
            return false
        }
    }

    private static func decryptWithKey(input: URL, output: URL, key: SymmetricKey?) throws {
        guard let fileIn = ArchiveByteStream.fileStream(
            path: FilePath(input.path),
            mode: .readOnly,
            options: [.noFollow],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw AEAError.unreadable
        }
        defer { try? fileIn.close() }

        guard let context = ArchiveEncryptionContext(from: fileIn) else {
            throw AEAError.unreadable
        }
        if let key {
            try context.setSymmetricKey(key)
        }

        try? fileIn.close()
        guard let fileIn2 = ArchiveByteStream.fileStream(
            path: FilePath(input.path),
            mode: .readOnly,
            options: [.noFollow],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw AEAError.unreadable
        }
        defer { try? fileIn2.close() }

        guard let decrypted = ArchiveByteStream.decryptionStream(
            readingFrom: fileIn2,
            encryptionContext: context
        ) else {
            throw AEAError.decryptFailed("decryption stream")
        }
        defer { try? decrypted.close() }

        if let decoder = ArchiveStream.decodeStream(readingFrom: decrypted) {
            defer { try? decoder.close() }
            try FileManager.default.createDirectory(
                at: output.hasDirectoryPath ? output : output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let extractRoot: URL
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: output.path, isDirectory: &isDir), isDir.boolValue {
                extractRoot = output
            } else if output.pathExtension.isEmpty {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                extractRoot = output
            } else {
                extractRoot = output.deletingPathExtension().appendingPathExtension("aea-extract")
                try? FileManager.default.removeItem(at: extractRoot)
                try FileManager.default.createDirectory(at: extractRoot, withIntermediateDirectories: true)
            }
            guard let extractor = ArchiveStream.extractStream(
                extractingTo: FilePath(extractRoot.path),
                flags: [.ignoreOperationNotPermitted]
            ) else {
                throw AEAError.decryptFailed("extract stream")
            }
            defer { try? extractor.close() }
            _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)

            if extractRoot != output {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: extractRoot,
                    includingPropertiesForKeys: nil
                )) ?? []
                if children.count == 1 {
                    try? FileManager.default.removeItem(at: output)
                    try FileManager.default.moveItem(at: children[0], to: output)
                    try? FileManager.default.removeItem(at: extractRoot)
                } else {
                    try? FileManager.default.removeItem(at: output)
                    try FileManager.default.moveItem(at: extractRoot, to: output)
                }
            }
            return
        }

        guard let fileOut = ArchiveByteStream.fileStream(
            path: FilePath(output.path),
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw AEAError.decryptFailed("output stream")
        }
        defer { try? fileOut.close() }
        _ = try ArchiveByteStream.process(readingFrom: decrypted, writingTo: fileOut)
    }

    private static func makeSymmetricKey(from normalized: String) throws -> SymmetricKey {
        let lower = normalized.lowercased()
        let payload: Data
        if lower.hasPrefix("base64:") {
            let b64 = String(normalized.dropFirst("base64:".count))
            guard let data = Data(base64Encoded: b64) else { throw AEAError.invalidKey }
            payload = data
        } else if lower.hasPrefix("hex:") {
            let hex = String(normalized.dropFirst("hex:".count))
            guard let data = dataFromHex(hex) else { throw AEAError.invalidKey }
            payload = data
        } else {
            throw AEAError.invalidKey
        }
        guard !payload.isEmpty else { throw AEAError.invalidKey }
        return SymmetricKey(data: payload)
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        var cleaned = hex
        if cleaned.count % 2 != 0 { return nil }
        var data = Data()
        data.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func authDataKeys(in probe: Data) -> [String] {
        if let structured = parseAuthDataKeys(probe), !structured.isEmpty {
            return structured
        }
        guard let ascii = String(data: probe, encoding: .ascii) ?? String(data: probe, encoding: .isoLatin1) else {
            return []
        }
        var keys: Set<String> = []
        let pattern = #"com\.apple\.[A-Za-z0-9._-]{3,80}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(ascii.startIndex..<ascii.endIndex, in: ascii)
            regex.enumerateMatches(in: ascii, range: range) { match, _, _ in
                guard let match, let swiftRange = Range(match.range, in: ascii) else { return }
                keys.insert(String(ascii[swiftRange]))
            }
        }
        return Array(keys)
    }

    private static func parseAuthDataKeys(_ data: Data) -> [String]? {
        guard data.count >= 4 else { return nil }

        let count = Int(readUInt32LE(data, 0))
        guard count > 0, count < 512 else { return nil }
        var offset = 4
        var keys: [String] = []
        for _ in 0..<count {
            guard offset + 4 <= data.count else { return nil }
            let keyLen = Int(readUInt32LE(data, offset))
            offset += 4
            guard keyLen > 0, keyLen < 4096, offset + keyLen <= data.count else { return nil }
            let keyData = data.subdata(in: offset..<(offset + keyLen))
            offset += keyLen
            guard offset + 4 <= data.count else { return nil }
            let valLen = Int(readUInt32LE(data, offset))
            offset += 4
            guard valLen >= 0, valLen < 16 * 1024 * 1024, offset + valLen <= data.count else { return nil }
            offset += valLen
            if let key = String(data: keyData, encoding: .utf8) {
                keys.append(key)
            }
        }
        return keys
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

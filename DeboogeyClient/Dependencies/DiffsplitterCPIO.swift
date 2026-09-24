//
//  DiffsplitterCPIO.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation

nonisolated enum DiffsplitterCPIO {
    struct Entry: Sendable, Equatable {
        let name: String
        let isDirectory: Bool
        let isSymlink: Bool
        let mode: UInt32
        let dataOffset: UInt64
        let dataSize: UInt64
    }

    enum CPIOError: LocalizedError {
        case truncated
        case invalidMagic
        case unsupportedFormat
        case pathTooDeep

        var errorDescription: String? {
            switch self {
            case .truncated:
                return L10n.t("The CPIO archive is truncated or unreadable.")
            case .invalidMagic:
                return L10n.t("The file is not a valid CPIO archive.")
            case .unsupportedFormat:
                return L10n.t("Unsupported CPIO format.")
            case .pathTooDeep:
                return L10n.t("A CPIO member path escapes the extract directory.")
            }
        }
    }

    private static let trailerName = "TRAILER!!!"

    static func expand(archive: URL, into destination: URL) throws {
        let data = try Data(contentsOf: archive, options: [.mappedIfSafe])
        try expand(data: data, into: destination)
    }

    static func expand(data: Data, into destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            let (entry, next) = try readEntry(data: data, at: offset)
            offset = next
            if entry.name == trailerName { break }
            let outURL = try safeURL(destination: destination, member: entry.name)
            if entry.isDirectory || entry.name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if entry.isSymlink {
                let linkData = data.subdata(in: Int(entry.dataOffset)..<Int(entry.dataOffset + entry.dataSize))
                let target = String(data: linkData, encoding: .utf8)
                    ?? String(data: linkData, encoding: .isoLatin1)
                    ?? ""
                try? FileManager.default.removeItem(at: outURL)
                try FileManager.default.createSymbolicLink(atPath: outURL.path, withDestinationPath: target)
                continue
            }
            let fileData = data.subdata(in: Int(entry.dataOffset)..<Int(entry.dataOffset + entry.dataSize))
            try fileData.write(to: outURL, options: .atomic)
        }
    }

    static func listEntries(data: Data) throws -> [Entry] {
        var offset = 0
        var entries: [Entry] = []
        while offset < data.count {
            let (entry, next) = try readEntry(data: data, at: offset)
            offset = next
            if entry.name == trailerName { break }
            entries.append(entry)
        }
        return entries
    }

    private static func readEntry(data: Data, at offset: Int) throws -> (Entry, Int) {
        guard offset + 6 <= data.count else { throw CPIOError.truncated }
        let magicData = data.subdata(in: offset..<(offset + 6))
        guard let magic = String(data: magicData, encoding: .ascii) else {
            throw CPIOError.invalidMagic
        }
        switch magic {
        case "070701", "070702":
            return try readNewc(data: data, at: offset)
        case "070707":
            return try readODC(data: data, at: offset)
        default:
            throw CPIOError.unsupportedFormat
        }
    }

    static func looksLike(_ data: Data) -> Bool {
        guard data.count >= 6, let magic = String(data: data.prefix(6), encoding: .ascii) else {
            return false
        }
        return magic == "070701" || magic == "070702" || magic == "070707"
    }

    private static func readNewc(data: Data, at offset: Int) throws -> (Entry, Int) {
        let headerSize = 110
        guard offset + headerSize <= data.count else { throw CPIOError.truncated }
        func field(_ index: Int) throws -> UInt64 {
            let start = offset + 6 + index * 8
            let slice = data.subdata(in: start..<(start + 8))
            guard let s = String(data: slice, encoding: .ascii),
                  let value = UInt64(s, radix: 16) else {
                throw CPIOError.truncated
            }
            return value
        }
        let mode = UInt32(try field(1))
        let filesize = try field(6)
        let namesize = Int(try field(11))
        let nameStart = offset + headerSize
        guard namesize > 0, nameStart + namesize <= data.count else { throw CPIOError.truncated }
        let nameBytes = data.subdata(in: nameStart..<(nameStart + namesize))
        let name = decodeName(nameBytes)
        var dataStart = nameStart + namesize
        dataStart = (dataStart + 3) & ~3
        guard dataStart + Int(filesize) <= data.count else { throw CPIOError.truncated }
        var dataEnd = dataStart + Int(filesize)
        dataEnd = (dataEnd + 3) & ~3
        return (makeEntry(name: name, mode: mode, dataOffset: UInt64(dataStart), dataSize: filesize), dataEnd)
    }

    private static func readODC(data: Data, at offset: Int) throws -> (Entry, Int) {
        let headerSize = 76
        guard offset + headerSize <= data.count else { throw CPIOError.truncated }
        func octal(_ start: Int, _ length: Int) throws -> UInt64 {
            let slice = data.subdata(in: (offset + start)..<(offset + start + length))
            guard let s = String(data: slice, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = UInt64(s, radix: 8) else {
                throw CPIOError.truncated
            }
            return value
        }
        let mode = UInt32(try octal(18, 6))
        let namesize = Int(try octal(59, 6))
        let filesize = try octal(65, 11)
        let nameStart = offset + headerSize
        guard namesize > 0, nameStart + namesize <= data.count else { throw CPIOError.truncated }
        let nameBytes = data.subdata(in: nameStart..<(nameStart + namesize))
        let name = decodeName(nameBytes)
        let dataStart = nameStart + namesize
        guard dataStart + Int(filesize) <= data.count else { throw CPIOError.truncated }
        return (
            makeEntry(name: name, mode: mode, dataOffset: UInt64(dataStart), dataSize: filesize),
            dataStart + Int(filesize)
        )
    }

    private static func decodeName(_ nameBytes: Data) -> String {
        let trimmed = nameBytes.dropLast(while: { $0 == 0 })
        return String(bytes: trimmed, encoding: .utf8)
            ?? String(bytes: trimmed, encoding: .isoLatin1)
            ?? ""
    }

    private static func makeEntry(name: String, mode: UInt32, dataOffset: UInt64, dataSize: UInt64) -> Entry {
        Entry(
            name: name,
            isDirectory: (mode & 0o170000) == 0o040000,
            isSymlink: (mode & 0o170000) == 0o120000,
            mode: mode,
            dataOffset: dataOffset,
            dataSize: dataSize
        )
    }

    private static func safeURL(destination: URL, member: String) throws -> URL {
        var cleaned = member.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if cleaned.hasPrefix("./") {
            cleaned = String(cleaned.dropFirst(2))
        }
        guard !cleaned.isEmpty, !cleaned.contains("..") else {
            throw CPIOError.pathTooDeep
        }
        var url = destination
        for part in cleaned.split(separator: "/") where !part.isEmpty {
            url = url.appendingPathComponent(String(part))
        }
        let destPath = destination.standardizedFileURL.path
        let outPath = url.standardizedFileURL.path
        guard outPath == destPath || outPath.hasPrefix(destPath + "/") else {
            throw CPIOError.pathTooDeep
        }
        return url
    }
}

private extension Data {
    func dropLast(while predicate: (UInt8) -> Bool) -> Data {
        var end = count
        while end > 0 && predicate(self[end - 1]) {
            end -= 1
        }
        return subdata(in: 0..<end)
    }
}

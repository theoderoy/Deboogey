//
//  DiffsplitterPBZX.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation
import Compression

nonisolated enum DiffsplitterPBZX {
    enum PBZXError: LocalizedError {
        case truncated
        case invalidMagic
        case decompressFailed
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .truncated:
                return L10n.t("The pbzx stream is truncated or unreadable.")
            case .invalidMagic:
                return L10n.t("The file is not a valid pbzx stream.")
            case .decompressFailed:
                return L10n.t("Could not decompress a pbzx chunk.")
            case .tooLarge:
                return L10n.t("The pbzx payload is too large to expand in Diffsplitter.")
            }
        }
    }

    private static let magic = Data("pbzx".utf8)
    private static let maxOutputBytes = 8 * 1024 * 1024 * 1024

    static func looksLike(_ data: Data) -> Bool {
        data.count >= 4 && data.starts(with: magic)
    }

    static func looksLikeFile(at url: URL) -> Bool {
        DiffsplitterBinaryIO.fileMatchesMagic(at: url, magic: magic)
    }

    static func decode(data: Data) throws -> Data {
        guard data.count >= 16 else { throw PBZXError.truncated }
        guard data.starts(with: magic) else { throw PBZXError.invalidMagic }
        var offset = 4
        guard offset + 8 <= data.count else { throw PBZXError.truncated }
        offset += 8

        var output = Data()
        while offset + 16 <= data.count {
            try Task.checkCancellation()
            let lastFlags = DiffsplitterBinaryIO.readUInt64BE(data, offset)
            offset += 8
            let chunkLength = DiffsplitterBinaryIO.readUInt64BE(data, offset)
            offset += 8
            guard chunkLength <= UInt64(Int.max) else { throw PBZXError.tooLarge }
            let length = Int(chunkLength)
            guard offset + length <= data.count else { throw PBZXError.truncated }
            let chunk = data.subdata(in: offset..<(offset + length))
            offset += length

            let decoded = (looksLikeXZ(chunk) || lastFlags != 0) ? try decompressXZ(chunk) : chunk
            if output.count > maxOutputBytes - decoded.count {
                throw PBZXError.tooLarge
            }
            output.append(decoded)
            if offset >= data.count { break }
        }
        return output
    }

    static func decode(fileAt url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try decode(data: data)
    }

    static func decodeToFile(fileAt url: URL, output: URL) throws {
        let decoded = try decode(fileAt: url)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try decoded.write(to: output, options: .atomic)
    }

    private static func looksLikeXZ(_ data: Data) -> Bool {
        data.count >= 6
            && data[0] == 0xFD
            && data[1] == 0x37
            && data[2] == 0x7A
            && data[3] == 0x58
            && data[4] == 0x5A
            && data[5] == 0x00
    }

    private static func decompressXZ(_ data: Data) throws -> Data {
        var capacity = max(data.count * 4, 256 * 1024)
        var lastError: PBZXError = .decompressFailed
        for _ in 0..<8 {
            var destination = Data(count: capacity)
            let written: Int = destination.withUnsafeMutableBytes { dst in
                data.withUnsafeBytes { src in
                    guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                          let srcBase = src.bindMemory(to: UInt8.self).baseAddress else {
                        return 0
                    }
                    return compression_decode_buffer(
                        dstBase,
                        dst.count,
                        srcBase,
                        src.count,
                        nil,
                        COMPRESSION_LZMA
                    )
                }
            }
            if written > 0 {
                destination.count = written
                return destination
            }
            lastError = .decompressFailed
            capacity *= 2
            if capacity > 512 * 1024 * 1024 {
                break
            }
        }
        throw lastError
    }
}

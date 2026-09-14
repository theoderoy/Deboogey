//
//  DiffsplitterUDIF.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation
import zlib
import Compression

nonisolated final class DiffsplitterUDIFDisk: @unchecked Sendable {
    let virtualSize: UInt64
    private let handle: FileHandle
    private let runs: [BlockRun]
    private let lock = NSLock()

    struct BlockRun: Sendable {
        let type: UInt32
        let compressedOffset: UInt64
        let compressedLength: UInt64
        let sectorNumber: UInt64
        let sectorCount: UInt64
    }

    enum UDIFError: LocalizedError {
        case truncated
        case invalidTrailer
        case missingBlkx
        case unsupportedBlock(UInt32)
        case decompressFailed
        case outOfRange

        var errorDescription: String? {
            switch self {
            case .truncated:
                return L10n.t("The disk image is truncated or unreadable.")
            case .invalidTrailer:
                return L10n.t("The disk image has an invalid UDIF trailer.")
            case .missingBlkx:
                return L10n.t("The disk image has no readable block table.")
            case .unsupportedBlock(let t):
                return L10n.f("Unsupported DMG block type: %u", Int(t))
            case .decompressFailed:
                return L10n.t("Could not decompress a DMG block.")
            case .outOfRange:
                return L10n.t("DMG read is out of range.")
            }
        }
    }

    private static let blockZero: UInt32 = 0x0000_0000
    private static let blockRaw: UInt32 = 0x0000_0001
    private static let blockIgnore: UInt32 = 0x0000_0002
    private static let blockComment: UInt32 = 0x7FFF_FFFE
    private static let blockTerminator: UInt32 = 0xFFFF_FFFF
    private static let blockADC: UInt32 = 0x8000_0004
    private static let blockZlib: UInt32 = 0x8000_0005
    private static let blockBzip2: UInt32 = 0x8000_0006
    private static let blockLZFSE: UInt32 = 0x8000_0007
    private static let blockLZMA: UInt32 = 0x8000_0008

    static func open(url: URL) throws -> DiffsplitterUDIFDisk {
        let handle = try FileHandle(forReadingFrom: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize >= 512 else {
            try? handle.close()
            throw UDIFError.truncated
        }
        try handle.seek(toOffset: fileSize - 512)
        guard let trailer = try handle.read(upToCount: 512), trailer.count == 512 else {
            try? handle.close()
            throw UDIFError.truncated
        }

        guard trailer.starts(with: Data("koly".utf8)) else {
            try handle.seek(toOffset: 0)
            let run = BlockRun(
                type: blockRaw,
                compressedOffset: 0,
                compressedLength: fileSize,
                sectorNumber: 0,
                sectorCount: fileSize / 512
            )
            return DiffsplitterUDIFDisk(handle: handle, virtualSize: fileSize, runs: [run])
        }

        let dataForkOffset = readUInt64BE(trailer, 0x18)
        let xmlOffset = readUInt64BE(trailer, 0xD8)
        let xmlLength = readUInt64BE(trailer, 0xE0)
        let sectorCount = readUInt64BE(trailer, 0x28)
        let virtualSize = sectorCount * 512

        guard xmlOffset > 0, xmlLength > 0, xmlOffset + xmlLength <= fileSize else {
            try? handle.close()
            throw UDIFError.invalidTrailer
        }
        try handle.seek(toOffset: xmlOffset)
        guard let xmlData = try handle.read(upToCount: Int(xmlLength)),
              xmlData.count == Int(xmlLength),
              let xml = String(data: xmlData, encoding: .utf8)
                ?? String(data: xmlData, encoding: .isoLatin1) else {
            try? handle.close()
            throw UDIFError.missingBlkx
        }
        let blkxBlobs = extractBlkxBlobs(from: xml)
        guard !blkxBlobs.isEmpty else {
            try? handle.close()
            throw UDIFError.missingBlkx
        }
        var runs: [BlockRun] = []
        for blob in blkxBlobs {
            let parsed = try parseMish(blob, dataForkOffset: dataForkOffset)
            runs.append(contentsOf: parsed)
        }
        runs.sort { $0.sectorNumber < $1.sectorNumber }
        return DiffsplitterUDIFDisk(handle: handle, virtualSize: virtualSize, runs: runs)
    }

    private init(handle: FileHandle, virtualSize: UInt64, runs: [BlockRun]) {
        self.handle = handle
        self.virtualSize = virtualSize
        self.runs = runs
    }

    deinit {
        try? handle.close()
    }

    func read(offset: UInt64, length: Int) throws -> Data {
        guard length >= 0 else { throw UDIFError.outOfRange }
        if length == 0 { return Data() }
        guard offset + UInt64(length) <= virtualSize else { throw UDIFError.outOfRange }
        var result = Data(count: length)
        var remaining = length
        var virtualOffset = offset
        var outIndex = 0
        while remaining > 0 {
            try Task.checkCancellation()
            guard let run = run(containingSector: virtualOffset / 512) else {
                let hole = min(remaining, Int(512 - (virtualOffset % 512)))
                outIndex += hole
                virtualOffset += UInt64(hole)
                remaining -= hole
                continue
            }
            let runStart = run.sectorNumber * 512
            let runLength = run.sectorCount * 512
            let intoRun = virtualOffset - runStart
            let take = min(UInt64(remaining), runLength - intoRun)
            let chunk = try readRun(run, intoRunOffset: intoRun, length: Int(take))
            result.replaceSubrange(outIndex..<(outIndex + chunk.count), with: chunk)
            outIndex += chunk.count
            virtualOffset += UInt64(chunk.count)
            remaining -= chunk.count
        }
        return result
    }

    private func run(containingSector sector: UInt64) -> BlockRun? {
        for run in runs {
            if sector >= run.sectorNumber && sector < run.sectorNumber + run.sectorCount {
                return run
            }
        }
        return nil
    }

    private func readRun(_ run: BlockRun, intoRunOffset: UInt64, length: Int) throws -> Data {
        switch run.type {
        case Self.blockZero, Self.blockIgnore, Self.blockComment:
            return Data(count: length)
        case Self.blockRaw:
            lock.lock()
            defer { lock.unlock() }
            try handle.seek(toOffset: run.compressedOffset + intoRunOffset)
            guard let data = try handle.read(upToCount: length), data.count == length else {
                throw UDIFError.truncated
            }
            return data
        case Self.blockZlib, Self.blockLZFSE, Self.blockLZMA, Self.blockADC, Self.blockBzip2:
            let full = try decompressRun(run)
            let start = Int(intoRunOffset)
            let end = start + length
            guard start >= 0, end <= full.count else { throw UDIFError.outOfRange }
            return full.subdata(in: start..<end)
        case Self.blockTerminator:
            return Data(count: length)
        default:
            throw UDIFError.unsupportedBlock(run.type)
        }
    }

    private func decompressRun(_ run: BlockRun) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        try handle.seek(toOffset: run.compressedOffset)
        guard run.compressedLength <= UInt64(Int.max),
              let compressed = try handle.read(upToCount: Int(run.compressedLength)),
              compressed.count == Int(run.compressedLength) else {
            throw UDIFError.truncated
        }
        let expected = Int(run.sectorCount * 512)
        switch run.type {
        case Self.blockZlib:
            return try Self.inflateZlib(compressed, expectedSize: expected)
        case Self.blockLZFSE:
            return try Self.decompress(compressed, algorithm: COMPRESSION_LZFSE, expectedSize: expected)
        case Self.blockLZMA:
            return try Self.decompress(compressed, algorithm: COMPRESSION_LZMA, expectedSize: expected)
        case Self.blockADC:
            return try Self.decodeADC(compressed, expectedSize: expected)
        case Self.blockBzip2:
            throw UDIFError.unsupportedBlock(run.type)
        default:
            throw UDIFError.unsupportedBlock(run.type)
        }
    }

    private static func extractBlkxBlobs(from xml: String) -> [Data] {
        var blobs: [Data] = []

        let parts = xml.components(separatedBy: "blkx")
        for part in parts.dropFirst() {
            if let dataRange = part.range(of: "<data>"),
               let endRange = part.range(of: "</data>", range: dataRange.upperBound..<part.endIndex) {
                let b64 = String(part[dataRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\t", with: "")
                    .replacingOccurrences(of: " ", with: "")
                if let decoded = Data(base64Encoded: b64), decoded.count > 0xCC {
                    blobs.append(decoded)
                }
            }
        }

        if blobs.isEmpty {
            var search = xml.startIndex
            while let start = xml.range(of: "<data>", range: search..<xml.endIndex) {
                guard let end = xml.range(of: "</data>", range: start.upperBound..<xml.endIndex) else { break }
                let b64 = String(xml[start.upperBound..<end.lowerBound])
                    .filter { !$0.isWhitespace }
                if let decoded = Data(base64Encoded: b64),
                   decoded.count > 0xCC,
                   decoded.starts(with: Data("mish".utf8)) {
                    blobs.append(decoded)
                }
                search = end.upperBound
            }
        }
        return blobs
    }

    private static func parseMish(_ data: Data, dataForkOffset: UInt64) throws -> [BlockRun] {
        guard data.count >= 0xCC, data.starts(with: Data("mish".utf8)) else {
            throw UDIFError.missingBlkx
        }
        let entryCount = Int(readUInt32BE(data, 0x54))
        let tableStart = 0xCC
        let entrySize = 40
        guard tableStart + entryCount * entrySize <= data.count else {
            throw UDIFError.truncated
        }
        var runs: [BlockRun] = []
        for i in 0..<entryCount {
            let o = tableStart + i * entrySize
            let type = readUInt32BE(data, o)
            if type == blockTerminator || type == blockComment { continue }
            let sectorNumber = readUInt64BE(data, o + 8)
            let sectorCount = readUInt64BE(data, o + 16)
            let compressedOffset = readUInt64BE(data, o + 24) + dataForkOffset
            let compressedLength = readUInt64BE(data, o + 32)
            runs.append(
                BlockRun(
                    type: type,
                    compressedOffset: compressedOffset,
                    compressedLength: compressedLength,
                    sectorNumber: sectorNumber,
                    sectorCount: sectorCount
                )
            )
        }
        return runs
    }

    private static func inflateZlib(_ data: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        var status = inflateInit2_(&stream, 15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw UDIFError.decompressFailed }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(expectedSize, 1))
        var written = 0
        try data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let srcBase = src.bindMemory(to: Bytef.self).baseAddress else {
                throw UDIFError.decompressFailed
            }
            stream.next_in = UnsafeMutablePointer(mutating: srcBase)
            stream.avail_in = uInt(data.count)
            while true {
                if written >= output.count { output.count += expectedSize }
                let capacity = output.count
                let availOut = uInt(capacity - written)
                let result: Int = output.withUnsafeMutableBytes { dst in
                    let base = dst.bindMemory(to: Bytef.self).baseAddress!.advanced(by: written)
                    stream.next_out = base
                    stream.avail_out = availOut
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                    return Int(status)
                }
                written = capacity - Int(stream.avail_out)
                if result == Z_STREAM_END { break }
                if result != Z_OK { throw UDIFError.decompressFailed }
            }
        }
        output.count = min(written, expectedSize)
        if output.count < expectedSize {
            output.append(Data(count: expectedSize - output.count))
        }
        return output
    }

    private static func decompress(_ data: Data, algorithm: compression_algorithm, expectedSize: Int) throws -> Data {
        var destination = Data(count: max(expectedSize, data.count))
        let written: Int = destination.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    dstBase, dst.count, srcBase, src.count, nil, algorithm
                )
            }
        }
        guard written > 0 else { throw UDIFError.decompressFailed }
        destination.count = min(written, expectedSize)
        if destination.count < expectedSize {
            destination.append(Data(count: expectedSize - destination.count))
        }
        return destination
    }

    private static func decodeADC(_ data: Data, expectedSize: Int) throws -> Data {
        var output = Data()
        output.reserveCapacity(expectedSize)
        var i = 0
        while i < data.count && output.count < expectedSize {
            let cmd = data[i]
            i += 1
            if cmd & 0x80 != 0 {
                let n = Int(cmd & 0x7F) + 1
                guard i + n <= data.count else { throw UDIFError.decompressFailed }
                output.append(data.subdata(in: i..<(i + n)))
                i += n
            } else if cmd & 0x40 != 0 {
                guard i < data.count else { throw UDIFError.decompressFailed }
                let b = data[i]
                i += 1
                let length = Int(cmd & 0x3F) + 4
                let offset = Int(b) + 1
                try appendBackReference(to: &output, offset: offset, length: length, cap: expectedSize)
            } else {
                guard i + 1 < data.count else { throw UDIFError.decompressFailed }
                let b1 = data[i]
                let b2 = data[i + 1]
                i += 2
                let length = Int(cmd & 0x3F) + 4
                let offset = (Int(b1) << 8 | Int(b2)) + 1
                try appendBackReference(to: &output, offset: offset, length: length, cap: expectedSize)
            }
        }
        if output.count < expectedSize {
            output.append(Data(count: expectedSize - output.count))
        }
        return output
    }

    private static func appendBackReference(to output: inout Data, offset: Int, length: Int, cap: Int) throws {
        guard offset > 0, offset <= output.count else { throw UDIFError.decompressFailed }
        for _ in 0..<length {
            if output.count >= cap { return }
            let byte = output[output.count - offset]
            output.append(byte)
        }
    }

    private static func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func readUInt64BE(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(data[offset + i])
        }
        return value
    }
}

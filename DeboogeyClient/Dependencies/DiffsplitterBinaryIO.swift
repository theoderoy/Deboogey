//
//  DiffsplitterBinaryIO.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 16/09/2026.
//

import Foundation
import CryptoKit
import zlib

nonisolated enum DiffsplitterBinaryIO {
    @inline(__always)
    static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    @inline(__always)
    static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    @inline(__always)
    static func readUInt64LE(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(readUInt32LE(data, offset)) | (UInt64(readUInt32LE(data, offset + 4)) << 32)
    }

    @inline(__always)
    static func readUInt16BE(_ data: Data, _ offset: Int) -> UInt16 {
        (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    @inline(__always)
    static func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    @inline(__always)
    static func readUInt64BE(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(data[offset + i])
        }
        return value
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fileMatchesMagic(at url: URL, magic: Data) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: magic.count),
              header.count == magic.count else { return false }
        return header == magic
    }

    static func inflateZlib(
        _ data: Data,
        windowBits: Int32,
        initialCapacity: Int,
        growBy: Int
    ) throws -> Data {
        var stream = z_stream()
        var status = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw InflateError.failed }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(initialCapacity, 1))
        var written = 0
        try data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let srcBase = src.bindMemory(to: Bytef.self).baseAddress else {
                throw InflateError.failed
            }
            stream.next_in = UnsafeMutablePointer(mutating: srcBase)
            stream.avail_in = uInt(data.count)
            while true {
                if written >= output.count {
                    output.count += max(growBy, 1)
                }
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
                if result != Z_OK { throw InflateError.failed }
                if stream.avail_in == 0 && stream.avail_out > 0 { break }
            }
        }
        output.count = written
        return output
    }

    enum InflateError: Error {
        case failed
    }
}

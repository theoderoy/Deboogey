//
//  Diffsplitter.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 02/09/2026.
//

import Foundation
import CryptoKit
import zlib
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Combine

nonisolated protocol DiffsplitterContainerBackend: Sendable {
    func attachDiskImage(_ image: URL, mountPoint: URL) throws
    func detachDiskImage(at mountPoint: URL)
    func expandPkg(package: URL, into destination: URL) throws
    func expandXip(archive: URL, into destination: URL) throws
    func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL?
    ) throws -> String
    func runProcessData(
        executable: String,
        arguments: [String],
        currentDirectory: URL?
    ) throws -> Data
}
nonisolated enum DiffsplitterContainerServices {
    static var backend: DiffsplitterContainerBackend = DiffsplitterMacContainerBackend()
}
nonisolated struct DiffsplitterUnsupportedContainerBackend: DiffsplitterContainerBackend {
    private func unsupported(_ feature: String) -> Error {
        DiffsplitterContainer.ContainerError.expandFailed("\(feature) is not available on this platform")
    }
    func attachDiskImage(_ image: URL, mountPoint: URL) throws {
        throw unsupported("Disk image mounting")
    }
    func detachDiskImage(at mountPoint: URL) {}
    func expandPkg(package: URL, into destination: URL) throws {
        throw unsupported("PKG expansion")
    }
    func expandXip(archive: URL, into destination: URL) throws {
        throw unsupported("XIP expansion")
    }
    func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL?
    ) throws -> String {
        throw unsupported(executable)
    }
    func runProcessData(
        executable: String,
        arguments: [String],
        currentDirectory: URL?
    ) throws -> Data {
        throw unsupported(executable)
    }
}
#if os(macOS)
nonisolated struct DiffsplitterMacContainerBackend: DiffsplitterContainerBackend {
    func attachDiskImage(_ image: URL, mountPoint: URL) throws {
        let diskutilArgs = [
            "image", "attach",
            "--readOnly",
            "--nobrowse",
            "--mountPoint", mountPoint.path,
            image.path
        ]
        do {
            _ = try runProcess(executable: "/usr/sbin/diskutil", arguments: diskutilArgs, currentDirectory: nil)
            return
        } catch let error as DiffsplitterContainer.ContainerError {
            let detail = error.processDetail.lowercased()
            let missingSubcommand =
                detail.contains("unknown")
                || detail.contains("invalid")
                || detail.contains("unrecognized")
                || detail.contains("usage:")
                || detail.contains("overview:")
            if !missingSubcommand {
                throw error
            }
        }
        _ = try runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                image.path,
                "-readonly",
                "-nobrowse",
                "-mountpoint",
                mountPoint.path
            ],
            currentDirectory: nil
        )
    }
    func detachDiskImage(at mountPoint: URL) {
        if (try? runProcess(
            executable: "/usr/sbin/diskutil",
            arguments: ["eject", "force", mountPoint.path],
            currentDirectory: nil
        )) != nil {
            return
        }
        _ = try? runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: ["detach", mountPoint.path, "-force"],
            currentDirectory: nil
        )
    }
    func expandPkg(package: URL, into destination: URL) throws {
        do {
            _ = try runProcess(
                executable: "/usr/sbin/pkgutil",
                arguments: ["--expand", package.path, destination.path],
                currentDirectory: nil
            )
        } catch {
            do {
                _ = try runProcess(
                    executable: "/usr/bin/xar",
                    arguments: ["-xf", package.path, "-C", destination.path],
                    currentDirectory: nil
                )
            } catch {
                throw DiffsplitterContainer.ContainerError.expandFailed(error.localizedDescription)
            }
        }
    }
    func expandXip(archive: URL, into destination: URL) throws {
        let localCopy = destination.appendingPathComponent(archive.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: archive, to: localCopy)
            _ = try runProcess(
                executable: "/usr/bin/xip",
                arguments: ["--expand", localCopy.path],
                currentDirectory: destination
            )
            try? FileManager.default.removeItem(at: localCopy)
        } catch {
            do {
                _ = try runProcess(
                    executable: "/usr/bin/xar",
                    arguments: ["-xf", archive.path, "-C", destination.path],
                    currentDirectory: nil
                )
            } catch {
                throw DiffsplitterContainer.ContainerError.expandFailed(error.localizedDescription)
            }
        }
    }
    func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL?
    ) throws -> String {
        let data = try runProcessData(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory
        )
        return String(data: data, encoding: .utf8) ?? ""
    }
    func runProcessData(
        executable: String,
        arguments: [String],
        currentDirectory: URL?
    ) throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        let dataLock = NSLock()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let chunk = stdout.fileHandleForReading.readDataToEndOfFile()
            dataLock.lock()
            outData = chunk
            dataLock.unlock()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let chunk = stderr.fileHandleForReading.readDataToEndOfFile()
            dataLock.lock()
            errData = chunk
            dataLock.unlock()
            group.leave()
        }
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                _ = group.wait(timeout: .now() + 2)
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        group.wait()
        if Task.isCancelled {
            throw CancellationError()
        }
        let errText = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let detail = errText.isEmpty ? "exit \(process.terminationStatus)" : errText
            throw DiffsplitterContainer.ContainerError.expandFailed(detail)
        }
        return outData
    }
}
#else
typealias DiffsplitterMacContainerBackend = DiffsplitterUnsupportedContainerBackend
#endif
nonisolated enum DiffsplitterZip {
    struct Entry: Sendable, Equatable {
        let name: String
        let crc32: UInt32
        let uncompressedSize: Int
        let compressedSize: UInt64
        let localHeaderOffset: UInt64
        let compressionMethod: UInt16
        let generalPurposeFlag: UInt16
    }
    enum ZipError: LocalizedError {
        case truncated
        case invalidSignature
        case unsupportedCompression(UInt16)
        case inflateFailed
        case memberNotFound
        case tooLarge
        var errorDescription: String? {
            switch self {
            case .truncated:
                return L10n.t("The ZIP archive is truncated or unreadable.")
            case .invalidSignature:
                return L10n.t("The ZIP archive is invalid.")
            case .unsupportedCompression:
                return L10n.t("This ZIP member uses an unsupported compression method.")
            case .inflateFailed:
                return L10n.t("Could not decompress the ZIP member.")
            case .memberNotFound:
                return L10n.t("The ZIP member could not be found.")
            case .tooLarge:
                return L10n.t("This archive has too many entries to compare in Diffsplitter.")
            }
        }
    }
    static func listEntries(archive: URL, maxEntries: Int = DiffsplitterContainer.maxEntries) throws -> [Entry] {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw ZipError.truncated }
        let (cdOffset, cdSize, entryCount) = try locateCentralDirectory(handle: handle, fileSize: fileSize)
        if entryCount > maxEntries { throw ZipError.tooLarge }
        try handle.seek(toOffset: cdOffset)
        var entries: [Entry] = []
        entries.reserveCapacity(Int(min(entryCount, UInt64(maxEntries))))
        var remaining = cdSize
        while remaining > 0, entries.count < maxEntries {
            try Task.checkCancellation()
            guard remaining >= 46 else { break }
            let header = try readExact(handle, count: 46)
            remaining -= 46
            guard readUInt32LE(header, 0) == 0x0201_4B50 else { throw ZipError.invalidSignature }
            let gpFlag = readUInt16LE(header, 8)
            let method = readUInt16LE(header, 10)
            let crc = readUInt32LE(header, 16)
            var compressed = UInt64(readUInt32LE(header, 20))
            var uncompressed = UInt64(readUInt32LE(header, 24))
            let nameLen = Int(readUInt16LE(header, 28))
            let extraLen = Int(readUInt16LE(header, 30))
            let commentLen = Int(readUInt16LE(header, 32))
            var localOffset = UInt64(readUInt32LE(header, 42))
            let nameData = try readExact(handle, count: nameLen)
            remaining -= UInt64(nameLen)
            let extra = try readExact(handle, count: extraLen)
            remaining -= UInt64(extraLen)
            if commentLen > 0 {
                _ = try readExact(handle, count: commentLen)
                remaining -= UInt64(commentLen)
            }
            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                applyZIP64Extra(
                    extra,
                    compressed: &compressed,
                    uncompressed: &uncompressed,
                    localOffset: &localOffset
                )
            }
            let name = decodeName(nameData, utf8: (gpFlag & 0x800) != 0)
            if name.hasSuffix("/") { continue }
            let sizeInt: Int
            if uncompressed > UInt64(Int.max) {
                sizeInt = Int.max
            } else {
                sizeInt = Int(uncompressed)
            }
            entries.append(Entry(
                name: name,
                crc32: crc,
                uncompressedSize: sizeInt,
                compressedSize: compressed,
                localHeaderOffset: localOffset,
                compressionMethod: method,
                generalPurposeFlag: gpFlag
            ))
        }
        if entries.count > maxEntries { throw ZipError.tooLarge }
        return entries
    }
    static func extractMember(
        archive: URL,
        memberPath: String,
        to destination: URL,
        expectedBytes: Int? = nil,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws {
        let entries = try listEntries(archive: archive)
        guard let entry = entries.first(where: { $0.name == memberPath })
            ?? entries.first(where: { $0.name.hasSuffix("/" + memberPath) }) else {
            throw ZipError.memberNotFound
        }
        try extract(entry: entry, archive: archive, to: destination, expectedBytes: expectedBytes, progress: progress)
    }
    static func extractMemberToMemory(
        archive: URL,
        memberPath: String,
        expectedBytes: Int? = nil,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws -> Data {
        let entries = try listEntries(archive: archive)
        guard let entry = entries.first(where: { $0.name == memberPath })
            ?? entries.first(where: { $0.name.hasSuffix("/" + memberPath) }) else {
            throw ZipError.memberNotFound
        }
        return try extractToMemory(
            entry: entry,
            archive: archive,
            expectedBytes: expectedBytes,
            progress: progress
        )
    }
    static func extract(
        entry: Entry,
        archive: URL,
        to destination: URL,
        expectedBytes: Int? = nil,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let out = try FileHandle(forWritingTo: destination)
        defer { try? out.close() }
        try extract(
            entry: entry,
            archive: archive,
            sink: FileExtractSink(out),
            expectedBytes: expectedBytes,
            progress: progress
        )
    }
    static func extractToMemory(
        entry: Entry,
        archive: URL,
        expectedBytes: Int? = nil,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws -> Data {
        let capacity = expectedBytes ?? entry.uncompressedSize
        let sink = MemoryExtractSink(capacity: max(0, capacity))
        try extract(
            entry: entry,
            archive: archive,
            sink: sink,
            expectedBytes: expectedBytes,
            progress: progress
        )
        return sink.data
    }
    private class ExtractSink {
        func write(_ bytes: Data) throws {}
        func finish() throws {}
    }
    private final class FileExtractSink: ExtractSink {
        private let handle: FileHandle
        init(_ handle: FileHandle) { self.handle = handle }
        override func write(_ bytes: Data) throws { try handle.write(contentsOf: bytes) }
        override func finish() throws { try handle.synchronize() }
    }
    private final class MemoryExtractSink: ExtractSink {
        private(set) var data: Data
        init(capacity: Int) {
            data = Data()
            if capacity > 0 {
                data.reserveCapacity(capacity)
            }
        }
        override func write(_ bytes: Data) throws { data.append(bytes) }
    }
    private static func extract(
        entry: Entry,
        archive: URL,
        sink: ExtractSink,
        expectedBytes: Int? = nil,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        try handle.seek(toOffset: entry.localHeaderOffset)
        let local = try readExact(handle, count: 30)
        guard readUInt32LE(local, 0) == 0x0403_4B50 else { throw ZipError.invalidSignature }
        let nameLen = Int(readUInt16LE(local, 26))
        let extraLen = Int(readUInt16LE(local, 28))
        _ = try readExact(handle, count: nameLen + extraLen)
        progress?(0, expectedBytes ?? entry.uncompressedSize)
        switch entry.compressionMethod {
        case 0:
            try copyStored(
                from: handle,
                to: sink,
                count: entry.compressedSize,
                progress: progress,
                expected: expectedBytes ?? entry.uncompressedSize
            )
        case 8:
            try inflateDeflate(
                from: handle,
                to: sink,
                compressedSize: entry.compressedSize,
                progress: progress,
                expected: expectedBytes ?? entry.uncompressedSize
            )
        default:
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }
        try sink.finish()
        let finalSize = expectedBytes ?? entry.uncompressedSize
        progress?(finalSize, finalSize)
    }
    private static func locateCentralDirectory(
        handle: FileHandle,
        fileSize: UInt64
    ) throws -> (offset: UInt64, size: UInt64, entries: UInt64) {
        let maxComment: UInt64 = 0xFFFF
        let searchLen = min(fileSize, 22 + maxComment)
        let start = fileSize - searchLen
        try handle.seek(toOffset: start)
        let tail = try readExact(handle, count: Int(searchLen))
        var eocdIndex: Int?
        if tail.count >= 22 {
            for i in stride(from: tail.count - 22, through: 0, by: -1) {
                if readUInt32LE(tail, i) == 0x0605_4B50 {
                    eocdIndex = i
                    break
                }
            }
        }
        guard let eocd = eocdIndex else { throw ZipError.invalidSignature }
        let absoluteEOCD = start + UInt64(eocd)
        let diskEntries = readUInt16LE(tail, eocd + 8)
        let totalEntries16 = readUInt16LE(tail, eocd + 10)
        let cdSize32 = readUInt32LE(tail, eocd + 12)
        let cdOffset32 = readUInt32LE(tail, eocd + 16)
        if totalEntries16 == 0xFFFF || cdSize32 == 0xFFFF_FFFF || cdOffset32 == 0xFFFF_FFFF || diskEntries == 0xFFFF {
            return try locateZIP64CentralDirectory(handle: handle, eocdOffset: absoluteEOCD)
        }
        return (UInt64(cdOffset32), UInt64(cdSize32), UInt64(totalEntries16))
    }
    private static func locateZIP64CentralDirectory(
        handle: FileHandle,
        eocdOffset: UInt64
    ) throws -> (offset: UInt64, size: UInt64, entries: UInt64) {
        guard eocdOffset >= 20 else { throw ZipError.truncated }
        let locatorOffset = eocdOffset - 20
        try handle.seek(toOffset: locatorOffset)
        let locator = try readExact(handle, count: 20)
        guard readUInt32LE(locator, 0) == 0x0706_4B50 else { throw ZipError.invalidSignature }
        let zip64EOCDOffset = readUInt64LE(locator, 8)
        try handle.seek(toOffset: zip64EOCDOffset)
        let header = try readExact(handle, count: 56)
        guard readUInt32LE(header, 0) == 0x0606_4B50 else { throw ZipError.invalidSignature }
        let entries = readUInt64LE(header, 32)
        let cdSize = readUInt64LE(header, 40)
        let cdOffset = readUInt64LE(header, 48)
        return (cdOffset, cdSize, entries)
    }
    private static func applyZIP64Extra(
        _ extra: Data,
        compressed: inout UInt64,
        uncompressed: inout UInt64,
        localOffset: inout UInt64
    ) {
        var i = 0
        while i + 4 <= extra.count {
            let headerID = readUInt16LE(extra, i)
            let size = Int(readUInt16LE(extra, i + 2))
            i += 4
            guard i + size <= extra.count else { return }
            if headerID == 0x0001 {
                var cursor = i
                if uncompressed == 0xFFFF_FFFF, cursor + 8 <= i + size {
                    uncompressed = readUInt64LE(extra, cursor)
                    cursor += 8
                }
                if compressed == 0xFFFF_FFFF, cursor + 8 <= i + size {
                    compressed = readUInt64LE(extra, cursor)
                    cursor += 8
                }
                if localOffset == 0xFFFF_FFFF, cursor + 8 <= i + size {
                    localOffset = readUInt64LE(extra, cursor)
                }
                return
            }
            i += size
        }
    }
    private static func decodeName(_ data: Data, utf8: Bool) -> String {
        if utf8, let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
    private static func copyStored(
        from handle: FileHandle,
        to sink: ExtractSink,
        count: UInt64,
        progress: DiffsplitterContent.MaterializeProgress?,
        expected: Int
    ) throws {
        var remaining = count
        var written = 0
        let chunkSize = 1024 * 1024
        while remaining > 0 {
            try Task.checkCancellation()
            let n = Int(min(UInt64(chunkSize), remaining))
            let chunk = try readExact(handle, count: n)
            try sink.write(chunk)
            remaining -= UInt64(n)
            written += n
            progress?(written, expected)
        }
    }
    private static func inflateDeflate(
        from handle: FileHandle,
        to sink: ExtractSink,
        compressedSize: UInt64,
        progress: DiffsplitterContent.MaterializeProgress?,
        expected: Int
    ) throws {
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw ZipError.inflateFailed }
        defer { inflateEnd(&stream) }
        var remaining = compressedSize
        var written = 0
        let inBufSize = 256 * 1024
        let outBufSize = 512 * 1024
        var inBuffer = Data(count: inBufSize)
        var outBuffer = Data(count: outBufSize)
        var inputAvail: uInt = 0
        var inputOffset = 0
        while true {
            try Task.checkCancellation()
            if inputAvail == 0, remaining > 0 {
                let n = Int(min(UInt64(inBufSize), remaining))
                let chunk = try readExact(handle, count: n)
                remaining -= UInt64(n)
                inBuffer.replaceSubrange(0..<n, with: chunk)
                inputAvail = uInt(n)
                inputOffset = 0
            }
            let status: Int32 = inBuffer.withUnsafeMutableBytes { inRaw in
                outBuffer.withUnsafeMutableBytes { outRaw in
                    let inBase = inRaw.bindMemory(to: UInt8.self).baseAddress!
                    let outBase = outRaw.bindMemory(to: UInt8.self).baseAddress!
                    stream.next_in = inBase.advanced(by: inputOffset)
                    stream.avail_in = inputAvail
                    stream.next_out = outBase
                    stream.avail_out = uInt(outBufSize)
                    let result = inflate(&stream, remaining == 0 && inputAvail == stream.avail_in ? Z_FINISH : Z_NO_FLUSH)
                    let consumed = Int(inputAvail) - Int(stream.avail_in)
                    inputOffset += consumed
                    inputAvail = stream.avail_in
                    return result
                }
            }
            let produced = outBufSize - Int(stream.avail_out)
            if produced > 0 {
                try sink.write(Data(outBuffer.prefix(produced)))
                written += produced
                progress?(written, expected)
            }
            if status == Z_STREAM_END {
                break
            }
            if status == Z_BUF_ERROR, inputAvail == 0, remaining == 0 {
                break
            }
            if status != Z_OK && status != Z_BUF_ERROR {
                throw ZipError.inflateFailed
            }
        }
    }
    private static func readExact(_ handle: FileHandle, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw ZipError.truncated
        }
        return data
    }
    private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
    private static func readUInt64LE(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(readUInt32LE(data, offset)) | (UInt64(readUInt32LE(data, offset + 4)) << 32)
    }
}
nonisolated enum DiffsplitterAEA {
    static let magic = Data("AEA1".utf8)
    private static let prologueProbeBytes = 256 * 1024
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
        if let id = try? archiveIdentifier(at: url), !id.isEmpty {
            lines.append("id: \(id)")
        }
        let authKeys = authDataKeys(in: probe)
        if !authKeys.isEmpty {
            lines.append("auth-data-keys:")
            for key in authKeys.sorted() {
                lines.append("  \(key)")
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
    static func resolveIpswExecutable() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ipsw",
            "/usr/local/bin/ipsw"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        if let path = which("ipsw") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    static func unwrapKeyWithIpsw(at url: URL) throws -> String? {
        guard let ipsw = resolveIpswExecutable() else { return nil }
        let output: String
        do {
            output = try DiffsplitterContainer.runProcess(
                executable: ipsw.path,
                arguments: ["fw", "aea", "--key", url.path]
            )
        } catch {
            do {
                output = try DiffsplitterContainer.runProcess(
                    executable: ipsw.path,
                    arguments: ["fw", "aea", url.path, "--key"]
                )
            } catch {
                return nil
            }
        }
        return parseKey(fromIpswOutput: output)
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
        if let keyValue, let normalized = normalizeKeyValue(keyValue) {
            try runAEADecrypt(input: input, output: output, extraArguments: [
                "-key-value", normalized
            ])
            return
        }
        do {
            try runAEADecrypt(input: input, output: output, extraArguments: ["-keychain"])
            return
        } catch {
        }
        if let unwrapped = try unwrapKeyWithIpsw(at: input),
           let normalized = normalizeKeyValue(unwrapped) {
            try runAEADecrypt(input: input, output: output, extraArguments: [
                "-key-value", normalized
            ])
            return
        }
        throw DiffsplitterContainer.ContainerError.aeaKeyRequired
    }
    static func decryptedOutputURL(for input: URL, in directory: URL) -> URL {
        var name = input.lastPathComponent
        if name.lowercased().hasSuffix(".aea") {
            name = String(name.dropLast(4))
        }
        if name.isEmpty { name = "aea-payload" }
        return directory.appendingPathComponent(name)
    }
    private static func runAEADecrypt(
        input: URL,
        output: URL,
        extraArguments: [String]
    ) throws {
        var args = [
            "decrypt",
            "-i", input.path,
            "-o", output.path
        ]
        args.append(contentsOf: extraArguments)
        do {
            _ = try DiffsplitterContainer.runProcess(
                executable: "/usr/bin/aea",
                arguments: args
            )
        } catch let error as DiffsplitterContainer.ContainerError {
            throw DiffsplitterContainer.ContainerError.aeaDecryptFailed(error.processDetail)
        } catch {
            throw DiffsplitterContainer.ContainerError.aeaDecryptFailed(error.localizedDescription)
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw DiffsplitterContainer.ContainerError.aeaDecryptFailed("aea produced no output")
        }
    }
    private static func archiveIdentifier(at url: URL) throws -> String {
        let raw = try DiffsplitterContainer.runProcess(
            executable: "/usr/bin/aea",
            arguments: ["id", "-i", url.path]
        )
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func authDataKeys(in probe: Data) -> [String] {
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
    static func parseKey(fromIpswOutput output: String) -> String? {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower.hasPrefix("base64:") || lower.hasPrefix("hex:") {
                return String(line)
            }
            if line.count >= 16,
               line.range(of: #"^[A-Za-z0-9+/=_-]+$"#, options: .regularExpression) != nil,
               !line.contains(" "),
               !lower.contains("error"),
               !lower.contains("usage") {
                return line
            }
        }
        return nil
    }
    private static func which(_ name: String) -> String? {
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in pathEnv.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
nonisolated enum DiffsplitterImage4 {
    static let maxInlineOctetBytes = 64
    static func isImage4Extension(of url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "im4m", "im4p", "im4r":
            return true
        default:
            return false
        }
    }
    static func looksLike(_ data: Data) -> Bool {
        guard data.count >= 10 else { return false }
        guard data[0] == 0x30 else { return false }
        if let marker = findIA5FourCC(in: data.prefix(64)) {
            return marker == "IM4M" || marker == "IM4P" || marker == "IM4R"
        }
        return false
    }
    static func summarize(_ data: Data) throws -> [String] {
        var reader = DERReader(data)
        let root = try reader.readNode()
        var lines: [String] = [
            "format: Image4",
            "size: \(data.count)",
            "sha256: \(sha256Hex(data))"
        ]
        try appendSummary(of: root, depth: 0, into: &lines)
        return lines
    }
    private static func findIA5FourCC(in data: Data.SubSequence) -> String? {
        var i = data.startIndex
        while i + 6 <= data.endIndex {
            if data[i] == 0x16, data[i + 1] == 0x04 {
                let bytes = data[(i + 2)..<(i + 6)]
                if let s = String(bytes: bytes, encoding: .ascii), s.count == 4,
                   s.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) {
                    return s
                }
            }
            i = data.index(after: i)
        }
        return nil
    }
    private static func appendSummary(of node: DERNode, depth: Int, into lines: inout [String]) throws {
        let indent = String(repeating: "  ", count: depth)
        switch node.content {
        case .constructed(let children):
            let label = node.tagLabel
            lines.append("\(indent)\(label) {")
            let ordered: [DERNode]
            if node.tagNumber == 0x11 {
                ordered = children.sorted { left, right in
                    fourCCKey(left).localizedStandardCompare(fourCCKey(right)) == .orderedAscending
                }
            } else {
                ordered = children
            }
            for child in ordered {
                try appendSummary(of: child, depth: depth + 1, into: &lines)
            }
            lines.append("\(indent)}")
        case .primitive(let value):
            lines.append("\(indent)\(formatPrimitive(tag: node.tagNumber, class: node.tagClass, value: value))")
        }
    }
    private static func fourCCKey(_ node: DERNode) -> String {
        if case .constructed(let children) = node.content {
            for child in children {
                if case .primitive(let value) = child.content,
                   child.tagNumber == 0x16,
                   let s = String(bytes: value, encoding: .ascii),
                   s.count == 4 {
                    return s
                }
            }
        }
        if case .primitive(let value) = node.content,
           node.tagNumber == 0x16,
           let s = String(bytes: value, encoding: .ascii) {
            return s
        }
        return String(format: "%u.%u", node.tagClass.rawValue, node.tagNumber)
    }
    private static func formatPrimitive(tag: UInt32, class tagClass: DERTagClass, value: Data) -> String {
        if tag == 0x16 || tag == 0x0C || tag == 0x13,
           let s = String(bytes: value, encoding: .utf8) ?? String(bytes: value, encoding: .ascii) {
            return "\(tagName(tag, class: tagClass)): \"\(s)\""
        }
        if tag == 0x01, let b = value.first {
            return "BOOLEAN: \(b == 0 ? "false" : "true")"
        }
        if tag == 0x02 {
            return "INTEGER: \(integerDescription(value))"
        }
        if tag == 0x04 {
            if value.count <= maxInlineOctetBytes {
                return "OCTET[\(value.count)]: \(value.map { String(format: "%02x", $0) }.joined())"
            }
            return "OCTET[\(value.count)]: sha256=\(sha256Hex(value))"
        }
        if tag == 0x05 {
            return "NULL"
        }
        if tag == 0x06 {
            return "OID: \(oidDescription(value))"
        }
        if value.count <= maxInlineOctetBytes {
            return "\(tagName(tag, class: tagClass))[\(value.count)]: \(value.map { String(format: "%02x", $0) }.joined())"
        }
        return "\(tagName(tag, class: tagClass))[\(value.count)]: sha256=\(sha256Hex(value))"
    }
    private static func tagName(_ tag: UInt32, class tagClass: DERTagClass) -> String {
        if tagClass == .universal {
            switch tag {
            case 0x01: return "BOOLEAN"
            case 0x02: return "INTEGER"
            case 0x04: return "OCTET"
            case 0x05: return "NULL"
            case 0x06: return "OID"
            case 0x0C: return "UTF8String"
            case 0x13: return "PrintableString"
            case 0x16: return "IA5String"
            case 0x17: return "UTCTime"
            case 0x18: return "GeneralizedTime"
            case 0x10: return "SEQUENCE"
            case 0x11: return "SET"
            default: break
            }
        }
        if let fourCC = fourCC(from: tag), tagClass != .universal {
            return "[\(fourCC)]"
        }
        return "TAG(\(tagClass.rawValue):\(tag))"
    }
    private static func fourCC(from tag: UInt32) -> String? {
        let bytes = [
            UInt8((tag >> 24) & 0xff),
            UInt8((tag >> 16) & 0xff),
            UInt8((tag >> 8) & 0xff),
            UInt8(tag & 0xff)
        ]
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }
    private static func integerDescription(_ value: Data) -> String {
        if value.isEmpty { return "0" }
        if value.count <= 8 {
            var n: UInt64 = 0
            for b in value { n = (n << 8) | UInt64(b) }
            return "0x" + String(n, radix: 16, uppercase: true) + " (\(n))"
        }
        return "0x" + value.map { String(format: "%02X", $0) }.joined()
    }
    private static func oidDescription(_ value: Data) -> String {
        guard let first = value.first else { return "" }
        var parts: [String] = ["\(Int(first / 40))", "\(Int(first % 40))"]
        var acc = 0
        for b in value.dropFirst() {
            acc = (acc << 7) | Int(b & 0x7f)
            if b & 0x80 == 0 {
                parts.append("\(acc)")
                acc = 0
            }
        }
        return parts.joined(separator: ".")
    }
    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
private nonisolated enum DERTagClass: UInt8 {
    case universal = 0
    case application = 1
    case contextSpecific = 2
    case `private` = 3
}
private nonisolated struct DERNode {
    let tagClass: DERTagClass
    let tagNumber: UInt32
    let content: Content
    enum Content {
        case primitive(Data)
        case constructed([DERNode])
    }
    var tagLabel: String {
        if tagClass == .universal {
            switch tagNumber {
            case 0x10: return "SEQUENCE"
            case 0x11: return "SET"
            default: break
            }
        }
        if let fourCC = DiffsplitterImage4FourCC.string(from: tagNumber), tagClass != .universal {
            return "[\(fourCC)]"
        }
        return "TAG(\(tagClass.rawValue):\(tagNumber))"
    }
}
private nonisolated enum DiffsplitterImage4FourCC {
    static func string(from tag: UInt32) -> String? {
        let bytes = [
            UInt8((tag >> 24) & 0xff),
            UInt8((tag >> 16) & 0xff),
            UInt8((tag >> 8) & 0xff),
            UInt8(tag & 0xff)
        ]
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }
}
private nonisolated struct DERReader {
    private let data: Data
    private var index: Int = 0
    init(_ data: Data) {
        self.data = data
    }
    mutating func readNode() throws -> DERNode {
        let start = index
        let (tagClass, constructed, tagNumber) = try readTag()
        let length = try readLength()
        let end = index + length
        guard end <= data.count else {
            throw DiffsplitterEngine.ReadError.unreadable
        }
        if constructed {
            var children: [DERNode] = []
            let childEnd = end
            while index < childEnd {
                children.append(try readNode())
            }
            guard index == childEnd else {
                throw DiffsplitterEngine.ReadError.unreadable
            }
            return DERNode(tagClass: tagClass, tagNumber: tagNumber, content: .constructed(children))
        } else {
            let value = data.subdata(in: index..<end)
            index = end
            _ = start
            return DERNode(tagClass: tagClass, tagNumber: tagNumber, content: .primitive(value))
        }
    }
    private mutating func readTag() throws -> (DERTagClass, Bool, UInt32) {
        guard index < data.count else { throw DiffsplitterEngine.ReadError.unreadable }
        let first = data[index]
        index += 1
        let tagClass = DERTagClass(rawValue: first >> 6) ?? .universal
        let constructed = (first & 0x20) != 0
        var tagNumber = UInt32(first & 0x1f)
        if tagNumber == 0x1f {
            tagNumber = 0
            while true {
                guard index < data.count else { throw DiffsplitterEngine.ReadError.unreadable }
                let b = data[index]
                index += 1
                tagNumber = (tagNumber << 7) | UInt32(b & 0x7f)
                if b & 0x80 == 0 { break }
            }
        }
        return (tagClass, constructed, tagNumber)
    }
    private mutating func readLength() throws -> Int {
        guard index < data.count else { throw DiffsplitterEngine.ReadError.unreadable }
        let first = data[index]
        index += 1
        if first & 0x80 == 0 {
            return Int(first)
        }
        let count = Int(first & 0x7f)
        guard count > 0, count <= 4, index + count <= data.count else {
            throw DiffsplitterEngine.ReadError.unreadable
        }
        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }
}
nonisolated enum DiffsplitterBinaryDump {
    static let bytesPerLine = 16
    static let defaultWindowLines = DiffsplitterSettings.defaultHexWindowLines
    static let maxWindowLines = DiffsplitterSettings.hexWindowLinesRange.upperBound
    static let pageOverlapLines = 8
    static var preferredWindowLines: Int { DiffsplitterSettings.hexWindowLines() }

    final class MemoryBuffer: @unchecked Sendable {
        let data: Data
        init(_ data: Data) { self.data = data }
    }

    enum ByteSource: Equatable {
        case file(URL)
        case memory(MemoryBuffer)

        static func == (lhs: ByteSource, rhs: ByteSource) -> Bool {
            switch (lhs, rhs) {
            case let (.file(a), .file(b)):
                return a == b
            case let (.memory(a), .memory(b)):
                return a === b
            default:
                return false
            }
        }

        var byteCount: Int {
            switch self {
            case .file(let url):
                return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            case .memory(let buffer):
                return buffer.data.count
            }
        }
    }

    struct CostEstimate: Equatable {
        let diskBytes: Int
        let windowMemoryBytes: Int
        let backingMemoryBytes: Int
        let leftBytes: Int
        let rightBytes: Int
        let preferDiskTemp: Bool
        var totalSourceBytes: Int { leftBytes + rightBytes }
        var memoryLabel: String {
            if backingMemoryBytes > 0 {
                return L10n.f(
                    "About %@ in memory for materialized files, plus %@ for the visible window",
                    byteCountString(backingMemoryBytes),
                    byteCountString(windowMemoryBytes)
                )
            }
            return L10n.f("About %@ in memory for the visible window", byteCountString(windowMemoryBytes))
        }
        var promptDetail: String {
            if preferDiskTemp {
                return L10n.f(
                    "%@.\nOnly the visible hex window stays in memory; the rest stays on disk until you scroll to it.",
                    memoryLabel
                )
            }
            return L10n.f(
                "%@.\nMaterialized files are kept in memory; only the visible hex window is formatted until you scroll.",
                memoryLabel
            )
        }
    }
    struct HexRow: Identifiable, Equatable, Hashable {
        enum Kind: Equatable, Hashable {
            case equal
            case insert
            case delete
            case replace
        }
        let id: Int
        let offset: UInt64
        let leftText: String?
        let rightText: String?
        let kind: Kind
    }
    struct Session: Equatable {
        let leftSource: ByteSource?
        let rightSource: ByteSource?
        let leftByteCount: Int
        let rightByteCount: Int
        var windowStartLine: Int
        var windowLineCount: Int
        var rows: [HexRow]
        var leftURL: URL? {
            if case .file(let url) = leftSource { return url }
            return nil
        }
        var rightURL: URL? {
            if case .file(let url) = rightSource { return url }
            return nil
        }
        var totalLines: Int {
            let maxBytes = max(leftByteCount, rightByteCount)
            guard maxBytes > 0 else { return 0 }
            return (maxBytes + bytesPerLine - 1) / bytesPerLine
        }
        var windowEndLine: Int {
            min(totalLines, windowStartLine + windowLineCount)
        }
        var windowByteRange: Range<Int> {
            let start = windowStartLine * bytesPerLine
            let end = min(max(leftByteCount, rightByteCount), windowEndLine * bytesPerLine)
            return start..<max(start, end)
        }
        var isEmbeddedSnapshot: Bool { leftSource == nil && rightSource == nil }
    }
    static func estimate(
        leftBytes: Int,
        rightBytes: Int,
        leftNeedsMaterialize: Bool,
        rightNeedsMaterialize: Bool,
        windowLines: Int = DiffsplitterSettings.hexWindowLines(),
        preferDiskTemp: Bool = DiffsplitterSettings.preferDiskTempForLargeFiles()
    ) -> CostEstimate {
        var disk = 0
        var backingMemory = 0
        if leftNeedsMaterialize {
            if preferDiskTemp {
                disk += max(0, leftBytes)
            } else {
                backingMemory += max(0, leftBytes)
            }
        }
        if rightNeedsMaterialize {
            if preferDiskTemp {
                disk += max(0, rightBytes)
            } else {
                backingMemory += max(0, rightBytes)
            }
        }
        let perLine = 96
        let memory = windowLines * perLine * ((leftBytes > 0 ? 1 : 0) + (rightBytes > 0 ? 1 : 0) + 1)
        return CostEstimate(
            diskBytes: disk,
            windowMemoryBytes: memory,
            backingMemoryBytes: backingMemory,
            leftBytes: max(0, leftBytes),
            rightBytes: max(0, rightBytes),
            preferDiskTemp: preferDiskTemp
        )
    }
    static func byteCountString(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    static func loadWindow(
        leftURL: URL?,
        rightURL: URL?,
        leftByteCount: Int,
        rightByteCount: Int,
        startLine: Int,
        lineCount: Int = DiffsplitterSettings.hexWindowLines()
    ) throws -> Session {
        try loadWindow(
            left: leftURL.map { .file($0) },
            right: rightURL.map { .file($0) },
            leftByteCount: leftByteCount,
            rightByteCount: rightByteCount,
            startLine: startLine,
            lineCount: lineCount
        )
    }
    static func loadWindow(
        left: ByteSource?,
        right: ByteSource?,
        leftByteCount: Int,
        rightByteCount: Int,
        startLine: Int,
        lineCount: Int = DiffsplitterSettings.hexWindowLines()
    ) throws -> Session {
        let totalLines: Int = {
            let maxBytes = max(leftByteCount, rightByteCount)
            guard maxBytes > 0 else { return 0 }
            return (maxBytes + bytesPerLine - 1) / bytesPerLine
        }()
        let clampedCount = min(max(1, lineCount), maxWindowLines)
        let clampedStart = max(0, min(startLine, max(0, totalLines - 1)))
        let endLine = min(totalLines, clampedStart + clampedCount)
        var rows: [HexRow] = []
        rows.reserveCapacity(max(0, endLine - clampedStart))
        let leftHandle = try openHandle(left)
        defer { try? leftHandle?.close() }
        let rightHandle = try openHandle(right)
        defer { try? rightHandle?.close() }
        let leftData = memoryData(left)
        let rightData = memoryData(right)
        for line in clampedStart..<endLine {
            try Task.checkCancellation()
            let offset = UInt64(line * bytesPerLine)
            let leftSlice = try readLineBytes(
                handle: leftHandle,
                data: leftData,
                offset: offset,
                fileSize: leftByteCount
            )
            let rightSlice = try readLineBytes(
                handle: rightHandle,
                data: rightData,
                offset: offset,
                fileSize: rightByteCount
            )
            let leftText = leftSlice.map { formatLine(offset: offset, bytes: $0) }
            let rightText = rightSlice.map { formatLine(offset: offset, bytes: $0) }
            let kind: HexRow.Kind
            switch (leftSlice, rightSlice) {
            case (nil, nil):
                kind = .equal
            case (nil, _?):
                kind = .insert
            case (_?, nil):
                kind = .delete
            case let (left?, right?):
                kind = left == right ? .equal : .replace
            }
            rows.append(HexRow(
                id: line,
                offset: offset,
                leftText: leftText,
                rightText: rightText,
                kind: kind
            ))
        }
        return Session(
            leftSource: left,
            rightSource: right,
            leftByteCount: leftByteCount,
            rightByteCount: rightByteCount,
            windowStartLine: clampedStart,
            windowLineCount: clampedCount,
            rows: rows
        )
    }
    static func pageUp(_ session: Session) throws -> Session {
        guard !session.isEmbeddedSnapshot else { return session }
        let step = max(1, session.windowLineCount - pageOverlapLines)
        let start = max(0, session.windowStartLine - step)
        return try loadWindow(
            left: session.leftSource,
            right: session.rightSource,
            leftByteCount: session.leftByteCount,
            rightByteCount: session.rightByteCount,
            startLine: start,
            lineCount: session.windowLineCount
        )
    }
    static func pageDown(_ session: Session) throws -> Session {
        guard !session.isEmbeddedSnapshot else { return session }
        let step = max(1, session.windowLineCount - pageOverlapLines)
        let start = min(max(0, session.totalLines - 1), session.windowStartLine + step)
        return try loadWindow(
            left: session.leftSource,
            right: session.rightSource,
            leftByteCount: session.leftByteCount,
            rightByteCount: session.rightByteCount,
            startLine: start,
            lineCount: session.windowLineCount
        )
    }
    static func jump(toOffsetBytes offset: Int, session: Session) throws -> Session {
        guard !session.isEmbeddedSnapshot else { return session }
        let line = max(0, offset) / bytesPerLine
        return try loadWindow(
            left: session.leftSource,
            right: session.rightSource,
            leftByteCount: session.leftByteCount,
            rightByteCount: session.rightByteCount,
            startLine: line,
            lineCount: session.windowLineCount
        )
    }
    static func alignedRowsForExport(
        from session: Session,
        maxLines: Int = DiffsplitterEngine.maxAlignLines
    ) throws -> [DiffsplitterEngine.AlignedRow] {
        if session.isEmbeddedSnapshot {
            return alignedRows(fromHexRows: session.rows)
        }
        let total = min(session.totalLines, max(0, maxLines))
        guard total > 0 else { return [] }
        var rows: [DiffsplitterEngine.AlignedRow] = []
        rows.reserveCapacity(total)
        let leftHandle = try openHandle(session.leftSource)
        defer { try? leftHandle?.close() }
        let rightHandle = try openHandle(session.rightSource)
        defer { try? rightHandle?.close() }
        let leftData = memoryData(session.leftSource)
        let rightData = memoryData(session.rightSource)
        for line in 0..<total {
            try Task.checkCancellation()
            let offset = UInt64(line * bytesPerLine)
            let leftSlice = try readLineBytes(
                handle: leftHandle,
                data: leftData,
                offset: offset,
                fileSize: session.leftByteCount
            )
            let rightSlice = try readLineBytes(
                handle: rightHandle,
                data: rightData,
                offset: offset,
                fileSize: session.rightByteCount
            )
            let leftText = leftSlice.map { formatLine(offset: offset, bytes: $0) }
            let rightText = rightSlice.map { formatLine(offset: offset, bytes: $0) }
            let kind: DiffsplitterEngine.RowKind
            switch (leftSlice, rightSlice) {
            case (nil, nil):
                continue
            case (nil, _?):
                kind = .insert
            case (_?, nil):
                kind = .delete
            case let (left?, right?):
                kind = left == right ? .equal : .replace
            }
            rows.append(DiffsplitterEngine.AlignedRow(
                id: rows.count,
                leftLineNumber: leftText == nil ? nil : line + 1,
                rightLineNumber: rightText == nil ? nil : line + 1,
                leftText: leftText,
                rightText: rightText,
                kind: kind
            ))
        }
        return rows
    }
    static func alignedRows(fromHexRows rows: [HexRow]) -> [DiffsplitterEngine.AlignedRow] {
        rows.enumerated().map { index, row in
            let kind: DiffsplitterEngine.RowKind
            switch row.kind {
            case .equal: kind = .equal
            case .insert: kind = .insert
            case .delete: kind = .delete
            case .replace: kind = .replace
            }
            return DiffsplitterEngine.AlignedRow(
                id: index,
                leftLineNumber: row.leftText == nil ? nil : index + 1,
                rightLineNumber: row.rightText == nil ? nil : index + 1,
                leftText: row.leftText,
                rightText: row.rightText,
                kind: kind
            )
        }
    }
    static func sessionFromEmbeddedAlignedRows(
        _ alignedRows: [DiffsplitterEngine.AlignedRow]
    ) -> Session {
        let hexRows: [HexRow] = alignedRows.enumerated().map { index, row in
            let kind: HexRow.Kind
            switch row.kind {
            case .equal: kind = .equal
            case .insert: kind = .insert
            case .delete: kind = .delete
            case .replace: kind = .replace
            }
            let offset = parseOffset(from: row.leftText)
                ?? parseOffset(from: row.rightText)
                ?? UInt64(index * bytesPerLine)
            return HexRow(
                id: index,
                offset: offset,
                leftText: row.leftText,
                rightText: row.rightText,
                kind: kind
            )
        }
        let lineCount = max(hexRows.count, 1)
        let byteCount = lineCount * bytesPerLine
        return Session(
            leftSource: nil,
            rightSource: nil,
            leftByteCount: byteCount,
            rightByteCount: byteCount,
            windowStartLine: 0,
            windowLineCount: lineCount,
            rows: hexRows
        )
    }
    static func looksLikeHexDump(_ rows: [DiffsplitterEngine.AlignedRow]) -> Bool {
        let samples = rows.prefix(12).compactMap { $0.leftText ?? $0.rightText }
        guard samples.count >= 2 else { return false }
        return samples.allSatisfy(looksLikeHexDumpLine)
    }
    static func looksLikeHexDumpLine(_ text: String) -> Bool {
        guard text.count >= 13 else { return false }
        let prefix = text.prefix(8)
        guard prefix.allSatisfy(\.isHexDigit) else { return false }
        guard text.dropFirst(8).hasPrefix("  ") else { return false }
        guard text.contains("|"), text.hasSuffix("|") else { return false }
        return true
    }
    private static func parseOffset(from text: String?) -> UInt64? {
        guard let text, text.count >= 8 else { return nil }
        return UInt64(text.prefix(8), radix: 16)
    }
    private static func openHandle(_ source: ByteSource?) throws -> FileHandle? {
        guard case .file(let url) = source else { return nil }
        return try FileHandle(forReadingFrom: url)
    }
    private static func memoryData(_ source: ByteSource?) -> Data? {
        guard case .memory(let buffer) = source else { return nil }
        return buffer.data
    }
    private static func readLineBytes(
        handle: FileHandle?,
        data: Data?,
        offset: UInt64,
        fileSize: Int
    ) throws -> Data? {
        guard fileSize > 0, offset < UInt64(fileSize) else { return nil }
        let remaining = fileSize - Int(offset)
        let count = min(bytesPerLine, remaining)
        if let data {
            let start = Int(offset)
            return data.subdata(in: start..<(start + count))
        }
        guard let handle else { return nil }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }
    private static func formatLine(offset: UInt64, bytes: Data) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        let paddedHex = hex.padding(toLength: bytesPerLine * 3 - 1, withPad: " ", startingAt: 0)
        let ascii = String(bytes.map { byte -> Character in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "."
        })
        return String(format: "%08llx  %@  |%@|", offset, paddedHex, ascii)
    }
}
nonisolated enum DiffsplitterContent {
    typealias MaterializeProgress = @Sendable (_ completed: Int, _ expected: Int?) -> Void
    static let hexEncodingName = "Hex"
    static func prefersHexDump(
        url: URL?,
        session: DiffsplitterContainerSession?,
        progress: MaterializeProgress? = nil
    ) throws -> Bool {
        guard let url else { return false }
        let resolved = try DiffsplitterContainer.resolvedFileURL(
            for: url,
            session: session,
            progress: progress
        )
        return try prefersHexDump(resolvedURL: resolved)
    }
    static func prefersHexDump(resolvedURL: URL) throws -> Bool {
        try prefersHexDump(at: resolvedURL)
    }
    static func decode(
        url: URL?,
        session: DiffsplitterContainerSession?,
        progress: MaterializeProgress? = nil
    ) throws -> DiffsplitterEngine.TextContent {
        guard let url else {
            return DiffsplitterEngine.TextContent(lines: [], encodingName: "empty")
        }
        let resolved = try DiffsplitterContainer.resolvedFileURL(
            for: url,
            session: session,
            progress: progress
        )
        if DiffsplitterAEA.isAEAExtension(of: resolved) || DiffsplitterAEA.looksLikeFile(at: resolved) {
            if let lines = try? DiffsplitterAEA.summarize(at: resolved), !lines.isEmpty {
                return DiffsplitterEngine.TextContent(lines: lines, encodingName: "AEA")
            }
        }
        if DiffsplitterImage4.isImage4Extension(of: resolved) {
            let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
            if let lines = try? DiffsplitterImage4.summarize(data), !lines.isEmpty {
                return DiffsplitterEngine.TextContent(lines: lines, encodingName: "Image4")
            }
        }
        let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
        return try decode(data: data, displayURL: resolved)
    }
    static func decode(data: Data, displayURL: URL) throws -> DiffsplitterEngine.TextContent {
        if DiffsplitterAEA.looksLike(data) || DiffsplitterAEA.isAEAExtension(of: displayURL) {
            if let lines = try? DiffsplitterAEA.summarize(data), !lines.isEmpty {
                return DiffsplitterEngine.TextContent(lines: lines, encodingName: "AEA")
            }
        }
        if DiffsplitterImage4.looksLike(data) || DiffsplitterImage4.isImage4Extension(of: displayURL) {
            if let lines = try? DiffsplitterImage4.summarize(data), !lines.isEmpty {
                return DiffsplitterEngine.TextContent(lines: lines, encodingName: "Image4")
            }
        }
        if let plistLines = plistXMLLines(from: data) {
            return DiffsplitterEngine.TextContent(lines: plistLines, encodingName: "Property List")
        }
        if !looksBinary(data) {
            if let string = String(data: data, encoding: .utf8) {
                return DiffsplitterEngine.TextContent(lines: splitLines(string), encodingName: "UTF-8")
            }
            if let string = String(data: data, encoding: .utf16) {
                return DiffsplitterEngine.TextContent(lines: splitLines(string), encodingName: "UTF-16")
            }
            if let string = String(data: data, encoding: .isoLatin1) {
                return DiffsplitterEngine.TextContent(lines: splitLines(string), encodingName: "ISO Latin-1")
            }
        }
        return DiffsplitterEngine.TextContent(
            lines: [
                "format: hex",
                "size: \(data.count)"
            ],
            encodingName: hexEncodingName
        )
    }
    static func binaryMetadataLines(url: URL?, byteCount: Int?) -> [String] {
        var lines = [
            "format: binary",
            "size: \(byteCount ?? -1)"
        ]
        if let url {
            lines.insert("path: \(url.lastPathComponent)", at: 1)
            if let zip = DiffsplitterContainer.zipStubMetadata(at: url) {
                lines.append("zip-crc32: \(String(format: "%08x", zip.crc32))")
                lines.append("zip-uncompressed: \(zip.uncompressedSize)")
            }
        }
        lines.append(
            DiffsplitterSettings.preferDiskTempForLargeFiles()
                ? "note: open Inspect Dump for a windowed hex view (disk-backed)"
                : "note: open Inspect Dump for a windowed hex view (memory-backed)"
        )
        return lines
    }
    private static func prefersHexDump(at resolved: URL) throws -> Bool {
        if DiffsplitterAEA.isAEAExtension(of: resolved) || DiffsplitterAEA.looksLikeFile(at: resolved) {
            if let lines = try? DiffsplitterAEA.summarize(at: resolved), !lines.isEmpty {
                return false
            }
        }
        if DiffsplitterImage4.isImage4Extension(of: resolved) {
            let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
            if let lines = try? DiffsplitterImage4.summarize(data), !lines.isEmpty {
                return false
            }
        }
        let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
        if DiffsplitterAEA.looksLike(data) {
            if let lines = try? DiffsplitterAEA.summarize(data), !lines.isEmpty {
                return false
            }
        }
        if DiffsplitterImage4.looksLike(data) {
            if let lines = try? DiffsplitterImage4.summarize(data), !lines.isEmpty {
                return false
            }
        }
        if plistXMLLines(from: data) != nil {
            return false
        }
        if !looksBinary(data) {
            if String(data: data, encoding: .utf8) != nil { return false }
            if String(data: data, encoding: .utf16) != nil { return false }
            if String(data: data, encoding: .isoLatin1) != nil { return false }
        }
        return true
    }
    private static func plistXMLLines(from data: Data) -> [String]? {
        guard !data.isEmpty else { return nil }
        let isBinary = data.starts(with: Data("bplist".utf8))
        let isXML = data.starts(with: Data("<?xml".utf8)) || data.starts(with: Data("<plist".utf8))
        guard isBinary || isXML else { return nil }
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let xml = try PropertyListSerialization.data(
                fromPropertyList: object,
                format: .xml,
                options: 0
            )
            guard let string = String(data: xml, encoding: .utf8) else { return nil }
            return splitLines(string)
        } catch {
            return nil
        }
    }
    private static func looksBinary(_ data: Data) -> Bool {
        if data.contains(0) { return true }
        let sample = data.prefix(8_192)
        guard !sample.isEmpty else { return false }
        let nonPrintable = sample.reduce(into: 0) { count, byte in
            if byte < 9 || (byte > 13 && byte < 32) { count += 1 }
        }
        return Double(nonPrintable) / Double(sample.count) > 0.30
    }
    private static func splitLines(_ string: String) -> [String] {
        if string.isEmpty { return [] }
        var lines = string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if string.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
nonisolated struct DiffsplitterZipMember: Sendable, Equatable {
    let archiveURL: URL
    let memberPath: String
    let crc32: UInt32
    let uncompressedSize: Int
}
nonisolated final class DiffsplitterContainerSession: @unchecked Sendable {
    private let root: URL
    private var mountPoints: [URL] = []
    private var zipMembersByStubPath: [String: DiffsplitterZipMember] = [:]
    private var inspectMaterializationDirs: [URL] = []
    private var inspectMemoryByStubPath: [String: Data] = [:]
    private let lock = NSRecursiveLock()
    private var closed = false
    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Diffsplitter", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base
    }
    func makeWorkDirectory(named prefix: String) throws -> URL {
        let url = try makeWorkPath(named: prefix)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func makeWorkPath(named prefix: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { throw DiffsplitterContainer.ContainerError.unreadable }
        return root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }
    func registerZipMemberStub(
        relativePath: String,
        archive: URL,
        memberPath: String,
        crc32: UInt32,
        uncompressedSize: Int
    ) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { throw DiffsplitterContainer.ContainerError.unreadable }
        let stubRoot = root.appendingPathComponent("zip-stubs", isDirectory: true)
        let stubURL = stubRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: stubURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: stubURL.path) {
            FileManager.default.createFile(atPath: stubURL.path, contents: Data())
        }
        let member = DiffsplitterZipMember(
            archiveURL: archive,
            memberPath: memberPath,
            crc32: crc32,
            uncompressedSize: uncompressedSize
        )
        zipMembersByStubPath[stubURL.path] = member
        let meta = StubSidecar(
            archivePath: archive.path,
            memberPath: memberPath,
            crc32: crc32,
            uncompressedSize: uncompressedSize
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: Self.sidecarURL(forStub: stubURL), options: .atomic)
        return stubURL
    }
    fileprivate struct StubSidecar: Codable {
        let archivePath: String
        let memberPath: String
        let crc32: UInt32
        let uncompressedSize: Int
    }
    fileprivate static func sidecarURL(forStub url: URL) -> URL {
        url.appendingPathExtension("dsmeta")
    }
    func zipMember(forStubURL url: URL) -> DiffsplitterZipMember? {
        lock.lock()
        defer { lock.unlock() }
        return zipMembersByStubPath[url.path]
    }
    func unloadInspectMaterializations() {
        lock.lock()
        let dirs = inspectMaterializationDirs
        inspectMaterializationDirs.removeAll()
        inspectMemoryByStubPath.removeAll()
        lock.unlock()
        for dir in dirs {
            try? FileManager.default.removeItem(at: dir)
        }
    }
    func materializeZipMember(
        forStubURL url: URL,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws -> URL {
        try materializeZipMember(
            forStubURL: url,
            durable: false,
            progress: progress
        )
    }
    func materializeZipMemberToMemory(
        forStubURL url: URL,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws -> Data {
        lock.lock()
        if let cached = inspectMemoryByStubPath[url.path] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let member = zipMember(forStubURL: url) ?? DiffsplitterContainer.zipStubMetadata(at: url) else {
            throw DiffsplitterContainer.ContainerError.unreadable
        }
        let data = try DiffsplitterContainer.extractZipMemberToMemory(
            archive: member.archiveURL,
            memberPath: member.memberPath,
            expectedBytes: member.uncompressedSize,
            progress: progress
        )
        lock.lock()
        inspectMemoryByStubPath[url.path] = data
        lock.unlock()
        return data
    }
    func materializeZipMemberForExpansion(
        forStubURL url: URL,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws -> URL {
        try materializeZipMember(
            forStubURL: url,
            durable: true,
            progress: progress
        )
    }
    private func materializeZipMember(
        forStubURL url: URL,
        durable: Bool,
        progress: DiffsplitterContent.MaterializeProgress?
    ) throws -> URL {
        guard let member = zipMember(forStubURL: url) ?? DiffsplitterContainer.zipStubMetadata(at: url) else {
            throw DiffsplitterContainer.ContainerError.unreadable
        }
        let outDir = try makeWorkDirectory(named: durable ? "zip-expand" : "zip-member")
        if !durable {
            lock.lock()
            inspectMaterializationDirs.append(outDir)
            lock.unlock()
        }
        let safeName = (member.memberPath as NSString).lastPathComponent
        let outURL = outDir.appendingPathComponent(safeName.isEmpty ? "member" : safeName)
        try DiffsplitterContainer.extractZipMember(
            archive: member.archiveURL,
            memberPath: member.memberPath,
            to: outURL,
            expectedBytes: member.uncompressedSize,
            progress: progress
        )
        return outURL
    }
    func attachDiskImage(_ image: URL, mountPoint: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { throw DiffsplitterContainer.ContainerError.unreadable }
        try? FileManager.default.removeItem(at: mountPoint)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        do {
            try DiffsplitterContainer.attachDiskImage(image, mountPoint: mountPoint)
        } catch let error as DiffsplitterContainer.ContainerError {
            throw DiffsplitterContainer.ContainerError.mountFailed(error.processDetail)
        } catch {
            throw DiffsplitterContainer.ContainerError.mountFailed(error.localizedDescription)
        }
        mountPoints.append(mountPoint)
    }
    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        for mount in mountPoints.reversed() {
            DiffsplitterContainer.detachDiskImage(at: mount)
        }
        mountPoints.removeAll()
        zipMembersByStubPath.removeAll()
        inspectMaterializationDirs.removeAll()
        inspectMemoryByStubPath.removeAll()
        try? FileManager.default.removeItem(at: root)
    }
    deinit {
        close()
    }
}
nonisolated enum DiffsplitterContainer {
    static var maxNestDepth: Int { DiffsplitterSettings.maxNestDepth() }
    static var maxEntries: Int { DiffsplitterSettings.maxEntries() }
    enum Kind: Equatable {
        case directory
        case zipFamily
        case pkg
        case xip
        case dmg
        case aea
    }
    enum ContainerError: LocalizedError {
        case unreadable
        case expandFailed(String)
        case tooDeep
        case tooManyEntries
        case mountFailed(String)
        case processFailed(String)
        case aeaKeyRequired
        case aeaDecryptFailed(String)
        var errorDescription: String? {
            switch self {
            case .unreadable:
                return L10n.t("The selected item could not be read.")
            case .expandFailed(let detail):
                return L10n.f("Could not expand the archive: %@", detail)
            case .tooDeep:
                return L10n.t("Nested archives are too deep to expand in Diffsplitter.")
            case .tooManyEntries:
                return L10n.t("This archive has too many entries to compare in Diffsplitter.")
            case .mountFailed(let detail):
                return L10n.f("Could not mount the disk image: %@", detail)
            case .processFailed(let detail):
                return L10n.f("Could not expand the archive: %@", detail)
            case .aeaKeyRequired:
                return L10n.t("This Apple Encrypted Archive needs a decryption key.")
            case .aeaDecryptFailed(let detail):
                return L10n.f("Could not decrypt the Apple Encrypted Archive: %@", detail)
            }
        }
        var processDetail: String {
            switch self {
            case .expandFailed(let detail), .mountFailed(let detail), .processFailed(let detail),
                 .aeaDecryptFailed(let detail):
                return detail
            case .unreadable, .tooDeep, .tooManyEntries, .aeaKeyRequired:
                return localizedDescription
            }
        }
    }
    private static let zipExtensions: Set<String> = [
        "zip", "ipsw", "ipa", "apk", "aab", "jar", "war", "aar",
        "docx", "xlsx", "pptx", "odt", "ods", "odp", "epub",
        "sketch", "vsix", "nupkg", "whl"
    ]
    static func kind(at url: URL) -> Kind? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue { return .directory }
        let ext = url.pathExtension.lowercased()
        if zipExtensions.contains(ext) { return .zipFamily }
        if ext == "pkg" { return .pkg }
        if ext == "xip" { return .xip }
        if ext == "dmg" { return .dmg }
        if ext == "aea" { return .aea }
        return kindFromMagic(at: url)
    }
    static func isDirectoryLike(at url: URL) -> Bool {
        kind(at: url) != nil
    }
    static func isContainerFile(at url: URL) -> Bool {
        guard let kind = kind(at: url) else { return false }
        return kind != .directory
    }
    static func isExpandableContainerPath(_ relativePath: String) -> Bool {
        let name = (relativePath as NSString).lastPathComponent
        guard !name.isEmpty else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        if zipExtensions.contains(ext) { return true }
        return ext == "pkg" || ext == "xip" || ext == "dmg" || ext == "aea"
    }
    static func nestDepth(of relativePath: String) -> Int {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { isExpandableContainerPath(String($0)) }
            .count
    }
    static func expandTree(
        at url: URL,
        session: DiffsplitterContainerSession,
        progress: (@Sendable (_ completed: Int, _ expected: Int?) -> Void)? = nil
    ) throws -> [String: URL] {
        var map: [String: URL] = [:]
        var expectedTotal: Int?
        try expandNode(
            at: url,
            pathPrefix: "",
            depth: 0,
            session: session,
            into: &map,
            expectedTotal: &expectedTotal,
            progress: progress
        )
        progress?(map.count, expectedTotal ?? map.count)
        return map
    }
    static func expandSingleContainer(
        at url: URL,
        pathPrefix: String,
        session: DiffsplitterContainerSession,
        aeaKey: String? = nil,
        progress: (@Sendable (_ completed: Int, _ expected: Int?) -> Void)? = nil
    ) throws -> [String: URL]? {
        try Task.checkCancellation()
        let depth = nestDepth(of: pathPrefix)
        guard depth <= maxNestDepth else { throw ContainerError.tooDeep }
        let resolved = try resolveForExpansion(
            url: url,
            session: session,
            progress: progress
        )
        guard let kind = kind(at: resolved), kind != .directory else {
            return nil
        }
        var map: [String: URL] = [:]
        var expectedTotal: Int?
        switch kind {
        case .directory:
            return nil
        case .zipFamily:
            try expandZipVirtually(
                archive: resolved,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress
            )
        case .pkg:
            let extracted = try session.makeWorkPath(named: "pkg")
            try runPkgExpand(package: resolved, into: extracted)
            try walkDirectory(
                at: extracted,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress,
                deferNestedContainers: true
            )
        case .xip:
            let extracted = try session.makeWorkDirectory(named: "xip")
            try runXipExpand(archive: resolved, into: extracted)
            try walkDirectory(
                at: extracted,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress,
                deferNestedContainers: true
            )
        case .dmg:
            let mountPoint = try session.makeWorkDirectory(named: "dmg-mnt")
            try session.attachDiskImage(resolved, mountPoint: mountPoint)
            try walkDirectory(
                at: mountPoint,
                pathPrefix: pathPrefix,
                depth: depth + 1,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress,
                deferNestedContainers: true
            )
        case .aea:
            try expandAEA(
                at: resolved,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                aeaKey: aeaKey,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress,
                deferNestedContainers: true
            )
        }
        progress?(map.count, expectedTotal ?? map.count)
        return map
    }
    private static func resolveForExpansion(
        url: URL,
        session: DiffsplitterContainerSession,
        progress: (@Sendable (Int, Int?) -> Void)?
    ) throws -> URL {
        if zipStubMetadata(at: url) != nil {
            return try session.materializeZipMemberForExpansion(
                forStubURL: url,
                progress: progress
            )
        }
        return url
    }
    private static func kindFromMagic(at url: URL) -> Kind? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 8), header.count >= 4 else { return nil }
        if header.starts(with: Array("AEA1".utf8)) {
            return .aea
        }
        if header.starts(with: [0x50, 0x4B, 0x03, 0x04])
            || header.starts(with: [0x50, 0x4B, 0x05, 0x06])
            || header.starts(with: [0x50, 0x4B, 0x07, 0x08]) {
            return .zipFamily
        }
        if header.starts(with: Array("xar!".utf8)) {
            let ext = url.pathExtension.lowercased()
            return ext == "xip" ? .xip : .pkg
        }
        return nil
    }
    private static func expandNode(
        at url: URL,
        pathPrefix: String,
        depth: Int,
        session: DiffsplitterContainerSession,
        into map: inout [String: URL],
        expectedTotal: inout Int?,
        progress: (@Sendable (Int, Int?) -> Void)?
    ) throws {
        try Task.checkCancellation()
        guard depth <= maxNestDepth else { throw ContainerError.tooDeep }
        guard let kind = kind(at: url) else {
            try addLeaf(
                url,
                pathPrefix: pathPrefix,
                name: url.lastPathComponent,
                into: &map,
                expectedTotal: expectedTotal,
                progress: progress
            )
            return
        }
        switch kind {
        case .directory:
            try walkDirectory(
                at: url,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress
            )
        case .zipFamily:
            try expandZipVirtually(
                archive: url,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress
            )
        case .pkg:
            let extracted = try session.makeWorkPath(named: "pkg")
            try runPkgExpand(package: url, into: extracted)
            try walkDirectory(
                at: extracted,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress
            )
        case .xip:
            let extracted = try session.makeWorkDirectory(named: "xip")
            try runXipExpand(archive: url, into: extracted)
            try walkDirectory(
                at: extracted,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress
            )
        case .dmg:
            if depth > 0 {
                try addLeaf(
                    url,
                    pathPrefix: pathPrefix,
                    name: url.lastPathComponent,
                    into: &map,
                    expectedTotal: expectedTotal,
                    progress: progress
                )
                return
            }
            do {
                let mountPoint = try session.makeWorkDirectory(named: "dmg-mnt")
                try session.attachDiskImage(url, mountPoint: mountPoint)
                try walkDirectory(
                    at: mountPoint,
                    pathPrefix: pathPrefix,
                    depth: depth + 1,
                    session: session,
                    into: &map,
                    expectedTotal: &expectedTotal,
                    progress: progress
                )
            } catch {
                try addLeaf(
                    url,
                    pathPrefix: pathPrefix,
                    name: url.lastPathComponent,
                    into: &map,
                    expectedTotal: expectedTotal,
                    progress: progress
                )
            }
        case .aea:
            if depth > 0 {
                try addLeaf(
                    url,
                    pathPrefix: pathPrefix,
                    name: url.lastPathComponent,
                    into: &map,
                    expectedTotal: expectedTotal,
                    progress: progress
                )
                return
            }
            do {
                try expandAEA(
                    at: url,
                    pathPrefix: pathPrefix,
                    depth: depth,
                    session: session,
                    aeaKey: nil,
                    into: &map,
                    expectedTotal: &expectedTotal,
                    progress: progress,
                    deferNestedContainers: false
                )
            } catch {
                try addLeaf(
                    url,
                    pathPrefix: pathPrefix,
                    name: url.lastPathComponent,
                    into: &map,
                    expectedTotal: expectedTotal,
                    progress: progress
                )
            }
        }
    }
    private static func expandAEA(
        at url: URL,
        pathPrefix: String,
        depth: Int,
        session: DiffsplitterContainerSession,
        aeaKey: String?,
        into map: inout [String: URL],
        expectedTotal: inout Int?,
        progress: (@Sendable (Int, Int?) -> Void)?,
        deferNestedContainers: Bool
    ) throws {
        try Task.checkCancellation()
        progress?(map.count, expectedTotal)
        let workDir = try session.makeWorkDirectory(named: "aea")
        let decrypted = DiffsplitterAEA.decryptedOutputURL(for: url, in: workDir)
        try DiffsplitterAEA.decrypt(input: url, output: decrypted, keyValue: aeaKey)
        guard let payloadKind = kind(at: decrypted) else {
            try addLeaf(
                decrypted,
                pathPrefix: pathPrefix,
                name: decrypted.lastPathComponent,
                into: &map,
                expectedTotal: expectedTotal,
                progress: progress
            )
            return
        }
        switch payloadKind {
        case .directory:
            try walkDirectory(
                at: decrypted,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress,
                deferNestedContainers: deferNestedContainers
            )
        case .zipFamily:
            try expandZipVirtually(
                archive: decrypted,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress
            )
        case .pkg:
            let extracted = try session.makeWorkPath(named: "aea-pkg")
            try runPkgExpand(package: decrypted, into: extracted)
            try walkDirectory(
                at: extracted,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress,
                deferNestedContainers: deferNestedContainers
            )
        case .xip:
            let extracted = try session.makeWorkDirectory(named: "aea-xip")
            try runXipExpand(archive: decrypted, into: extracted)
            try walkDirectory(
                at: extracted,
                pathPrefix: pathPrefix,
                depth: depth,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress,
                deferNestedContainers: deferNestedContainers
            )
        case .dmg:
            let mountPoint = try session.makeWorkDirectory(named: "aea-dmg-mnt")
            try session.attachDiskImage(decrypted, mountPoint: mountPoint)
            try walkDirectory(
                at: mountPoint,
                pathPrefix: pathPrefix,
                depth: depth + 1,
                session: session,
                into: &map,
                expectedTotal: &expectedTotal,
                progress: progress,
                deferNestedContainers: true
            )
        case .aea:
            try addLeaf(
                decrypted,
                pathPrefix: pathPrefix,
                name: decrypted.lastPathComponent,
                into: &map,
                expectedTotal: expectedTotal,
                progress: progress
            )
        }
    }
    private static func walkDirectory(
        at root: URL,
        pathPrefix: String,
        depth: Int,
        session: DiffsplitterContainerSession,
        into map: inout [String: URL],
        expectedTotal: inout Int?,
        progress: (@Sendable (Int, Int?) -> Void)?,
        deferNestedContainers: Bool = false
    ) throws {
        let rootPath = root.standardizedFileURL.path
        let enumeratorOptions: FileManager.DirectoryEnumerationOptions =
            DiffsplitterSettings.includeHiddenFiles() ? [] : [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: enumeratorOptions
        ) else {
            throw ContainerError.unreadable
        }
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { continue }
            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            var relative = String(path.dropFirst(rootPath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            guard !relative.isEmpty else { continue }
            let fullRelative = pathPrefix.isEmpty ? relative : "\(pathPrefix)/\(relative)"
            if !deferNestedContainers, isContainerFile(at: fileURL) {
                try expandNode(
                    at: fileURL,
                    pathPrefix: fullRelative,
                    depth: depth + 1,
                    session: session,
                    into: &map,
                    expectedTotal: &expectedTotal,
                    progress: progress
                )
            } else {
                try addLeaf(
                    fileURL,
                    relativePath: fullRelative,
                    into: &map,
                    expectedTotal: expectedTotal,
                    progress: progress
                )
            }
        }
    }
    private static func addLeaf(
        _ url: URL,
        pathPrefix: String,
        name: String,
        into map: inout [String: URL],
        expectedTotal: Int?,
        progress: (@Sendable (Int, Int?) -> Void)?
    ) throws {
        let relative = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
        try addLeaf(url, relativePath: relative, into: &map, expectedTotal: expectedTotal, progress: progress)
    }
    private static func addLeaf(
        _ url: URL,
        relativePath: String,
        into map: inout [String: URL],
        expectedTotal: Int?,
        progress: (@Sendable (Int, Int?) -> Void)?
    ) throws {
        guard map.count < maxEntries else { throw ContainerError.tooManyEntries }
        map[relativePath] = url
        progress?(map.count, expectedTotal)
    }
    private static func expandZipVirtually(
        archive: URL,
        pathPrefix: String,
        depth: Int,
        session: DiffsplitterContainerSession,
        into map: inout [String: URL],
        expectedTotal: inout Int?,
        progress: (@Sendable (Int, Int?) -> Void)?
    ) throws {
        progress?(map.count, -1)
        let entries = try listZipEntries(archive: archive)
        expectedTotal = (expectedTotal ?? map.count) + entries.count
        progress?(map.count, expectedTotal)
        for entry in entries {
            try Task.checkCancellation()
            let fullRelative = pathPrefix.isEmpty ? entry.name : "\(pathPrefix)/\(entry.name)"
            let stub = try session.registerZipMemberStub(
                relativePath: fullRelative,
                archive: archive,
                memberPath: entry.name,
                crc32: entry.crc32,
                uncompressedSize: entry.uncompressedSize
            )
            try addLeaf(
                stub,
                relativePath: fullRelative,
                into: &map,
                expectedTotal: expectedTotal,
                progress: progress
            )
        }
    }
    private struct ZipListEntry {
        let name: String
        let crc32: UInt32
        let uncompressedSize: Int
    }
    private static func listZipEntries(archive: URL) throws -> [ZipListEntry] {
        do {
            return try DiffsplitterZip.listEntries(archive: archive, maxEntries: maxEntries).map {
                ZipListEntry(name: $0.name, crc32: $0.crc32, uncompressedSize: $0.uncompressedSize)
            }
        } catch let error as DiffsplitterZip.ZipError {
            switch error {
            case .tooLarge:
                throw ContainerError.tooManyEntries
            default:
                throw ContainerError.expandFailed(error.localizedDescription)
            }
        }
    }
    static func zipStubMetadata(at url: URL) -> DiffsplitterZipMember? {
        let metaURL = DiffsplitterContainerSession.sidecarURL(forStub: url)
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(DiffsplitterContainerSession.StubSidecar.self, from: data) else {
            return nil
        }
        return DiffsplitterZipMember(
            archiveURL: URL(fileURLWithPath: meta.archivePath),
            memberPath: meta.memberPath,
            crc32: meta.crc32,
            uncompressedSize: meta.uncompressedSize
        )
    }
    static func resolvedFileURL(
        for url: URL,
        session: DiffsplitterContainerSession?,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws -> URL {
        if zipStubMetadata(at: url) == nil {
            return url
        }
        if let session {
            return try session.materializeZipMember(forStubURL: url, progress: progress)
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Diffsplitter-materialize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        guard let member = zipStubMetadata(at: url) else { return url }
        let outURL = temp.appendingPathComponent((member.memberPath as NSString).lastPathComponent)
        try extractZipMember(
            archive: member.archiveURL,
            memberPath: member.memberPath,
            to: outURL,
            expectedBytes: member.uncompressedSize,
            progress: progress
        )
        return outURL
    }
    static func extractZipMember(
        archive: URL,
        memberPath: String,
        to destination: URL,
        expectedBytes: Int? = nil,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws {
        do {
            try DiffsplitterZip.extractMember(
                archive: archive,
                memberPath: memberPath,
                to: destination,
                expectedBytes: expectedBytes,
                progress: progress
            )
        } catch let error as DiffsplitterZip.ZipError {
            throw ContainerError.processFailed(error.localizedDescription)
        }
    }
    static func extractZipMemberToMemory(
        archive: URL,
        memberPath: String,
        expectedBytes: Int? = nil,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws -> Data {
        do {
            return try DiffsplitterZip.extractMemberToMemory(
                archive: archive,
                memberPath: memberPath,
                expectedBytes: expectedBytes,
                progress: progress
            )
        } catch let error as DiffsplitterZip.ZipError {
            throw ContainerError.processFailed(error.localizedDescription)
        }
    }
    static func resolveBinaryDumpSource(
        for url: URL,
        session: DiffsplitterContainerSession?,
        preferDiskTemp: Bool,
        progress: DiffsplitterContent.MaterializeProgress? = nil
    ) throws -> DiffsplitterBinaryDump.ByteSource {
        guard zipStubMetadata(at: url) != nil else {
            return .file(url)
        }
        if preferDiskTemp {
            let resolved = try resolvedFileURL(for: url, session: session, progress: progress)
            return .file(resolved)
        }
        if let session {
            let data = try session.materializeZipMemberToMemory(forStubURL: url, progress: progress)
            return .memory(DiffsplitterBinaryDump.MemoryBuffer(data))
        }
        guard let member = zipStubMetadata(at: url) else {
            return .file(url)
        }
        let data = try extractZipMemberToMemory(
            archive: member.archiveURL,
            memberPath: member.memberPath,
            expectedBytes: member.uncompressedSize,
            progress: progress
        )
        return .memory(DiffsplitterBinaryDump.MemoryBuffer(data))
    }
    static func attachDiskImage(_ image: URL, mountPoint: URL) throws {
        try DiffsplitterContainerServices.backend.attachDiskImage(image, mountPoint: mountPoint)
    }
    static func detachDiskImage(at mountPoint: URL) {
        DiffsplitterContainerServices.backend.detachDiskImage(at: mountPoint)
    }
    private static func runPkgExpand(package: URL, into destination: URL) throws {
        try DiffsplitterContainerServices.backend.expandPkg(package: package, into: destination)
    }
    private static func runXipExpand(archive: URL, into destination: URL) throws {
        try DiffsplitterContainerServices.backend.expandXip(archive: archive, into: destination)
    }
    @discardableResult
    static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> String {
        try DiffsplitterContainerServices.backend.runProcess(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory
        )
    }
    static func runProcessData(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> Data {
        try DiffsplitterContainerServices.backend.runProcessData(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory
        )
    }
}

nonisolated enum DiffsplitterEngine {
    static var maxTextBytes: Int { DiffsplitterSettings.maxTextBytes() }
    static let maxConcurrentFileStatus = 8
    static let maxAlignLines = 200_000
    static let maxEditDistance = 4_096
    static let fingerprintChunkBytes = 64 * 1024

    enum SideKind: Equatable {
        case file
        case directory
    }

    enum ReadError: LocalizedError {
        case binaryFile
        case unreadable
        case notFileOrDirectory
        case mismatchedKinds
        var errorDescription: String? {
            switch self {
            case .binaryFile:
                return L10n.t("This file looks binary and cannot be shown as text.")
            case .unreadable:
                return L10n.t("The selected item could not be read.")
            case .notFileOrDirectory:
                return L10n.t("Choose a regular file, folder, or archive.")
            case .mismatchedKinds:
                return L10n.t("Both sides must be files, or both sides must be folders or archives.")
            }
        }
    }

    struct TextContent: Equatable {
        let lines: [String]
        let encodingName: String
    }

    enum RowKind: String, Codable, Equatable {
        case equal
        case insert
        case delete
        case replace
    }

    struct AlignedRow: Identifiable, Equatable, Hashable {
        let id: Int
        let leftLineNumber: Int?
        let rightLineNumber: Int?
        let leftText: String?
        let rightText: String?
        let kind: RowKind
    }

    enum DirEntryStatus: String, Equatable, Hashable {
        case added
        case removed
        case modified
        case identical
        case binary
    }

    static let defaultStatusPriority: [DirEntryStatus] = [
        .added, .modified, .removed, .binary
    ]

    static func statusPriority(
        fromRawValues rawValues: [String]
    ) -> [DirEntryStatus] {
        let parsed = rawValues.compactMap(DirEntryStatus.init(rawValue:))
            .filter { $0 != .identical }
        var seen = Set<DirEntryStatus>()
        var result: [DirEntryStatus] = []
        for status in parsed where seen.insert(status).inserted {
            result.append(status)
        }
        for status in defaultStatusPriority where seen.insert(status).inserted {
            result.append(status)
        }
        return result
    }

    struct DirEntry: Identifiable, Equatable, Hashable {
        var id: String { relativePath }
        let relativePath: String
        let status: DirEntryStatus
    }
    static func sideKind(at url: URL) throws -> SideKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ReadError.unreadable
        }
        if isDirectory.boolValue { return .directory }
        if DiffsplitterContainer.isContainerFile(at: url) { return .directory }
        var isRegular = false
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) {
            isRegular = values.isRegularFile == true
        }
        guard isRegular else { throw ReadError.notFileOrDirectory }
        return .file
    }
    static func resolveComparisonKind(left: URL, right: URL) throws -> DiffsplitterDocument.ComparisonKind {
        let leftKind = try sideKind(at: left)
        let rightKind = try sideKind(at: right)
        guard leftKind == rightKind else { throw ReadError.mismatchedKinds }
        return leftKind == .directory ? .directories : .files
    }
    static func buildSideFileMap(
        at url: URL,
        session: DiffsplitterContainerSession,
        progress: (@Sendable (_ completed: Int, _ expected: Int?) -> Void)? = nil
    ) throws -> [String: URL] {
        try DiffsplitterContainer.expandTree(at: url, session: session, progress: progress)
    }
    static func compareDirectoryMaps(
        left: [String: URL],
        right: [String: URL],
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) throws -> [DirEntry] {
        let allPaths = Set(left.keys).union(right.keys).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let total = allPaths.count
        guard total > 0 else {
            progress?(0, 0)
            return []
        }
        var results = [DirEntry?](repeating: nil, count: total)
        let resultsLock = NSLock()
        var firstError: Error?
        let errorLock = NSLock()
        var completedCount = 0
        let progressLock = NSLock()
        let gate = DispatchSemaphore(value: maxConcurrentFileStatus)
        DispatchQueue.concurrentPerform(iterations: total) { index in
            if Task.isCancelled { return }
            errorLock.lock()
            let alreadyFailed = firstError != nil
            errorLock.unlock()
            if alreadyFailed { return }
            gate.wait()
            defer { gate.signal() }
            if Task.isCancelled { return }
            errorLock.lock()
            let failedAfterWait = firstError != nil
            errorLock.unlock()
            if failedAfterWait { return }
            let path = allPaths[index]
            let leftURL = left[path]
            let rightURL = right[path]
            let entry: DirEntry
            do {
                switch (leftURL, rightURL) {
                case (nil, .some):
                    entry = DirEntry(relativePath: path, status: .added)
                case (.some, nil):
                    entry = DirEntry(relativePath: path, status: .removed)
                case let (.some(leftFile), .some(rightFile)):
                    entry = DirEntry(
                        relativePath: path,
                        status: try fileStatus(left: leftFile, right: rightFile)
                    )
                case (nil, nil):
                    entry = DirEntry(relativePath: path, status: .identical)
                }
            } catch {
                errorLock.lock()
                if firstError == nil { firstError = error }
                errorLock.unlock()
                return
            }
            resultsLock.lock()
            results[index] = entry
            resultsLock.unlock()
            progressLock.lock()
            completedCount += 1
            let completed = completedCount
            progressLock.unlock()
            progress?(completed, total)
        }
        try Task.checkCancellation()
        errorLock.lock()
        let error = firstError
        errorLock.unlock()
        if let error { throw error }
        guard results.allSatisfy({ $0 != nil }) else {
            throw CancellationError()
        }
        return results.compactMap { $0 }
    }
    static func readText(from url: URL, session: DiffsplitterContainerSession? = nil) throws -> TextContent {
        try DiffsplitterContent.decode(url: url, session: session)
    }
    typealias MemberLoadProgress = @Sendable (_ fractionCompleted: Double, _ status: String) -> Void
    static func alignDirectoryEntry(
        status: DirEntryStatus,
        leftURL: URL?,
        rightURL: URL?,
        leftSession: DiffsplitterContainerSession?,
        rightSession: DiffsplitterContainerSession?,
        ignoreWhitespace: Bool,
        progress: MemberLoadProgress? = nil
    ) throws -> [AlignedRow] {
        if status == .binary {
            progress?(0.2, L10n.t("Loading…"))
            let leftLines = DiffsplitterContent.binaryMetadataLines(
                url: leftURL,
                byteCount: fileByteCount(leftURL)
            )
            let rightLines = DiffsplitterContent.binaryMetadataLines(
                url: rightURL,
                byteCount: fileByteCount(rightURL)
            )
            progress?(0.5, L10n.t("Aligning…"))
            let rows = try alignLines(
                left: leftLines,
                right: rightLines,
                ignoreWhitespace: false
            ) { local in
                progress?(0.5 + 0.5 * local, L10n.t("Aligning…"))
            }
            progress?(1, L10n.t("Aligning…"))
            return rows
        }
        let leftLines: [String]
        let rightLines: [String]
        switch status {
        case .identical:
            return []
        case .added:
            leftLines = []
            rightLines = try decodeSide(
                url: rightURL,
                session: rightSession,
                statusLabel: L10n.t("Loading right…"),
                range: 0.0...0.35,
                progress: progress
            )
        case .removed:
            leftLines = try decodeSide(
                url: leftURL,
                session: leftSession,
                statusLabel: L10n.t("Loading left…"),
                range: 0.0...0.35,
                progress: progress
            )
            rightLines = []
        case .modified:
            leftLines = try decodeSide(
                url: leftURL,
                session: leftSession,
                statusLabel: L10n.t("Loading left…"),
                range: 0.0...0.17,
                progress: progress
            )
            rightLines = try decodeSide(
                url: rightURL,
                session: rightSession,
                statusLabel: L10n.t("Loading right…"),
                range: 0.17...0.35,
                progress: progress
            )
        case .binary:
            return []
        }
        let alignRange: ClosedRange<Double> = 0.35...1.0
        let alignStatus = L10n.t("Aligning…")
        progress?(alignRange.lowerBound, alignStatus)
        let rows = try alignLines(
            left: leftLines,
            right: rightLines,
            ignoreWhitespace: ignoreWhitespace
        ) { local in
            guard let progress else { return }
            let overall = alignRange.lowerBound + (alignRange.upperBound - alignRange.lowerBound) * local
            progress(overall, alignStatus)
        }
        progress?(alignRange.upperBound, alignStatus)
        return rows
    }
    private static func decodeSide(
        url: URL?,
        session: DiffsplitterContainerSession?,
        statusLabel: String,
        range: ClosedRange<Double>,
        progress: MemberLoadProgress?
    ) throws -> [String] {
        progress?(range.lowerBound, statusLabel)
        let content = try DiffsplitterContent.decode(url: url, session: session) { completed, expected in
            guard let progress else { return }
            let local: Double
            if let expected, expected > 0 {
                local = min(1, Double(completed) / Double(expected))
            } else if completed > 0 {
                local = min(0.95, Double(completed) / Double(completed + 1_048_576))
            } else {
                local = 0
            }
            let overall = range.lowerBound + (range.upperBound - range.lowerBound) * local
            progress(overall, statusLabel)
        }
        progress?(range.upperBound, statusLabel)
        return content.lines
    }
    private static func fileByteCount(_ url: URL?) -> Int? {
        guard let url else { return nil }
        if let zip = DiffsplitterContainer.zipStubMetadata(at: url) {
            return zip.uncompressedSize
        }
        return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
    static func alignLines(
        left: [String],
        right: [String],
        ignoreWhitespace: Bool,
        progress: (@Sendable (_ fractionCompleted: Double) -> Void)? = nil
    ) throws -> [AlignedRow] {
        progress?(0)
        if left.count + right.count > maxAlignLines {
            progress?(0.5)
            let rows = indexPairedRows(
                left: left,
                right: right,
                ignoreWhitespace: ignoreWhitespace
            ) { local in
                progress?(0.5 + 0.5 * local)
            }
            progress?(1)
            return rows
        }
        let leftKeys = try mapKeys(left, ignoreWhitespace: ignoreWhitespace, phaseProgress: { local in
            progress?(0.05 * local)
        })
        let rightKeys = try mapKeys(right, ignoreWhitespace: ignoreWhitespace, phaseProgress: { local in
            progress?(0.05 * (0.5 + 0.5 * local))
        })
        progress?(0.05)
        let editResult = try myersEditOffsets(
            left: leftKeys,
            right: rightKeys
        ) { d, maxD in
            let denom = max(1, maxD)
            let local = min(1, Double(d) / Double(denom))
            progress?(0.05 + 0.80 * local)
        }
        switch editResult {
        case .tooDifferent:
            progress?(0.85)
            let rows = indexPairedRows(
                left: left,
                right: right,
                ignoreWhitespace: ignoreWhitespace
            ) { local in
                progress?(0.85 + 0.15 * local)
            }
            progress?(1)
            return rows
        case let .edits(removals, insertions):
            progress?(0.85)
            let rows = buildAlignedRows(
                left: left,
                right: right,
                removals: removals,
                insertions: insertions
            ) { local in
                progress?(0.85 + 0.15 * local)
            }
            progress?(1)
            return rows
        }
    }
    static func unifiedDiff(
        leftName: String,
        rightName: String,
        rows: [AlignedRow]
    ) -> String {
        var lines: [String] = [
            "--- \(leftName)",
            "+++ \(rightName)"
        ]
        var hunkLeftStart = 0
        var hunkRightStart = 0
        var hunkLines: [String] = []
        var leftCount = 0
        var rightCount = 0
        var collecting = false
        var previousEqual: AlignedRow?
        func flushHunk() {
            guard collecting, !hunkLines.isEmpty else { return }
            lines.append("@@ -\(hunkLeftStart),\(leftCount) +\(hunkRightStart),\(rightCount) @@")
            lines.append(contentsOf: hunkLines)
            hunkLines.removeAll(keepingCapacity: true)
            leftCount = 0
            rightCount = 0
            collecting = false
        }
        for row in rows {
            switch row.kind {
            case .equal:
                if collecting {
                    hunkLines.append(" \(row.leftText ?? row.rightText ?? "")")
                    leftCount += 1
                    rightCount += 1
                    if hunkLines.count > 6 {
                        flushHunk()
                    }
                }
                previousEqual = row
            case .delete:
                if !collecting {
                    collecting = true
                    hunkLeftStart = row.leftLineNumber ?? 1
                    hunkRightStart = max((row.rightLineNumber ?? 1) - 0, 1)
                    if let previous = previousEqual {
                        hunkLeftStart = previous.leftLineNumber ?? hunkLeftStart
                        hunkRightStart = previous.rightLineNumber ?? hunkRightStart
                        hunkLines.append(" \(previous.leftText ?? "")")
                        leftCount = 1
                        rightCount = 1
                    }
                }
                hunkLines.append("-\(row.leftText ?? "")")
                leftCount += 1
            case .insert:
                if !collecting {
                    collecting = true
                    hunkLeftStart = max((row.leftLineNumber ?? 1), 1)
                    hunkRightStart = row.rightLineNumber ?? 1
                    if let previous = previousEqual {
                        hunkLeftStart = previous.leftLineNumber ?? hunkLeftStart
                        hunkRightStart = previous.rightLineNumber ?? hunkRightStart
                        hunkLines.append(" \(previous.leftText ?? "")")
                        leftCount = 1
                        rightCount = 1
                    }
                }
                hunkLines.append("+\(row.rightText ?? "")")
                rightCount += 1
            case .replace:
                if !collecting {
                    collecting = true
                    hunkLeftStart = row.leftLineNumber ?? 1
                    hunkRightStart = row.rightLineNumber ?? 1
                }
                hunkLines.append("-\(row.leftText ?? "")")
                hunkLines.append("+\(row.rightText ?? "")")
                leftCount += 1
                rightCount += 1
            }
        }
        flushHunk()
        return lines.joined(separator: "\n") + "\n"
    }

    private enum MyersResult {
        case edits(removals: Set<Int>, insertions: Set<Int>)
        case tooDifferent
    }
    private static func indexPairedRows(
        left: [String],
        right: [String],
        ignoreWhitespace: Bool,
        progress: (@Sendable (Double) -> Void)?
    ) -> [AlignedRow] {
        let count = max(left.count, right.count)
        var rows: [AlignedRow] = []
        rows.reserveCapacity(count)
        let reportEvery = max(1, count / 64)
        for index in 0..<count {
            if index % reportEvery == 0 {
                progress?(Double(index) / Double(max(1, count)))
            }
            let leftText = index < left.count ? left[index] : nil
            let rightText = index < right.count ? right[index] : nil
            let kind: RowKind
            switch (leftText, rightText) {
            case (nil, nil):
                continue
            case (nil, _):
                kind = .insert
            case (_, nil):
                kind = .delete
            case let (l?, r?) where linesEqual(l, r, ignoreWhitespace: ignoreWhitespace):
                kind = .equal
            default:
                kind = .replace
            }
            rows.append(AlignedRow(
                id: rows.count,
                leftLineNumber: leftText == nil ? nil : index + 1,
                rightLineNumber: rightText == nil ? nil : index + 1,
                leftText: leftText,
                rightText: rightText,
                kind: kind
            ))
        }
        progress?(1)
        return rows
    }
    private static func buildAlignedRows(
        left: [String],
        right: [String],
        removals: Set<Int>,
        insertions: Set<Int>,
        progress: (@Sendable (Double) -> Void)?
    ) -> [AlignedRow] {
        var rows: [AlignedRow] = []
        rows.reserveCapacity(max(left.count, right.count))
        var leftIndex = 0
        var rightIndex = 0
        var rowID = 0
        var leftLine = 1
        var rightLine = 1
        let estimatedRows = max(1, left.count + right.count)
        var lastReportRow = 0
        while leftIndex < left.count || rightIndex < right.count {
            if rowID - lastReportRow >= 256 {
                progress?(min(1, Double(rowID) / Double(estimatedRows)))
                lastReportRow = rowID
            }
            let removing = leftIndex < left.count && removals.contains(leftIndex)
            let inserting = rightIndex < right.count && insertions.contains(rightIndex)
            if removing && inserting {
                rows.append(AlignedRow(
                    id: rowID,
                    leftLineNumber: leftLine,
                    rightLineNumber: rightLine,
                    leftText: left[leftIndex],
                    rightText: right[rightIndex],
                    kind: .replace
                ))
                rowID += 1
                leftIndex += 1
                rightIndex += 1
                leftLine += 1
                rightLine += 1
            } else if removing {
                rows.append(AlignedRow(
                    id: rowID,
                    leftLineNumber: leftLine,
                    rightLineNumber: nil,
                    leftText: left[leftIndex],
                    rightText: nil,
                    kind: .delete
                ))
                rowID += 1
                leftIndex += 1
                leftLine += 1
            } else if inserting {
                rows.append(AlignedRow(
                    id: rowID,
                    leftLineNumber: nil,
                    rightLineNumber: rightLine,
                    leftText: nil,
                    rightText: right[rightIndex],
                    kind: .insert
                ))
                rowID += 1
                rightIndex += 1
                rightLine += 1
            } else if leftIndex < left.count && rightIndex < right.count {
                rows.append(AlignedRow(
                    id: rowID,
                    leftLineNumber: leftLine,
                    rightLineNumber: rightLine,
                    leftText: left[leftIndex],
                    rightText: right[rightIndex],
                    kind: .equal
                ))
                rowID += 1
                leftIndex += 1
                rightIndex += 1
                leftLine += 1
                rightLine += 1
            } else if leftIndex < left.count {
                rows.append(AlignedRow(
                    id: rowID,
                    leftLineNumber: leftLine,
                    rightLineNumber: nil,
                    leftText: left[leftIndex],
                    rightText: nil,
                    kind: .delete
                ))
                rowID += 1
                leftIndex += 1
                leftLine += 1
            } else if rightIndex < right.count {
                rows.append(AlignedRow(
                    id: rowID,
                    leftLineNumber: nil,
                    rightLineNumber: rightLine,
                    leftText: nil,
                    rightText: right[rightIndex],
                    kind: .insert
                ))
                rowID += 1
                rightIndex += 1
                rightLine += 1
            } else {
                break
            }
        }
        progress?(1)
        return rows
    }
    private static func mapKeys(
        _ lines: [String],
        ignoreWhitespace: Bool,
        phaseProgress: (@Sendable (Double) -> Void)?
    ) throws -> [String] {
        guard !lines.isEmpty else {
            phaseProgress?(1)
            return []
        }
        if !ignoreWhitespace {
            phaseProgress?(1)
            return lines
        }
        var keys = [String]()
        keys.reserveCapacity(lines.count)
        let reportEvery = max(1, lines.count / 32)
        for (index, line) in lines.enumerated() {
            if index % reportEvery == 0 {
                try Task.checkCancellation()
                phaseProgress?(Double(index) / Double(lines.count))
            }
            keys.append(normalizeWhitespace(line))
        }
        phaseProgress?(1)
        return keys
    }
    private static func myersEditOffsets(
        left: [String],
        right: [String],
        onDepth: (@Sendable (_ d: Int, _ maxD: Int) -> Void)?
    ) throws -> MyersResult {
        let n = left.count
        let m = right.count
        if n == 0 && m == 0 { return .edits(removals: [], insertions: []) }
        let maxD = min(n + m, maxEditDistance)
        var trace: [[Int]] = []
        trace.reserveCapacity(maxD + 1)
        var foundD: Int?
        outer: for d in 0...maxD {
            try Task.checkCancellation()
            onDepth?(d, maxD)
            var v = Array(repeating: 0, count: 2 * d + 1)
            for k in stride(from: -d, through: d, by: 2) {
                let x: Int
                if d == 0 {
                    x = 0
                } else {
                    let prev = trace[d - 1]
                    let down = k == -d || (k != d && prev[(k - 1) + (d - 1)] < prev[(k + 1) + (d - 1)])
                    if down {
                        x = prev[(k + 1) + (d - 1)]
                    } else {
                        x = prev[(k - 1) + (d - 1)] + 1
                    }
                }
                var xx = x
                var y = xx - k
                while xx < n, y < m, left[xx] == right[y] {
                    xx += 1
                    y += 1
                }
                v[k + d] = xx
                if xx >= n, y >= m {
                    trace.append(v)
                    foundD = d
                    break outer
                }
            }
            trace.append(v)
        }
        guard let finalD = foundD else {
            return .tooDifferent
        }
        var removals = Set<Int>()
        var insertions = Set<Int>()
        var x = n
        var y = m
        for d in stride(from: finalD, through: 0, by: -1) {
            let k = x - y
            let prevX: Int
            let prevY: Int
            if d == 0 {
                prevX = 0
                prevY = 0
            } else {
                let prev = trace[d - 1]
                let down = k == -d || (k != d && prev[(k - 1) + (d - 1)] < prev[(k + 1) + (d - 1)])
                let prevK = down ? k + 1 : k - 1
                prevX = prev[prevK + (d - 1)]
                prevY = prevX - prevK
            }
            while x > prevX, y > prevY {
                x -= 1
                y -= 1
            }
            if d > 0 {
                if x == prevX {
                    insertions.insert(prevY)
                } else {
                    removals.insert(prevX)
                }
            }
            x = prevX
            y = prevY
        }
        return .edits(removals: removals, insertions: insertions)
    }
    private static func linesEqual(
        _ left: String,
        _ right: String,
        ignoreWhitespace: Bool
    ) -> Bool {
        if left == right { return true }
        guard ignoreWhitespace else { return false }
        return normalizeWhitespace(left) == normalizeWhitespace(right)
    }
    private static func normalizeWhitespace(_ line: String) -> String {
        line
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
    private static func looksBinarySample(_ data: Data) -> Bool {
        if data.contains(0) { return true }
        let sample = data.prefix(8_192)
        guard !sample.isEmpty else { return false }
        let nonPrintable = sample.reduce(into: 0) { count, byte in
            if byte < 9 || (byte > 13 && byte < 32) { count += 1 }
        }
        return Double(nonPrintable) / Double(sample.count) > 0.30
    }
    private static func fileStatus(left: URL, right: URL) throws -> DirEntryStatus {
        if let leftZip = DiffsplitterContainer.zipStubMetadata(at: left),
           let rightZip = DiffsplitterContainer.zipStubMetadata(at: right) {
            if leftZip.crc32 == rightZip.crc32 && leftZip.uncompressedSize == rightZip.uncompressedSize {
                return .identical
            }
            if DiffsplitterImage4.isImage4Extension(of: left)
                || DiffsplitterImage4.isImage4Extension(of: right)
                || DiffsplitterImage4.isImage4Extension(of: URL(fileURLWithPath: leftZip.memberPath))
                || DiffsplitterImage4.isImage4Extension(of: URL(fileURLWithPath: rightZip.memberPath))
                || DiffsplitterAEA.isAEAExtension(of: left)
                || DiffsplitterAEA.isAEAExtension(of: right)
                || DiffsplitterAEA.isAEAExtension(of: URL(fileURLWithPath: leftZip.memberPath))
                || DiffsplitterAEA.isAEAExtension(of: URL(fileURLWithPath: rightZip.memberPath)) {
                return .modified
            }
            if leftZip.uncompressedSize > maxTextBytes || rightZip.uncompressedSize > maxTextBytes {
                return .binary
            }
            return .modified
        }
        return try fileStatusBytes(left: left, right: right)
    }
    private static func fileStatusBytes(left: URL, right: URL) throws -> DirEntryStatus {
        if DiffsplitterAEA.isAEAExtension(of: left) || DiffsplitterAEA.isAEAExtension(of: right)
            || DiffsplitterAEA.looksLikeFile(at: left) || DiffsplitterAEA.looksLikeFile(at: right) {
            let leftLines = (try? DiffsplitterAEA.summarize(at: left)) ?? []
            let rightLines = (try? DiffsplitterAEA.summarize(at: right)) ?? []
            if !leftLines.isEmpty || !rightLines.isEmpty {
                return leftLines == rightLines ? .identical : .modified
            }
            return .modified
        }
        if DiffsplitterImage4.isImage4Extension(of: left) || DiffsplitterImage4.isImage4Extension(of: right) {
            let leftData = try Data(contentsOf: left, options: [.mappedIfSafe])
            let rightData = try Data(contentsOf: right, options: [.mappedIfSafe])
            let leftLines = (try? DiffsplitterImage4.summarize(leftData)) ?? []
            let rightLines = (try? DiffsplitterImage4.summarize(rightData)) ?? []
            if !leftLines.isEmpty || !rightLines.isEmpty {
                return leftLines == rightLines ? .identical : .modified
            }
            return .modified
        }
        let leftSize = try fileSize(at: left)
        let rightSize = try fileSize(at: right)
        if leftSize != rightSize {
            if leftSize > maxTextBytes || rightSize > maxTextBytes {
                return .binary
            }
            return .modified
        }
        if leftSize == 0 { return .identical }
        if leftSize > maxTextBytes {
            let leftFP = try fingerprint(at: left, size: leftSize)
            let rightFP = try fingerprint(at: right, size: rightSize)
            return leftFP == rightFP ? .identical : .binary
        }
        let leftFP = try fingerprint(at: left, size: leftSize)
        let rightFP = try fingerprint(at: right, size: rightSize)
        if leftFP == rightFP { return .identical }
        let head = try readChunk(at: left, offset: 0, maxLength: min(8_192, leftSize))
        if looksBinarySample(head) { return .binary }
        return .modified
    }
    private static func fileSize(at url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw ReadError.unreadable
        }
        return size
    }
    private static func fingerprint(at url: URL, size: Int) throws -> Data {
        if size <= fingerprintChunkBytes * 3 {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return Data(SHA256.hash(data: data))
        }
        var hasher = SHA256()
        let chunk = fingerprintChunkBytes
        let head = try readChunk(at: url, offset: 0, maxLength: chunk)
        hasher.update(data: head)
        let midOffset = max(0, (size / 2) - (chunk / 2))
        let mid = try readChunk(at: url, offset: midOffset, maxLength: chunk)
        hasher.update(data: mid)
        let tailOffset = max(0, size - chunk)
        let tail = try readChunk(at: url, offset: tailOffset, maxLength: chunk)
        hasher.update(data: tail)
        var sizeBE = UInt64(size).bigEndian
        withUnsafeBytes(of: &sizeBE) { hasher.update(bufferPointer: $0) }
        return Data(hasher.finalize())
    }
    private static func readChunk(at url: URL, offset: Int, maxLength: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: maxLength) ?? Data()
        return data
    }
}

nonisolated struct DiffsplitterIndexProgress: Sendable, Equatable {
    var fractionCompleted: Double
    var status: String
}

nonisolated final class DiffsplitterIndexProgressReporter: @unchecked Sendable {
    enum Side: Sendable {
        case left
        case right
    }
    private let leftWeight = 0.10
    private let rightWeight = 0.10
    private let compareWeight = 0.80
    private let lock = NSLock()
    private var leftFraction = 0.0
    private var rightFraction = 0.0
    private var compareFraction = 0.0
    private var status = L10n.t("Comparing…")
    private var lastPublish: CFAbsoluteTime = 0
    private let minInterval: CFAbsoluteTime = 1.0 / 12.0
    private let onUpdate: @Sendable (DiffsplitterIndexProgress) -> Void
    init(onUpdate: @escaping @Sendable (DiffsplitterIndexProgress) -> Void) {
        self.onUpdate = onUpdate
    }
    func reportListing(side: Side) {
        let label: String
        switch side {
        case .left:
            label = L10n.t("Listing left archive…")
        case .right:
            label = L10n.t("Listing right archive…")
        }
        lock.lock()
        switch side {
        case .left: leftFraction = max(leftFraction, 0.02)
        case .right: rightFraction = max(rightFraction, 0.02)
        }
        status = label
        let snapshot = currentProgressLocked()
        lastPublish = 0
        lock.unlock()
        onUpdate(snapshot)
    }
    func reportExpand(side: Side, completed: Int, expected: Int?) {
        if expected == -1 {
            reportListing(side: side)
            return
        }
        let fraction: Double
        if let expected, expected > 0 {
            fraction = min(0.92, Double(completed) / Double(expected))
        } else if completed <= 0 {
            fraction = 0.02
        } else {
            fraction = min(0.92, Double(completed) / Double(completed + 80))
        }
        let label: String
        switch side {
        case .left:
            label = L10n.t("Indexing left…")
        case .right:
            label = L10n.t("Indexing right…")
        }
        lock.lock()
        switch side {
        case .left: leftFraction = max(leftFraction, fraction)
        case .right: rightFraction = max(rightFraction, fraction)
        }
        status = label
        let snapshot = currentProgressLocked()
        let shouldPublish = shouldPublishLocked()
        lock.unlock()
        if shouldPublish {
            onUpdate(snapshot)
        }
    }
    func finishExpand(side: Side) {
        lock.lock()
        switch side {
        case .left: leftFraction = 1
        case .right: rightFraction = 1
        }
        status = L10n.t("Comparing files…")
        let snapshot = currentProgressLocked()
        lastPublish = 0
        lock.unlock()
        onUpdate(snapshot)
    }
    func reportCompare(completed: Int, total: Int) {
        let fraction: Double
        if total > 0 {
            fraction = min(1, Double(completed) / Double(total))
        } else {
            fraction = 1
        }
        lock.lock()
        compareFraction = fraction
        status = L10n.t("Comparing files…")
        let snapshot = currentProgressLocked()
        let shouldPublish = shouldPublishLocked() || completed >= total
        lock.unlock()
        if shouldPublish {
            onUpdate(snapshot)
        }
    }
    func finish() {
        lock.lock()
        leftFraction = 1
        rightFraction = 1
        compareFraction = 1
        status = L10n.t("Comparing…")
        let snapshot = currentProgressLocked()
        lock.unlock()
        onUpdate(snapshot)
    }
    private func currentProgressLocked() -> DiffsplitterIndexProgress {
        let overall =
            leftFraction * leftWeight
            + rightFraction * rightWeight
            + compareFraction * compareWeight
        return DiffsplitterIndexProgress(
            fractionCompleted: min(1, max(0, overall)),
            status: status
        )
    }
    private func shouldPublishLocked() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastPublish >= minInterval {
            lastPublish = now
            return true
        }
        return false
    }
}

nonisolated final class DiffsplitterProgressPublisher: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPublish: CFAbsoluteTime = 0
    private var lastStatus: String?
    private let minInterval: CFAbsoluteTime = 1.0 / 12.0
    private let onUpdate: @Sendable (DiffsplitterIndexProgress) -> Void
    init(onUpdate: @escaping @Sendable (DiffsplitterIndexProgress) -> Void) {
        self.onUpdate = onUpdate
    }
    func publish(fractionCompleted: Double, status: String, force: Bool = false) {
        let snapshot = DiffsplitterIndexProgress(
            fractionCompleted: min(1, max(0, fractionCompleted)),
            status: status
        )
        lock.lock()
        let statusChanged = lastStatus != status
        lastStatus = status
        let shouldPublish: Bool
        if force || statusChanged {
            lastPublish = CFAbsoluteTimeGetCurrent()
            shouldPublish = true
        } else {
            shouldPublish = shouldPublishLocked()
        }
        lock.unlock()
        if shouldPublish {
            onUpdate(snapshot)
        }
    }
    private func shouldPublishLocked() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastPublish >= minInterval {
            lastPublish = now
            return true
        }
        return false
    }
}

extension UTType {
    static let diffsplitterDocument = UTType(exportedAs: "theoderoy.Deboogey.Diffsplitter", conformingTo: .json)
    static let diffsplitterXDocument = UTType(exportedAs: "theoderoy.Deboogey.DiffsplitterX", conformingTo: .json)
}

nonisolated struct DiffsplitterDocument: Codable {
    static let currentFormatVersion = 0

    enum ComparisonKind: String, Codable, Hashable {
        case files
        case directories
    }
    let formatVersion: Int
    let leftPath: String?
    let rightPath: String?
    let leftBookmark: Data?
    let rightBookmark: Data?
    let comparisonKind: ComparisonKind?
    let ignoreWhitespace: Bool
    let selectedRelativePath: String?
    init(
        leftPath: String?,
        rightPath: String?,
        leftBookmark: Data? = nil,
        rightBookmark: Data? = nil,
        comparisonKind: ComparisonKind?,
        ignoreWhitespace: Bool = false,
        selectedRelativePath: String? = nil
    ) {
        formatVersion = Self.currentFormatVersion
        self.leftPath = leftPath
        self.rightPath = rightPath
        self.leftBookmark = leftBookmark
        self.rightBookmark = rightBookmark
        self.comparisonKind = comparisonKind
        self.ignoreWhitespace = ignoreWhitespace
        self.selectedRelativePath = selectedRelativePath
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    static func read(from url: URL) throws -> DiffsplitterDocument {
        let document = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard document.formatVersion == currentFormatVersion else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSDebugDescriptionErrorKey: "Unsupported Diffsplitter document version."
            ])
        }
        return document
    }
}

nonisolated struct DiffsplitterXDocument: Codable {
    static let currentFormatVersion = 0

    struct Row: Codable {
        let leftLineNumber: Int?
        let rightLineNumber: Int?
        let leftText: String?
        let rightText: String?
        let kind: DiffsplitterEngine.RowKind
    }
    let formatVersion: Int
    let leftName: String?
    let rightName: String?
    let selectedRelativePath: String?
    let ignoreWhitespace: Bool
    let comparisonKind: DiffsplitterDocument.ComparisonKind?
    let isHexDump: Bool?
    let rows: [Row]
    init(
        leftName: String?,
        rightName: String?,
        selectedRelativePath: String? = nil,
        ignoreWhitespace: Bool = false,
        comparisonKind: DiffsplitterDocument.ComparisonKind? = nil,
        isHexDump: Bool = false,
        rows: [DiffsplitterEngine.AlignedRow]
    ) {
        formatVersion = Self.currentFormatVersion
        self.leftName = leftName
        self.rightName = rightName
        self.selectedRelativePath = selectedRelativePath
        self.ignoreWhitespace = ignoreWhitespace
        self.comparisonKind = comparisonKind
        self.isHexDump = isHexDump
        self.rows = rows.map { row in
            Row(
                leftLineNumber: row.leftLineNumber,
                rightLineNumber: row.rightLineNumber,
                leftText: row.leftText,
                rightText: row.rightText,
                kind: row.kind
            )
        }
    }
    var presentsAsHexDump: Bool {
        if isHexDump == true { return true }
        return DiffsplitterBinaryDump.looksLikeHexDump(alignedRows())
    }
    func alignedRows() -> [DiffsplitterEngine.AlignedRow] {
        rows.enumerated().map { index, row in
            DiffsplitterEngine.AlignedRow(
                id: index,
                leftLineNumber: row.leftLineNumber,
                rightLineNumber: row.rightLineNumber,
                leftText: row.leftText,
                rightText: row.rightText,
                kind: row.kind
            )
        }
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    static func read(from url: URL) throws -> DiffsplitterXDocument {
        let document = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard document.formatVersion == currentFormatVersion else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSDebugDescriptionErrorKey: "Unsupported DiffsplitterX document version."
            ])
        }
        return document
    }
}

nonisolated struct DiffsplitterWindowRequest: Codable, Hashable {
    enum Action: String, Codable, Hashable {
        case create
        case open
    }
    let id: UUID
    let action: Action
    let documentURL: URL?
    init(action: Action, documentURL: URL? = nil) {
        id = UUID()
        self.action = action
        self.documentURL = documentURL
    }
}

@MainActor

enum DiffsplitterNavigation {
    static let windowID = "deboogey-diffsplitter"
    static func openLegacy(documentAt url: URL?) {
        DiffsplitterWindowController.open(DiffsplitterWindowRequest(
            action: url == nil ? .create : .open,
            documentURL: url
        ))
    }
    static func chooseDocumentLegacy() {
        chooseDocument { url in openLegacy(documentAt: url) }
    }
    @available(macOS 13.0, *)
    static func open(documentAt url: URL?, using openWindow: OpenWindowAction) {
        let request = DiffsplitterWindowRequest(
            action: url == nil ? .create : .open,
            documentURL: url
        )
        openWindow(id: windowID, value: request)
    }
    @available(macOS 13.0, *)
    static func chooseDocument(using openWindow: OpenWindowAction) {
        chooseDocument { url in open(documentAt: url, using: openWindow) }
    }
    private static func chooseDocument(open: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = L10n.t("Open Diffsplitter Document")
        panel.allowedContentTypes = [.diffsplitterDocument, .diffsplitterXDocument]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            open(url)
        }
    }
}

enum DiffsplitterFileAccess {
    static func chooseSideItem(
        title: String,
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK else {
                completion(nil)
                return
            }
            completion(panel.url)
        }
    }
    static func exportText(
        title: String,
        suggestedName: String,
        contentTypes: [UTType],
        text: String,
        onError: @escaping (String) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = contentTypes
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.data(using: .utf8)?.write(to: url, options: .atomic)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
    static func saveDocument(
        title: String,
        suggestedName: String,
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = title
        panel.allowedContentTypes = [.diffsplitterDocument]
        panel.nameFieldStringValue = suggestedName
        panel.begin { response in
            guard response == .OK, var url = panel.url else {
                completion(nil)
                return
            }
            if url.pathExtension.lowercased() != "dsplt" {
                url = url.appendingPathExtension("dsplt")
            }
            completion(url)
        }
    }
    static func exportDocument(
        title: String,
        suggestedName: String,
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = title
        panel.allowedContentTypes = [.diffsplitterXDocument]
        panel.nameFieldStringValue = suggestedName
        panel.begin { response in
            guard response == .OK, var url = panel.url else {
                completion(nil)
                return
            }
            if url.pathExtension.lowercased() != "dspltx" {
                url = url.appendingPathExtension("dspltx")
            }
            completion(url)
        }
    }

    enum SaveOrExportChoice {
        case save
        case export
        case cancel
    }
    static func presentSaveOrExportChooser(
        allowExport: Bool,
        completion: @escaping (SaveOrExportChoice) -> Void
    ) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L10n.t("Save or Export Diffsplitter Document?")
            alert.informativeText = L10n.t(
                "Save a Diffsplitter document to reopen the same paths later, or export a DiffsplitterX document that stores the full file differences."
            )
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.t("Save Diffsplitter Document"))
            if allowExport {
                alert.addButton(withTitle: L10n.t("Export DiffsplitterX Document…"))
            }
            alert.addButton(withTitle: L10n.t("Cancel"))
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                switch response {
                case .alertFirstButtonReturn:
                    completion(.save)
                case .alertSecondButtonReturn:
                    completion(allowExport ? .export : .cancel)
                default:
                    completion(.cancel)
                }
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window, completionHandler: finish)
            } else {
                finish(alert.runModal())
            }
        }
    }
    static func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    static func presentMessageAlert(
        title: String,
        message: String,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.t("OK"))
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window) { _ in
                    completion()
                }
            } else {
                alert.runModal()
                completion()
            }
        }
    }

    enum AEAKeyPromptResult {
        case decrypt(String)
        case metadataOnly
    }
    static func presentAEAKeyPrompt(
        initialValue: String,
        completion: @escaping (AEAKeyPromptResult) -> Void
    ) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L10n.t("AEA Decryption Key")
            alert.informativeText = L10n.t(
                "Enter the base64 or hex key for this Apple Encrypted Archive. Leave blank to compare metadata only."
            )
            alert.alertStyle = .informational
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
            field.stringValue = initialValue
            field.placeholderString = L10n.t("base64:… or hex:…")
            field.isEditable = true
            field.isSelectable = true
            alert.accessoryView = field
            alert.addButton(withTitle: L10n.t("Decrypt"))
            alert.addButton(withTitle: L10n.t("Compare Metadata"))
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                if response == .alertFirstButtonReturn {
                    completion(.decrypt(field.stringValue))
                } else {
                    completion(.metadataOnly)
                }
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window, completionHandler: finish)
                DispatchQueue.main.async {
                    field.window?.makeFirstResponder(field)
                }
            } else {
                finish(alert.runModal())
            }
        }
    }

    enum BinaryDumpPromptResult {
        case inspectDump
        case metadataOnly
        case cancel
    }
    static func presentBinaryDumpPrompt(
        estimate: DiffsplitterBinaryDump.CostEstimate,
        completion: @escaping (BinaryDumpPromptResult) -> Void
    ) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L10n.t("Inspect Binary Dump?")
            alert.informativeText = estimate.promptDetail
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.t("Inspect Dump"))
            alert.addButton(withTitle: L10n.t("Metadata Only"))
            alert.addButton(withTitle: L10n.t("Cancel"))
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                switch response {
                case .alertFirstButtonReturn:
                    completion(.inspectDump)
                case .alertSecondButtonReturn:
                    completion(.metadataOnly)
                default:
                    completion(.cancel)
                }
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window, completionHandler: finish)
            } else {
                finish(alert.runModal())
            }
        }
    }
}

@MainActor

final class DiffsplitterWindowController: NSWindowController {
    private static var openWindows: [UUID: DiffsplitterWindowController] = [:]
    private let requestID: UUID
    private var closeObserver: NSObjectProtocol?
    private init(request: DiffsplitterWindowRequest) {
        requestID = request.id
        let root = DiffsplitterView(request: request)
            .environment(\.locale, L10n.locale)
        let sizing = AppWindowSizing.diffsplitter
        let window: NSWindow
        if #available(macOS 14.0, *) {
            let hostingView = NSHostingView(rootView: root)
            hostingView.sceneBridgingOptions = [.toolbars]
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: sizing.defaultSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
        } else {
            window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(sizing.defaultSize)
        }
        window.title = L10n.t("Diffsplitter")
        window.minSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: sizing.minimumSize)
        ).size
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowDidClose()
            }
        }
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    static func open(_ request: DiffsplitterWindowRequest) {
        let controller = DiffsplitterWindowController(request: request)
        openWindows[request.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func windowDidClose() {
        Self.openWindows.removeValue(forKey: requestID)
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
    }
}

@MainActor

final class DiffsplitterSession: ObservableObject {
    enum Side {
        case left
        case right
    }

    struct AEAKeyPromptState: Identifiable {
        let id = UUID()
        let path: String
        let fallbackEntry: DiffsplitterEngine.DirEntry
    }
    @Published var leftURL: URL?
    @Published var rightURL: URL?
    @Published var leftAccessing = false
    @Published var rightAccessing = false
    @Published var leftSession: DiffsplitterContainerSession?
    @Published var rightSession: DiffsplitterContainerSession?
    @Published var leftFileMap: [String: URL] = [:]
    @Published var rightFileMap: [String: URL] = [:]
    @Published var expandedContainerPaths: Set<String> = []
    @Published var skippedExpandPaths: Set<String> = []
    @Published var comparisonKind: DiffsplitterDocument.ComparisonKind?
    @Published var rows: [DiffsplitterEngine.AlignedRow] = []
    @Published var visibleRowCount = 0
    @Published var directoryEntries: [DiffsplitterEngine.DirEntry] = []
    @Published var selectedRelativePath: String?
    @Published var directoryBrowsePrefix = ""
    @Published var directoryFilter = ""
    @Published var directoryStatusFilters: Set<DiffsplitterEngine.DirEntryStatus> = []
    @Published var ignoreWhitespace = false
    @Published var isComparing = false
    @Published var indexProgress: DiffsplitterIndexProgress?
    @Published var memberLoadProgress: DiffsplitterIndexProgress?
    @Published var documentTransferProgress: DiffsplitterIndexProgress?
    @Published var setupError: String?
    @Published var documentURL: URL?
    @Published var savedDocumentData: Data?
    @Published var documentError: String?
    @Published var isEmbeddedDocument = false
    @Published var embeddedLeftName: String?
    @Published var embeddedRightName: String?
    @Published var leftDropTargeted = false
    @Published var rightDropTargeted = false
    @Published var aeaSessionKeys: [String: String] = [:]
    @Published var aeaKeyPrompt: AEAKeyPromptState?
    @Published var aeaKeyDraft = ""
    @Published var isPresentingAppKitAlert = false
    @Published var binaryDump: DiffsplitterBinaryDump.Session?
    @Published var binaryDumpOffsetField = "0"
    private var compareTask: Task<Void, Never>?
    private var documentTransferTask: Task<Void, Never>?
    var reduceMotion = false
    var hasBothSides: Bool { leftURL != nil && rightURL != nil }
    var isReady: Bool { isEmbeddedDocument || (hasBothSides && comparisonKind != nil) }
    var canExportDiffsplitterX: Bool {
        if documentTransferProgress != nil { return false }
        if !rows.isEmpty { return true }
        guard let dump = binaryDump else { return false }
        return dump.totalLines > 0
    }
    var isBinaryDumpActive: Bool { binaryDump != nil }
    var isTransferringDocument: Bool { documentTransferProgress != nil }
    func cancelAndClose() {
        compareTask?.cancel()
        documentTransferTask?.cancel()
        documentTransferProgress = nil
        closeContainerSessions()
        stopAccess(for: .left)
        stopAccess(for: .right)
    }
    func handleDocumentRequest(_ request: DiffsplitterWindowRequest) {
        switch request.action {
        case .create:
            break
        case .open:
            guard let url = request.documentURL else { return }
            openDocument(at: url)
        }
    }
    func presentOpenPanel(for side: Side) {
        let title = side == .left ? L10n.t("Choose Left Item") : L10n.t("Choose Right Item")
        DiffsplitterFileAccess.chooseSideItem(title: title) { [weak self] url in
            guard let self, let url else { return }
            self.assign(url, to: side)
        }
    }
    func handleDrop(_ providers: [NSItemProvider], onto side: Side) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let value = item as? URL {
                url = value
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                self?.assign(url, to: side)
            }
        }
        return true
    }
    func assign(_ url: URL, to side: Side) {
        if isEmbeddedDocument {
            exitEmbeddedDocumentMode(clearRows: true)
        }
        let accessed = url.startAccessingSecurityScopedResource()
        switch side {
        case .left:
            stopAccess(for: .left)
            leftURL = url
            leftAccessing = accessed
        case .right:
            stopAccess(for: .right)
            rightURL = url
            rightAccessing = accessed
        }
        setupError = nil
        recompare()
    }
    func stopAccess(for side: Side) {
        switch side {
        case .left:
            if leftAccessing, let leftURL {
                leftURL.stopAccessingSecurityScopedResource()
            }
            leftAccessing = false
        case .right:
            if rightAccessing, let rightURL {
                rightURL.stopAccessingSecurityScopedResource()
            }
            rightAccessing = false
        }
    }
    func swapSides() {
        if isEmbeddedDocument {
            swapEmbeddedSides()
            return
        }
        let previousLeft = leftURL
        let previousRight = rightURL
        let previousLeftAccess = leftAccessing
        let previousRightAccess = rightAccessing
        leftURL = previousRight
        rightURL = previousLeft
        leftAccessing = previousRightAccess
        rightAccessing = previousLeftAccess
        recompare()
    }
    private func swapEmbeddedSides() {
        let previousLeftName = embeddedLeftName
        embeddedLeftName = embeddedRightName
        embeddedRightName = previousLeftName
        if let dump = binaryDump {
            let swappedRows = dump.rows.enumerated().map { index, row -> DiffsplitterBinaryDump.HexRow in
                let kind: DiffsplitterBinaryDump.HexRow.Kind
                switch row.kind {
                case .insert: kind = .delete
                case .delete: kind = .insert
                case .equal, .replace: kind = row.kind
                }
                return DiffsplitterBinaryDump.HexRow(
                    id: index,
                    offset: row.offset,
                    leftText: row.rightText,
                    rightText: row.leftText,
                    kind: kind
                )
            }
            binaryDump = DiffsplitterBinaryDump.Session(
                leftSource: dump.rightSource,
                rightSource: dump.leftSource,
                leftByteCount: dump.rightByteCount,
                rightByteCount: dump.leftByteCount,
                windowStartLine: dump.windowStartLine,
                windowLineCount: dump.windowLineCount,
                rows: swappedRows
            )
            return
        }
        applyRows(rows.enumerated().map { index, row in
            let kind: DiffsplitterEngine.RowKind
            switch row.kind {
            case .insert: kind = .delete
            case .delete: kind = .insert
            case .equal, .replace: kind = row.kind
            }
            return DiffsplitterEngine.AlignedRow(
                id: index,
                leftLineNumber: row.rightLineNumber,
                rightLineNumber: row.leftLineNumber,
                leftText: row.rightText,
                rightText: row.leftText,
                kind: kind
            )
        })
    }
    private func exitEmbeddedDocumentMode(clearRows: Bool) {
        isEmbeddedDocument = false
        embeddedLeftName = nil
        embeddedRightName = nil
        if clearRows {
            binaryDump = nil
            binaryDumpOffsetField = "0"
            applyRows([])
            comparisonKind = nil
            selectedRelativePath = nil
        }
    }
    func clearSession(keepingDocument: Bool) {
        compareTask?.cancel()
        unloadInspectMaterializations()
        closeContainerSessions()
        stopAccess(for: .left)
        stopAccess(for: .right)
        leftURL = nil
        rightURL = nil
        comparisonKind = nil
        rows = []
        visibleRowCount = 0
        directoryEntries = []
        selectedRelativePath = nil
        directoryBrowsePrefix = ""
        directoryFilter = ""
        directoryStatusFilters = []
        expandedContainerPaths = []
        skippedExpandPaths = []
        aeaSessionKeys = [:]
        aeaKeyPrompt = nil
        aeaKeyDraft = ""
        setupError = nil
        isComparing = false
        indexProgress = nil
        memberLoadProgress = nil
        binaryDump = nil
        binaryDumpOffsetField = "0"
        isEmbeddedDocument = false
        embeddedLeftName = nil
        embeddedRightName = nil
        if !keepingDocument {
            documentURL = nil
            savedDocumentData = nil
        }
    }
    func closeContainerSessions() {
        leftSession?.close()
        rightSession?.close()
        leftSession = nil
        rightSession = nil
        leftFileMap = [:]
        rightFileMap = [:]
        expandedContainerPaths = []
        skippedExpandPaths = []
        aeaSessionKeys = [:]
        aeaKeyPrompt = nil
        aeaKeyDraft = ""
    }
    func unloadInspectMaterializations() {
        leftSession?.unloadInspectMaterializations()
        rightSession?.unloadInspectMaterializations()
    }
    func openDirectoryMember(_ path: String) {
        selectedRelativePath = path
    }
    func enterDirectoryBrowsePrefix(_ prefix: String) {
        selectedRelativePath = nil
        clearBinaryDump()
        applyRows([])
        directoryBrowsePrefix = prefix
    }
    func leaveDirectoryBrowseLevel(toRoot: Bool = false) {
        selectedRelativePath = nil
        clearBinaryDump()
        applyRows([])
        guard !directoryBrowsePrefix.isEmpty else { return }
        if toRoot {
            directoryBrowsePrefix = ""
            return
        }
        let parent = (directoryBrowsePrefix as NSString).deletingLastPathComponent
        directoryBrowsePrefix = parent == "/" ? "" : parent
    }
    func leaveDirectoryDetail() {
        compareTask?.cancel()
        clearBinaryDump()
        unloadInspectMaterializations()
        selectedRelativePath = nil
        memberLoadProgress = nil
        isComparing = false
        applyRows([])
    }

    struct DirectoryBrowserItem: Identifiable, Hashable {
        enum Kind: Hashable {
            case folder
            case file
        }
        let id: String
        let displayName: String
        let fullPath: String
        let kind: Kind
        let status: DiffsplitterEngine.DirEntryStatus
        let childCount: Int
    }
    func directoryBrowserItems(
        statusFilters: Set<DiffsplitterEngine.DirEntryStatus> = [],
        query: String = "",
        statusPriority: [DiffsplitterEngine.DirEntryStatus] = DiffsplitterEngine.defaultStatusPriority
    ) -> [DirectoryBrowserItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = directoryEntries.filter { $0.status != .identical }
        if !statusFilters.isEmpty {
            changed = changed.filter { statusFilters.contains($0.status) }
        }
        if !trimmedQuery.isEmpty {
            changed = changed.filter {
                $0.relativePath.localizedCaseInsensitiveContains(trimmedQuery)
            }
            return changed.compactMap { entry -> DirectoryBrowserItem? in
                if !directoryBrowsePrefix.isEmpty {
                    let prefix = directoryBrowsePrefix + "/"
                    guard entry.relativePath.hasPrefix(prefix) else { return nil }
                } else if expandedContainerPaths.contains(where: {
                    entry.relativePath.hasPrefix($0 + "/")
                }) {
                }
                return DirectoryBrowserItem(
                    id: "file:" + entry.relativePath,
                    displayName: entry.relativePath,
                    fullPath: entry.relativePath,
                    kind: .file,
                    status: entry.status,
                    childCount: 0
                )
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }

        struct FolderAccum {
            var status: DiffsplitterEngine.DirEntryStatus = .identical
            var count = 0
        }
        var folders: [String: FolderAccum] = [:]
        var files: [DiffsplitterEngine.DirEntry] = []
        let prefix = directoryBrowsePrefix
        let prefixSlash = prefix.isEmpty ? "" : prefix + "/"
        for entry in changed {
            let path = entry.relativePath
            if prefix.isEmpty {
                if expandedContainerPaths.contains(where: { path.hasPrefix($0 + "/") }) {
                    continue
                }
            } else {
                guard path.hasPrefix(prefixSlash) else { continue }
            }
            let remainder = prefix.isEmpty ? path : String(path.dropFirst(prefixSlash.count))
            guard !remainder.isEmpty else { continue }
            if let slashIdx = remainder.firstIndex(of: "/") {
                let name = String(remainder[..<slashIdx])
                let folderPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
                var accum = folders[folderPath] ?? FolderAccum()
                accum.count += 1
                accum.status = Self.rollupStatus(accum.status, entry.status, priority: statusPriority)
                folders[folderPath] = accum
            } else {
                files.append(entry)
            }
        }
        if prefix.isEmpty {
            for expanded in expandedContainerPaths {
                if folders[expanded] == nil {
                    let descendants = changed.filter { $0.relativePath.hasPrefix(expanded + "/") }
                    guard !descendants.isEmpty else { continue }
                    var accum = FolderAccum()
                    for entry in descendants {
                        accum.count += 1
                        accum.status = Self.rollupStatus(accum.status, entry.status, priority: statusPriority)
                    }
                    folders[expanded] = accum
                }
            }
        }
        var items: [DirectoryBrowserItem] = folders.map { path, accum in
            DirectoryBrowserItem(
                id: "folder:" + path,
                displayName: (path as NSString).lastPathComponent,
                fullPath: path,
                kind: .folder,
                status: accum.status == .identical ? .modified : accum.status,
                childCount: accum.count
            )
        }
        items.append(contentsOf: files.map { entry in
            DirectoryBrowserItem(
                id: "file:" + entry.relativePath,
                displayName: (entry.relativePath as NSString).lastPathComponent,
                fullPath: entry.relativePath,
                kind: .file,
                status: entry.status,
                childCount: 0
            )
        })
        items.sort { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .folder
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        return items
    }
    private static func rollupStatus(
        _ current: DiffsplitterEngine.DirEntryStatus,
        _ next: DiffsplitterEngine.DirEntryStatus,
        priority: [DiffsplitterEngine.DirEntryStatus]
    ) -> DiffsplitterEngine.DirEntryStatus {
        let rank: (DiffsplitterEngine.DirEntryStatus) -> Int = { status in
            guard status != .identical else { return 0 }
            guard let index = priority.firstIndex(of: status) else { return 0 }
            return priority.count - index
        }
        return rank(next) > rank(current) ? next : current
    }
    func activateDirectoryBrowserItem(_ item: DirectoryBrowserItem) {
        switch item.kind {
        case .folder:
            enterDirectoryBrowsePrefix(item.fullPath)
        case .file:
            if expandedContainerPaths.contains(item.fullPath) {
                enterDirectoryBrowsePrefix(item.fullPath)
                return
            }
            guard directoryEntries.contains(where: { $0.relativePath == item.fullPath }) else {
                return
            }
            openDirectoryMember(item.fullPath)
        }
    }
    func clearBinaryDump() {
        binaryDump = nil
        binaryDumpOffsetField = "0"
    }
    func applyIgnoreWhitespaceChange() {
        if isEmbeddedDocument {
            realignEmbeddedRowsForIgnoreWhitespace()
            return
        }
        guard hasBothSides else { return }
        if isBinaryDumpActive { return }
        if comparisonKind == .directories {
            if selectedRelativePath != nil {
                loadSelectedDirectoryFile()
            }
            return
        }
        recompare()
    }
    private func realignEmbeddedRowsForIgnoreWhitespace() {
        guard !isBinaryDumpActive else { return }
        let leftLines = rows.compactMap(\.leftText)
        let rightLines = rows.compactMap(\.rightText)
        guard !leftLines.isEmpty || !rightLines.isEmpty else { return }
        let ignoreWhitespace = self.ignoreWhitespace
        compareTask?.cancel()
        isComparing = true
        memberLoadProgress = DiffsplitterIndexProgress(
            fractionCompleted: 0,
            status: L10n.t("Aligning…")
        )
        compareTask = Task.detached(priority: .userInitiated) {
            let result = Result {
                try DiffsplitterEngine.alignLines(
                    left: leftLines,
                    right: rightLines,
                    ignoreWhitespace: ignoreWhitespace
                )
            }
            await MainActor.run { [self] in
                guard !Task.isCancelled else { return }
                self.isComparing = false
                self.memberLoadProgress = nil
                switch result {
                case .success(let aligned):
                    self.applyRows(aligned)
                case .failure(let error):
                    if error is CancellationError { return }
                    self.setupError = error.localizedDescription
                }
            }
        }
    }
    func recompare() {
        guard !isEmbeddedDocument else { return }
        guard let leftURL, let rightURL else {
            comparisonKind = nil
            rows = []
            visibleRowCount = 0
            return
        }
        compareTask?.cancel()
        isComparing = true
        indexProgress = DiffsplitterIndexProgress(fractionCompleted: 0, status: L10n.t("Comparing…"))
        memberLoadProgress = nil
        clearBinaryDump()
        let restoreDirectoryPath = selectedRelativePath
        let restoreBrowsePrefix = directoryBrowsePrefix
        selectedRelativePath = nil
        directoryBrowsePrefix = ""
        setupError = nil
        let ignoreWhitespace = self.ignoreWhitespace
        let leftName = leftURL.lastPathComponent
        let rightName = rightURL.lastPathComponent
        let compareStartedAt = Date()
        compareTask = Task.detached(priority: .userInitiated) {
            var builtLeftSession: DiffsplitterContainerSession?
            var builtRightSession: DiffsplitterContainerSession?
            let reporter = DiffsplitterIndexProgressReporter { progress in
                Task { @MainActor [self] in
                    self.indexProgress = progress
                }
            }
            let result: Result<ComparePayload, Error>
            do {
                let kind = try DiffsplitterEngine.resolveComparisonKind(left: leftURL, right: rightURL)
                switch kind {
                case .files:
                    let progressPublish = DiffsplitterProgressPublisher { progress in
                        Task { @MainActor [self] in
                            self.indexProgress = progress
                        }
                    }
                    progressPublish.publish(
                        fractionCompleted: 0,
                        status: L10n.t("Loading…"),
                        force: true
                    )
                    let leftPrefersHex = try DiffsplitterContent.prefersHexDump(url: leftURL, session: nil)
                    progressPublish.publish(
                        fractionCompleted: 0.06,
                        status: L10n.t("Loading…"),
                        force: true
                    )
                    let rightPrefersHex = try DiffsplitterContent.prefersHexDump(url: rightURL, session: nil)
                    if leftPrefersHex || rightPrefersHex {
                        progressPublish.publish(
                            fractionCompleted: 0.2,
                            status: L10n.t("Loading window…"),
                            force: true
                        )
                        let leftCount = (try? leftURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        let rightCount = (try? rightURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        let dump = try DiffsplitterBinaryDump.loadWindow(
                            leftURL: leftURL,
                            rightURL: rightURL,
                            leftByteCount: leftCount,
                            rightByteCount: rightCount,
                            startLine: 0
                        )
                        result = .success(ComparePayload(
                            kind: kind,
                            rows: [],
                            entries: [],
                            selectedPath: nil,
                            leftSession: nil,
                            rightSession: nil,
                            leftMap: [:],
                            rightMap: [:],
                            binaryDump: dump
                        ))
                    } else {
                        let leftText = try DiffsplitterEngine.readText(from: leftURL)
                        progressPublish.publish(
                            fractionCompleted: 0.08,
                            status: L10n.t("Loading…"),
                            force: true
                        )
                        let rightText = try DiffsplitterEngine.readText(from: rightURL)
                        progressPublish.publish(
                            fractionCompleted: 0.15,
                            status: L10n.t("Aligning…"),
                            force: true
                        )
                        let aligned = try DiffsplitterEngine.alignLines(
                            left: leftText.lines,
                            right: rightText.lines,
                            ignoreWhitespace: ignoreWhitespace
                        ) { fraction in
                            progressPublish.publish(
                                fractionCompleted: 0.15 + 0.85 * fraction,
                                status: L10n.t("Aligning…"),
                                force: fraction >= 1
                            )
                        }
                        result = .success(ComparePayload(
                            kind: kind,
                            rows: aligned,
                            entries: [],
                            selectedPath: nil,
                            leftSession: nil,
                            rightSession: nil,
                            leftMap: [:],
                            rightMap: [:],
                            binaryDump: nil
                        ))
                    }
                case .directories:
                    let leftSession = try DiffsplitterContainerSession()
                    let rightSession = try DiffsplitterContainerSession()
                    builtLeftSession = leftSession
                    builtRightSession = rightSession
                    let maps = try await withThrowingTaskGroup(
                        of: (DiffsplitterIndexProgressReporter.Side, [String: URL]).self
                    ) { group -> ([String: URL], [String: URL]) in
                        group.addTask {
                            let map = try DiffsplitterEngine.buildSideFileMap(
                                at: leftURL,
                                session: leftSession
                            ) { completed, expected in
                                reporter.reportExpand(side: .left, completed: completed, expected: expected)
                            }
                            return (.left, map)
                        }
                        group.addTask {
                            let map = try DiffsplitterEngine.buildSideFileMap(
                                at: rightURL,
                                session: rightSession
                            ) { completed, expected in
                                reporter.reportExpand(side: .right, completed: completed, expected: expected)
                            }
                            return (.right, map)
                        }
                        var leftMap: [String: URL]?
                        var rightMap: [String: URL]?
                        for try await (side, map) in group {
                            switch side {
                            case .left:
                                leftMap = map
                                reporter.finishExpand(side: .left)
                            case .right:
                                rightMap = map
                                reporter.finishExpand(side: .right)
                            }
                        }
                        guard let leftMap, let rightMap else {
                            throw DiffsplitterEngine.ReadError.unreadable
                        }
                        return (leftMap, rightMap)
                    }
                    let leftMap = maps.0
                    let rightMap = maps.1
                    let entries = try DiffsplitterEngine.compareDirectoryMaps(
                        left: leftMap,
                        right: rightMap
                    ) { completed, total in
                        reporter.reportCompare(completed: completed, total: total)
                    }
                    reporter.finish()
                    result = .success(ComparePayload(
                        kind: kind,
                        rows: [],
                        entries: entries,
                        selectedPath: nil,
                        leftSession: leftSession,
                        rightSession: rightSession,
                        leftMap: leftMap,
                        rightMap: rightMap,
                        binaryDump: nil
                    ))
                }
            } catch {
                result = .failure(error)
            }
            if case .failure = result {
                builtLeftSession?.close()
                builtRightSession?.close()
            }
            let leftoverLeftSession = builtLeftSession
            let leftoverRightSession = builtRightSession
            await MainActor.run { [self] in
                if Task.isCancelled {
                    leftoverLeftSession?.close()
                    leftoverRightSession?.close()
                    self.isComparing = false
                    self.indexProgress = nil
                    return
                }
                self.isComparing = false
                self.indexProgress = nil
                switch result {
                case .success(let payload):
                    self.closeContainerSessions()
                    self.comparisonKind = payload.kind
                    self.directoryEntries = payload.entries
                    self.leftSession = payload.leftSession
                    self.rightSession = payload.rightSession
                    self.leftFileMap = payload.leftMap
                    self.rightFileMap = payload.rightMap
                    self.expandedContainerPaths = []
                    self.skippedExpandPaths = []
                    self.memberLoadProgress = nil
                    self.expandedContainerPaths = []
                    self.skippedExpandPaths = []
                    self.memberLoadProgress = nil
                    if payload.kind == .directories {
                        if let path = restoreDirectoryPath,
                           payload.entries.contains(where: {
                               $0.relativePath == path && $0.status != .identical
                           }) {
                            self.selectedRelativePath = path
                        } else {
                            self.selectedRelativePath = payload.selectedPath
                        }
                        if !restoreBrowsePrefix.isEmpty,
                           payload.entries.contains(where: {
                               $0.relativePath == restoreBrowsePrefix
                                   || $0.relativePath.hasPrefix(restoreBrowsePrefix + "/")
                           }) {
                            self.directoryBrowsePrefix = restoreBrowsePrefix
                        } else {
                            self.directoryBrowsePrefix = ""
                        }
                    } else {
                        self.selectedRelativePath = payload.selectedPath
                        self.directoryBrowsePrefix = ""
                    }
                    if let dump = payload.binaryDump {
                        self.binaryDump = dump
                        self.binaryDumpOffsetField = String(
                            format: "%08x",
                            dump.windowStartLine * DiffsplitterBinaryDump.bytesPerLine
                        )
                        self.rows = []
                        self.visibleRowCount = 0
                    } else {
                        self.applyRows(payload.rows)
                    }
                    DiffsplitterCompletionFeedback.notifyIfNeeded(
                        elapsed: Date().timeIntervalSince(compareStartedAt),
                        label: "\(leftName) ↔ \(rightName)"
                    )
                    EntityTracker.shared.record(
                        source: .diffsplitter,
                        arguments: [
                            TrackedEntity.DiffsplitterActivity.comparisonFinished.rawValue,
                            "\(leftName) ↔ \(rightName)"
                        ]
                    )
                case .failure(let error):
                    if error is CancellationError { return }
                    self.closeContainerSessions()
                    self.comparisonKind = nil
                    self.rows = []
                    self.visibleRowCount = 0
                    self.directoryEntries = []
                    self.selectedRelativePath = nil
                    self.expandedContainerPaths = []
                    self.skippedExpandPaths = []
                    self.memberLoadProgress = nil
                    self.setupError = error.localizedDescription
                }
            }
        }
    }

    private struct ComparePayload: Sendable {
        let kind: DiffsplitterDocument.ComparisonKind
        let rows: [DiffsplitterEngine.AlignedRow]
        let entries: [DiffsplitterEngine.DirEntry]
        let selectedPath: String?
        let leftSession: DiffsplitterContainerSession?
        let rightSession: DiffsplitterContainerSession?
        let leftMap: [String: URL]
        let rightMap: [String: URL]
        let binaryDump: DiffsplitterBinaryDump.Session?
    }
    func loadSelectedDirectoryFile() {
        guard comparisonKind == .directories,
              let path = selectedRelativePath,
              let entry = directoryEntries.first(where: { $0.relativePath == path }),
              entry.status != .identical
        else {
            applyRows([])
            return
        }
        compareTask?.cancel()
        unloadInspectMaterializations()
        clearBinaryDump()
        applyRows([])
        let canExpand = !expandedContainerPaths.contains(path)
            && !skippedExpandPaths.contains(path)
            && DiffsplitterContainer.isExpandableContainerPath(path)
            && (leftFileMap[path] != nil || rightFileMap[path] != nil)
        if canExpand {
            expandSelectedNestedContainer(path: path, fallbackEntry: entry)
            return
        }
        beginDirectoryMemberCompare(path: path, entry: entry)
    }

    private struct NestedExpandPayload: Sendable {
        let leftMap: [String: URL]
        let rightMap: [String: URL]
        let entries: [DiffsplitterEngine.DirEntry]
        let didExpand: Bool
    }
    func expandSelectedNestedContainer(
        path: String,
        fallbackEntry: DiffsplitterEngine.DirEntry
    ) {
        isComparing = true
        indexProgress = nil
        let expandingAEA = DiffsplitterContainer.isExpandableContainerPath(path)
            && (path as NSString).pathExtension.lowercased() == "aea"
        memberLoadProgress = DiffsplitterIndexProgress(
            fractionCompleted: 0,
            status: expandingAEA
                ? L10n.t("Expanding AEA…")
                : L10n.t("Expanding archive…")
        )
        let leftSession = self.leftSession
        let rightSession = self.rightSession
        let leftURL = leftFileMap[path]
        let rightURL = rightFileMap[path]
        let leftMapSnapshot = leftFileMap
        let rightMapSnapshot = rightFileMap
        let existingEntries = directoryEntries
        let aeaKey = aeaSessionKeys[path]
        let compareLabel = (path as NSString).lastPathComponent
        let compareStartedAt = Date()
        compareTask = Task.detached(priority: .userInitiated) {
            let progressPublish = DiffsplitterProgressPublisher { progress in
                Task { @MainActor [self] in
                    self.memberLoadProgress = progress
                }
            }
            let result = Result {
                var leftChildren: [String: URL]?
                var rightChildren: [String: URL]?
                if let leftURL, let leftSession {
                    leftChildren = try DiffsplitterContainer.expandSingleContainer(
                        at: leftURL,
                        pathPrefix: path,
                        session: leftSession,
                        aeaKey: aeaKey
                    ) { completed, expected in
                        let local: Double
                        if let expected, expected > 0 {
                            local = min(0.45, Double(completed) / Double(max(expected, 1)) * 0.45)
                        } else if completed > 0 {
                            local = 0.1
                        } else {
                            local = 0.02
                        }
                        progressPublish.publish(
                            fractionCompleted: local,
                            status: L10n.t("Expanding left…"),
                            force: completed == 0
                        )
                    }
                }
                if let rightURL, let rightSession {
                    rightChildren = try DiffsplitterContainer.expandSingleContainer(
                        at: rightURL,
                        pathPrefix: path,
                        session: rightSession,
                        aeaKey: aeaKey
                    ) { completed, expected in
                        let local: Double
                        if let expected, expected > 0 {
                            local = 0.45 + min(0.45, Double(completed) / Double(max(expected, 1)) * 0.45)
                        } else if completed > 0 {
                            local = 0.55
                        } else {
                            local = 0.48
                        }
                        progressPublish.publish(
                            fractionCompleted: local,
                            status: L10n.t("Expanding right…"),
                            force: completed == 0
                        )
                    }
                }
                guard leftChildren != nil || rightChildren != nil else {
                    return NestedExpandPayload(
                        leftMap: leftMapSnapshot,
                        rightMap: rightMapSnapshot,
                        entries: existingEntries,
                        didExpand: false
                    )
                }
                let leftChildMap = leftChildren ?? [:]
                let rightChildMap = rightChildren ?? [:]
                var newLeftMap = leftMapSnapshot
                var newRightMap = rightMapSnapshot
                newLeftMap.removeValue(forKey: path)
                newRightMap.removeValue(forKey: path)
                for (key, url) in leftChildMap {
                    newLeftMap[key] = url
                }
                for (key, url) in rightChildMap {
                    newRightMap[key] = url
                }
                let allNewKeys = Set(leftChildMap.keys).union(rightChildMap.keys)
                let leftPartial = Dictionary(uniqueKeysWithValues: allNewKeys.compactMap { key in
                    newLeftMap[key].map { (key, $0) }
                })
                let rightPartial = Dictionary(uniqueKeysWithValues: allNewKeys.compactMap { key in
                    newRightMap[key].map { (key, $0) }
                })
                progressPublish.publish(
                    fractionCompleted: 0.9,
                    status: L10n.t("Comparing…"),
                    force: true
                )
                let newEntries = try DiffsplitterEngine.compareDirectoryMaps(
                    left: leftPartial,
                    right: rightPartial
                ) { completed, total in
                    let local = total > 0
                        ? 0.9 + 0.1 * Double(completed) / Double(total)
                        : 1.0
                    progressPublish.publish(
                        fractionCompleted: local,
                        status: L10n.t("Comparing…"),
                        force: false
                    )
                }
                var merged = existingEntries.filter { $0.relativePath != path }
                let replacedPaths = Set(newEntries.map(\.relativePath))
                merged.removeAll { replacedPaths.contains($0.relativePath) }
                merged.append(contentsOf: newEntries)
                merged.sort {
                    $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                }
                return NestedExpandPayload(
                    leftMap: newLeftMap,
                    rightMap: newRightMap,
                    entries: merged,
                    didExpand: true
                )
            }
            await MainActor.run { [self] in
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let payload):
                    if payload.didExpand {
                        self.leftFileMap = payload.leftMap
                        self.rightFileMap = payload.rightMap
                        self.directoryEntries = payload.entries
                        self.expandedContainerPaths.insert(path)
                        self.isComparing = false
                        self.memberLoadProgress = nil
                        self.selectedRelativePath = nil
                        self.applyRows([])
                        self.directoryBrowsePrefix = path
                        DiffsplitterCompletionFeedback.notifyIfNeeded(
                            elapsed: Date().timeIntervalSince(compareStartedAt),
                            label: compareLabel
                        )
                        EntityTracker.shared.record(
                            source: .diffsplitter,
                            arguments: [
                                TrackedEntity.DiffsplitterActivity.comparisonFinished.rawValue,
                                compareLabel
                            ]
                        )
                    } else {
                        self.openSkippedContainerAsFileComparison(
                            path: path,
                            entry: fallbackEntry
                        )
                    }
                case .failure(let error):
                    if error is CancellationError { return }
                    self.isComparing = false
                    self.memberLoadProgress = nil
                    if let containerError = error as? DiffsplitterContainer.ContainerError {
                        switch containerError {
                        case .aeaKeyRequired:
                            self.aeaKeyDraft = self.aeaSessionKeys[path] ?? ""
                            self.aeaKeyPrompt = AEAKeyPromptState(
                                path: path,
                                fallbackEntry: fallbackEntry
                            )
                            return
                        case .aeaDecryptFailed:
                            self.openSkippedContainerAsFileComparison(
                                path: path,
                                entry: fallbackEntry
                            )
                            return
                        default:
                            break
                        }
                    }
                    self.applyRows([])
                    self.setupError = error.localizedDescription
                }
            }
        }
    }
    private func openSkippedContainerAsFileComparison(
        path: String,
        entry: DiffsplitterEngine.DirEntry
    ) {
        skippedExpandPaths.insert(path)
        openDirectoryMember(path)
        beginDirectoryMemberCompare(path: path, entry: entry)
    }
    func beginDirectoryMemberCompare(
        path: String,
        entry: DiffsplitterEngine.DirEntry
    ) {
        if entry.status == .binary {
            presentBinaryDumpPrompt(path: path, entry: entry)
            return
        }
        clearBinaryDump()
        isComparing = true
        indexProgress = nil
        memberLoadProgress = DiffsplitterIndexProgress(
            fractionCompleted: 0,
            status: L10n.t("Loading…")
        )
        let ignoreWhitespace = self.ignoreWhitespace
        let leftSession = self.leftSession
        let rightSession = self.rightSession
        let leftURL = leftFileMap[path]
        let rightURL = rightFileMap[path]
        let status = entry.status
        let compareLabel = (path as NSString).lastPathComponent
        let compareStartedAt = Date()
        compareTask = Task.detached(priority: .userInitiated) {
            let progressPublish = DiffsplitterProgressPublisher { progress in
                Task { @MainActor [self] in
                    self.memberLoadProgress = progress
                }
            }

            enum Outcome {
                case rows([DiffsplitterEngine.AlignedRow])
                case hexDump(DiffsplitterBinaryDump.Session)
            }
            let result = Result {
                progressPublish.publish(
                    fractionCompleted: 0.02,
                    status: L10n.t("Loading…"),
                    force: true
                )
                let leftResolved: URL?
                if let leftURL {
                    leftResolved = try DiffsplitterContainer.resolvedFileURL(
                        for: leftURL,
                        session: leftSession
                    ) { completed, expected in
                        let local: Double
                        if let expected, expected > 0 {
                            local = min(0.2, Double(completed) / Double(expected) * 0.2)
                        } else {
                            local = 0.05
                        }
                        progressPublish.publish(
                            fractionCompleted: local,
                            status: L10n.t("Loading left…"),
                            force: false
                        )
                    }
                } else {
                    leftResolved = nil
                }
                let rightResolved: URL?
                if let rightURL {
                    rightResolved = try DiffsplitterContainer.resolvedFileURL(
                        for: rightURL,
                        session: rightSession
                    ) { completed, expected in
                        let local: Double
                        if let expected, expected > 0 {
                            local = 0.2 + min(0.2, Double(completed) / Double(expected) * 0.2)
                        } else {
                            local = 0.25
                        }
                        progressPublish.publish(
                            fractionCompleted: local,
                            status: L10n.t("Loading right…"),
                            force: false
                        )
                    }
                } else {
                    rightResolved = nil
                }
                let leftHex = try leftResolved.map { try DiffsplitterContent.prefersHexDump(resolvedURL: $0) } ?? false
                let rightHex = try rightResolved.map { try DiffsplitterContent.prefersHexDump(resolvedURL: $0) } ?? false
                if leftHex || rightHex {
                    progressPublish.publish(
                        fractionCompleted: 0.9,
                        status: L10n.t("Loading window…"),
                        force: true
                    )
                    let leftCount = leftResolved.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
                    let rightCount = rightResolved.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
                    let dump = try DiffsplitterBinaryDump.loadWindow(
                        leftURL: leftResolved,
                        rightURL: rightResolved,
                        leftByteCount: leftCount,
                        rightByteCount: rightCount,
                        startLine: 0
                    )
                    return Outcome.hexDump(dump)
                }
                progressPublish.publish(
                    fractionCompleted: 0.45,
                    status: L10n.t("Loading…"),
                    force: true
                )
                let leftLines: [String]
                let rightLines: [String]
                switch status {
                case .identical:
                    return Outcome.rows([])
                case .added:
                    leftLines = []
                    rightLines = try Self.decodeResolvedLines(rightResolved)
                case .removed:
                    leftLines = try Self.decodeResolvedLines(leftResolved)
                    rightLines = []
                case .modified:
                    leftLines = try Self.decodeResolvedLines(leftResolved)
                    rightLines = try Self.decodeResolvedLines(rightResolved)
                case .binary:
                    return Outcome.rows([])
                }
                progressPublish.publish(
                    fractionCompleted: 0.55,
                    status: L10n.t("Aligning…"),
                    force: true
                )
                let aligned = try DiffsplitterEngine.alignLines(
                    left: leftLines,
                    right: rightLines,
                    ignoreWhitespace: ignoreWhitespace
                ) { local in
                    progressPublish.publish(
                        fractionCompleted: 0.55 + 0.45 * local,
                        status: L10n.t("Aligning…"),
                        force: local >= 1
                    )
                }
                return Outcome.rows(aligned)
            }
            await MainActor.run { [self] in
                guard !Task.isCancelled else { return }
                self.isComparing = false
                self.memberLoadProgress = nil
                switch result {
                case .success(let outcome):
                    switch outcome {
                    case .rows(let aligned):
                        self.applyRows(aligned)
                    case .hexDump(let dump):
                        self.binaryDump = dump
                        self.binaryDumpOffsetField = String(
                            format: "%08x",
                            dump.windowStartLine * DiffsplitterBinaryDump.bytesPerLine
                        )
                        self.rows = []
                        self.visibleRowCount = 0
                    }
                    DiffsplitterCompletionFeedback.notifyIfNeeded(
                        elapsed: Date().timeIntervalSince(compareStartedAt),
                        label: compareLabel
                    )
                    EntityTracker.shared.record(
                        source: .diffsplitter,
                        arguments: [
                            TrackedEntity.DiffsplitterActivity.comparisonFinished.rawValue,
                            compareLabel
                        ]
                    )
                case .failure(let error):
                    if error is CancellationError { return }
                    self.applyRows([])
                    self.setupError = error.localizedDescription
                }
            }
        }
    }
    nonisolated private static func decodeResolvedLines(_ url: URL?) throws -> [String] {
        guard let url else { return [] }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try DiffsplitterContent.decode(data: data, displayURL: url).lines
    }
    private func presentBinaryDumpPrompt(path: String, entry: DiffsplitterEngine.DirEntry) {
        guard !isPresentingAppKitAlert else { return }
        let leftURL = leftFileMap[path]
        let rightURL = rightFileMap[path]
        let leftBytes = byteCount(for: leftURL) ?? 0
        let rightBytes = byteCount(for: rightURL) ?? 0
        let estimate = DiffsplitterBinaryDump.estimate(
            leftBytes: leftBytes,
            rightBytes: rightBytes,
            leftNeedsMaterialize: leftURL.map { DiffsplitterContainer.zipStubMetadata(at: $0) != nil } ?? false,
            rightNeedsMaterialize: rightURL.map { DiffsplitterContainer.zipStubMetadata(at: $0) != nil } ?? false
        )
        showBinaryMetadataRows(leftURL: leftURL, rightURL: rightURL)
        isPresentingAppKitAlert = true
        DiffsplitterFileAccess.presentBinaryDumpPrompt(estimate: estimate) { [weak self] result in
            guard let self else { return }
            self.isPresentingAppKitAlert = false
            switch result {
            case .inspectDump:
                self.beginBinaryDump(path: path, entry: entry)
            case .metadataOnly:
                self.beginBinaryMetadataCompare(path: path, entry: entry)
            case .cancel:
                self.leaveDirectoryDetail()
            }
        }
    }
    private func showBinaryMetadataRows(leftURL: URL?, rightURL: URL?) {
        clearBinaryDump()
        let leftLines = DiffsplitterContent.binaryMetadataLines(
            url: leftURL,
            byteCount: byteCount(for: leftURL)
        )
        let rightLines = DiffsplitterContent.binaryMetadataLines(
            url: rightURL,
            byteCount: byteCount(for: rightURL)
        )
        let rows = (try? DiffsplitterEngine.alignLines(
            left: leftLines,
            right: rightLines,
            ignoreWhitespace: false
        )) ?? []
        applyRows(rows)
    }
    private func beginBinaryMetadataCompare(path: String, entry: DiffsplitterEngine.DirEntry) {
        clearBinaryDump()
        isComparing = true
        memberLoadProgress = DiffsplitterIndexProgress(
            fractionCompleted: 0,
            status: L10n.t("Loading…")
        )
        let leftURL = leftFileMap[path]
        let rightURL = rightFileMap[path]
        let leftSession = self.leftSession
        let rightSession = self.rightSession
        let compareLabel = (path as NSString).lastPathComponent
        let compareStartedAt = Date()
        compareTask = Task.detached(priority: .userInitiated) {
            let result = Result {
                try DiffsplitterEngine.alignDirectoryEntry(
                    status: .binary,
                    leftURL: leftURL,
                    rightURL: rightURL,
                    leftSession: leftSession,
                    rightSession: rightSession,
                    ignoreWhitespace: false
                )
            }
            await MainActor.run { [self] in
                guard !Task.isCancelled else { return }
                self.isComparing = false
                self.memberLoadProgress = nil
                switch result {
                case .success(let aligned):
                    self.applyRows(aligned)
                    DiffsplitterCompletionFeedback.notifyIfNeeded(
                        elapsed: Date().timeIntervalSince(compareStartedAt),
                        label: compareLabel
                    )
                    EntityTracker.shared.record(
                        source: .diffsplitter,
                        arguments: [
                            TrackedEntity.DiffsplitterActivity.comparisonFinished.rawValue,
                            compareLabel
                        ]
                    )
                case .failure(let error):
                    if error is CancellationError { return }
                    self.setupError = error.localizedDescription
                }
            }
        }
    }
    private func beginBinaryDump(path: String, entry: DiffsplitterEngine.DirEntry) {
        compareTask?.cancel()
        isComparing = true
        indexProgress = nil
        memberLoadProgress = DiffsplitterIndexProgress(
            fractionCompleted: 0,
            status: L10n.t("Preparing binary dump…")
        )
        applyRows([])
        let leftStub = leftFileMap[path]
        let rightStub = rightFileMap[path]
        let leftSession = self.leftSession
        let rightSession = self.rightSession
        let preferDiskTemp = DiffsplitterSettings.preferDiskTempForLargeFiles()
        let compareLabel = (path as NSString).lastPathComponent
        let compareStartedAt = Date()
        compareTask = Task.detached(priority: .userInitiated) {
            let progressPublish = DiffsplitterProgressPublisher { progress in
                Task { @MainActor [self] in
                    self.memberLoadProgress = progress
                }
            }
            let result = Result {
                progressPublish.publish(
                    fractionCompleted: 0.05,
                    status: L10n.t("Materializing…"),
                    force: true
                )
                let leftSource: DiffsplitterBinaryDump.ByteSource?
                if let leftStub {
                    leftSource = try DiffsplitterContainer.resolveBinaryDumpSource(
                        for: leftStub,
                        session: leftSession,
                        preferDiskTemp: preferDiskTemp
                    ) { completed, expected in
                        let local: Double
                        if let expected, expected > 0 {
                            local = min(0.45, Double(completed) / Double(expected) * 0.45)
                        } else {
                            local = 0.1
                        }
                        progressPublish.publish(
                            fractionCompleted: local,
                            status: L10n.t("Materializing left…"),
                            force: false
                        )
                    }
                } else {
                    leftSource = nil
                }
                let rightSource: DiffsplitterBinaryDump.ByteSource?
                if let rightStub {
                    rightSource = try DiffsplitterContainer.resolveBinaryDumpSource(
                        for: rightStub,
                        session: rightSession,
                        preferDiskTemp: preferDiskTemp
                    ) { completed, expected in
                        let local: Double
                        if let expected, expected > 0 {
                            local = 0.45 + min(0.45, Double(completed) / Double(expected) * 0.45)
                        } else {
                            local = 0.55
                        }
                        progressPublish.publish(
                            fractionCompleted: local,
                            status: L10n.t("Materializing right…"),
                            force: false
                        )
                    }
                } else {
                    rightSource = nil
                }
                progressPublish.publish(
                    fractionCompleted: 0.95,
                    status: L10n.t("Loading window…"),
                    force: true
                )
                let leftCount = leftSource?.byteCount ?? 0
                let rightCount = rightSource?.byteCount ?? 0
                return try DiffsplitterBinaryDump.loadWindow(
                    left: leftSource,
                    right: rightSource,
                    leftByteCount: leftCount,
                    rightByteCount: rightCount,
                    startLine: 0
                )
            }
            await MainActor.run { [self] in
                guard !Task.isCancelled else { return }
                self.isComparing = false
                self.memberLoadProgress = nil
                switch result {
                case .success(let sessionDump):
                    self.binaryDump = sessionDump
                    self.binaryDumpOffsetField = String(format: "%08x", sessionDump.windowStartLine * DiffsplitterBinaryDump.bytesPerLine)
                    self.rows = []
                    self.visibleRowCount = 0
                    DiffsplitterCompletionFeedback.notifyIfNeeded(
                        elapsed: Date().timeIntervalSince(compareStartedAt),
                        label: compareLabel
                    )
                    EntityTracker.shared.record(
                        source: .diffsplitter,
                        arguments: [
                            TrackedEntity.DiffsplitterActivity.comparisonFinished.rawValue,
                            compareLabel
                        ]
                    )
                case .failure(let error):
                    if error is CancellationError { return }
                    self.setupError = error.localizedDescription
                    self.showBinaryMetadataRows(leftURL: leftStub, rightURL: rightStub)
                }
            }
        }
    }
    func binaryDumpPageUp() {
        guard let dump = binaryDump else { return }
        do {
            binaryDump = try DiffsplitterBinaryDump.pageUp(dump)
            syncBinaryDumpOffsetField()
        } catch {
            setupError = error.localizedDescription
        }
    }
    func binaryDumpPageDown() {
        guard let dump = binaryDump else { return }
        do {
            binaryDump = try DiffsplitterBinaryDump.pageDown(dump)
            syncBinaryDumpOffsetField()
        } catch {
            setupError = error.localizedDescription
        }
    }
    func binaryDumpJumpToOffsetField() {
        guard let dump = binaryDump else { return }
        let trimmed = binaryDumpOffsetField.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Int
        if trimmed.lowercased().hasPrefix("0x"),
           let parsed = Int(trimmed.dropFirst(2), radix: 16) {
            value = parsed
        } else if let hex = Int(trimmed, radix: 16), trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefABCDEF")) != nil {
            value = hex
        } else if let decimal = Int(trimmed) {
            value = decimal
        } else {
            setupError = L10n.t("Enter a byte offset in hex or decimal.")
            return
        }
        do {
            binaryDump = try DiffsplitterBinaryDump.jump(toOffsetBytes: value, session: dump)
            syncBinaryDumpOffsetField()
        } catch {
            setupError = error.localizedDescription
        }
    }
    private func syncBinaryDumpOffsetField() {
        guard let dump = binaryDump else { return }
        binaryDumpOffsetField = String(
            format: "%08x",
            dump.windowStartLine * DiffsplitterBinaryDump.bytesPerLine
        )
    }
    private func byteCount(for url: URL?) -> Int? {
        guard let url else { return nil }
        if let zip = DiffsplitterContainer.zipStubMetadata(at: url) {
            return zip.uncompressedSize
        }
        return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
    func applyRows(_ newRows: [DiffsplitterEngine.AlignedRow]) {
        rows = newRows
        visibleRowCount = 0
        guard !newRows.isEmpty else { return }
        if reduceMotion || newRows.count > 400 {
            visibleRowCount = newRows.count
            return
        }
        let batchSize = max(12, newRows.count / 24)
        Task { @MainActor [self] in
            var shown = 0
            while shown < newRows.count {
                try? await Task.sleep(nanoseconds: 16_000_000)
                shown = min(shown + batchSize, newRows.count)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    visibleRowCount = shown
                }
            }
        }
    }
    func isDirectoryLike(_ url: URL) -> Bool {
        (try? DiffsplitterEngine.sideKind(at: url)) == .directory
    }
    func copyUnifiedDiff() {
        DiffsplitterFileAccess.copyToPasteboard(currentUnifiedDiff())
    }
    func exportUnifiedDiff() {
        let text = currentUnifiedDiff()
        guard !text.isEmpty else { return }
        DiffsplitterFileAccess.exportText(
            title: L10n.t("Export Unified Diff"),
            suggestedName: "Diffsplitter.diff",
            contentTypes: [.plainText],
            text: text
        ) { [weak self] message in
            self?.documentError = message
        }
    }
    func exportDiffsplitterXDocument() {
        guard canExportDiffsplitterX else { return }
        documentTransferTask?.cancel()
        documentTransferProgress = DiffsplitterIndexProgress(
            fractionCompleted: 0,
            status: L10n.t("Preparing DiffsplitterX Document…")
        )
        let names = sideDisplayNames()
        let selectedPath = selectedRelativePath
        let ignoreWS = ignoreWhitespace
        let kind: DiffsplitterDocument.ComparisonKind =
            comparisonKind == .directories ? .directories : .files
        let existingRows = rows
        let dump = binaryDump
        let suggestedName = suggestedDiffsplitterXName()
        documentTransferTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled {
                    self.documentTransferProgress = nil
                }
            }
            do {
                await Task.yield()
                try Task.checkCancellation()
                let document = try await Task.detached(priority: .userInitiated) {
                    let exportRows: [DiffsplitterEngine.AlignedRow]
                    if !existingRows.isEmpty {
                        exportRows = existingRows
                    } else if let dump {
                        exportRows = try DiffsplitterBinaryDump.alignedRowsForExport(from: dump)
                    } else {
                        exportRows = []
                    }
                    return DiffsplitterXDocument(
                        leftName: names.left,
                        rightName: names.right,
                        selectedRelativePath: selectedPath,
                        ignoreWhitespace: ignoreWS,
                        comparisonKind: kind,
                        isHexDump: dump != nil,
                        rows: exportRows
                    )
                }.value
                try Task.checkCancellation()
                self.documentTransferProgress = nil
                let url = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                    DiffsplitterFileAccess.exportDocument(
                        title: L10n.t("Export DiffsplitterX Document"),
                        suggestedName: suggestedName
                    ) { url in
                        continuation.resume(returning: url)
                    }
                }
                guard let url else { return }
                try Task.checkCancellation()
                self.documentTransferProgress = DiffsplitterIndexProgress(
                    fractionCompleted: 0.5,
                    status: L10n.t("Writing DiffsplitterX Document…")
                )
                await Task.yield()
                try await Task.detached(priority: .userInitiated) {
                    try document.encoded().write(to: url, options: .atomic)
                }.value
                EntityTracker.shared.record(
                    source: .diffsplitter,
                    arguments: [
                        TrackedEntity.DiffsplitterActivity.documentExported.rawValue,
                        url.lastPathComponent
                    ]
                )
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    self.documentError = error.localizedDescription
                }
            }
        }
    }
    func currentDiffsplitterXDocument() throws -> DiffsplitterXDocument {
        let names = sideDisplayNames()
        return DiffsplitterXDocument(
            leftName: names.left,
            rightName: names.right,
            selectedRelativePath: selectedRelativePath,
            ignoreWhitespace: ignoreWhitespace,
            comparisonKind: comparisonKind == .directories ? .directories : .files,
            isHexDump: binaryDump != nil,
            rows: try rowsForDiffsplitterXExport()
        )
    }
    func rowsForDiffsplitterXExport() throws -> [DiffsplitterEngine.AlignedRow] {
        if !rows.isEmpty { return rows }
        guard let dump = binaryDump else { return [] }
        return try DiffsplitterBinaryDump.alignedRowsForExport(from: dump)
    }
    func sideDisplayNames() -> (left: String, right: String) {
        if isEmbeddedDocument {
            return (
                embeddedLeftName ?? L10n.t("Left"),
                embeddedRightName ?? L10n.t("Right")
            )
        }
        let leftName = leftURL?.lastPathComponent ?? "left"
        let rightName = rightURL?.lastPathComponent ?? "right"
        if comparisonKind == .directories, let path = selectedRelativePath {
            return ("\(leftName)/\(path)", "\(rightName)/\(path)")
        }
        return (leftName, rightName)
    }
    func suggestedDiffsplitterXName() -> String {
        let names = sideDisplayNames()
        let base = "\(names.left) vs \(names.right)"
            .replacingOccurrences(of: "/", with: "-")
        return "\(base).dspltx"
    }
    func currentUnifiedDiff() -> String {
        guard !rows.isEmpty else { return "" }
        let names = sideDisplayNames()
        return DiffsplitterEngine.unifiedDiff(leftName: names.left, rightName: names.right, rows: rows)
    }
    var currentDocument: DiffsplitterDocument {
        currentDocument(relativeTo: documentURL)
    }
    func currentDocument(relativeTo documentURL: URL?) -> DiffsplitterDocument {
        DiffsplitterDocument(
            leftPath: leftURL?.path,
            rightPath: rightURL?.path,
            leftBookmark: sideBookmark(leftURL, relativeTo: documentURL),
            rightBookmark: sideBookmark(rightURL, relativeTo: documentURL),
            comparisonKind: comparisonKind,
            ignoreWhitespace: ignoreWhitespace,
            selectedRelativePath: selectedRelativePath
        )
    }
    func sideBookmark(_ url: URL?, relativeTo documentURL: URL?) -> Data? {
#if DEBOOGEY_MCE
        guard let url, let documentURL else { return nil }
        return try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: documentURL
        )
#else
        return nil
#endif
    }
    func resolveSideURL(
        path: String?,
        bookmark: Data?,
        relativeTo documentURL: URL
    ) -> URL? {
#if DEBOOGEY_MCE
        if let bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: documentURL,
                bookmarkDataIsStale: &stale
            ), !stale {
                return url
            }
        }
#endif
        return path.map { URL(fileURLWithPath: $0) }
    }
    var hasUnsavedDocumentChanges: Bool {
        guard !isEmbeddedDocument else { return false }
        guard hasBothSides else { return false }
        return (try? currentDocument.encoded()) != savedDocumentData
    }
    func openDocument(at url: URL) {
        if url.pathExtension.lowercased() == "dspltx" {
            openDiffsplitterXDocument(at: url)
            return
        }
        do {
            let document = try DiffsplitterDocument.read(from: url)
            documentURL = url
            savedDocumentData = try document.encoded()
            ignoreWhitespace = document.ignoreWhitespace
            selectedRelativePath = document.selectedRelativePath
            let left = resolveSideURL(
                path: document.leftPath,
                bookmark: document.leftBookmark,
                relativeTo: url
            )
            let right = resolveSideURL(
                path: document.rightPath,
                bookmark: document.rightBookmark,
                relativeTo: url
            )
            clearSession(keepingDocument: true)
            documentURL = url
            savedDocumentData = try? document.encoded()
            ignoreWhitespace = document.ignoreWhitespace
            selectedRelativePath = document.selectedRelativePath
            if let left { assign(left, to: .left) }
            if let right { assign(right, to: .right) }
            if left == nil || right == nil {
                setupError = L10n.t("Could not restore one or both sides. Choose the missing items again.")
            }
        } catch {
            documentError = error.localizedDescription
        }
    }
    func openDiffsplitterXDocument(at url: URL) {
        documentTransferTask?.cancel()
        documentTransferProgress = DiffsplitterIndexProgress(
            fractionCompleted: 0,
            status: L10n.t("Importing DiffsplitterX Document…")
        )
        documentTransferTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled {
                    self.documentTransferProgress = nil
                }
            }
            do {
                await Task.yield()
                try Task.checkCancellation()
                let payload = try await Task.detached(priority: .userInitiated) {
                    let document = try DiffsplitterXDocument.read(from: url)
                    return (document, document.alignedRows())
                }.value
                try Task.checkCancellation()
                let document = payload.0
                let alignedRows = payload.1
                self.clearSession(keepingDocument: false)
                self.documentURL = url
                self.savedDocumentData = nil
                self.isEmbeddedDocument = true
                self.embeddedLeftName = document.leftName
                self.embeddedRightName = document.rightName
                self.ignoreWhitespace = document.ignoreWhitespace
                self.selectedRelativePath = document.selectedRelativePath
                self.comparisonKind = document.comparisonKind ?? .files
                if document.isHexDump == true
                    || DiffsplitterBinaryDump.looksLikeHexDump(alignedRows) {
                    let dump = DiffsplitterBinaryDump.sessionFromEmbeddedAlignedRows(alignedRows)
                    self.binaryDump = dump
                    self.binaryDumpOffsetField = String(
                        format: "%08x",
                        dump.windowStartLine * DiffsplitterBinaryDump.bytesPerLine
                    )
                    self.rows = []
                    self.visibleRowCount = 0
                } else {
                    self.applyRows(alignedRows)
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    self.documentError = error.localizedDescription
                }
            }
        }
    }
    func saveDocument(forceSaveAs: Bool) {
        if forceSaveAs {
            saveRedirectDocument(forceSaveAs: true)
            return
        }
        DiffsplitterFileAccess.presentSaveOrExportChooser(allowExport: canExportDiffsplitterX) { [weak self] choice in
            guard let self else { return }
            switch choice {
            case .save:
                self.saveRedirectDocument(forceSaveAs: false)
            case .export:
                self.exportDiffsplitterXDocument()
            case .cancel:
                break
            }
        }
    }
    func saveRedirectDocument(forceSaveAs: Bool) {
        guard hasBothSides else { return }
        let saveAs = forceSaveAs || documentURL == nil || documentURL?.pathExtension.lowercased() == "dspltx"
        if saveAs {
            DiffsplitterFileAccess.saveDocument(
                title: L10n.t("Save Diffsplitter Document"),
                suggestedName: suggestedRedirectDocumentName()
            ) { [weak self] url in
                guard let self, let url else { return }
                self.writeDocument(to: url)
            }
        } else if let documentURL {
            writeDocument(to: documentURL)
        }
    }
    func suggestedRedirectDocumentName() -> String {
        if let documentURL, documentURL.pathExtension.lowercased() == "dsplt" {
            return documentURL.lastPathComponent
        }
        return "Untitled.dsplt"
    }
    func writeDocument(to url: URL) {
        do {
            if isEmbeddedDocument {
                exitEmbeddedDocumentMode(clearRows: false)
            }
            let activity: TrackedEntity.DiffsplitterActivity = FileManager.default.fileExists(atPath: url.path)
                ? .documentModified
                : .documentCreated
            let document = currentDocument(relativeTo: url)
            let data = try document.encoded()
            try data.write(to: url, options: .atomic)
            documentURL = url
            savedDocumentData = data
            EntityTracker.shared.record(
                source: .diffsplitter,
                arguments: [activity.rawValue, url.lastPathComponent]
            )
        } catch {
            documentError = error.localizedDescription
        }
    }
    func saveDraftForClosing(completion: @escaping (Bool) -> Void) {
        guard hasBothSides, !isEmbeddedDocument else {
            completion(true)
            return
        }
        if documentURL == nil || documentURL?.pathExtension.lowercased() == "dspltx" {
            DiffsplitterFileAccess.saveDocument(
                title: L10n.t("Save Diffsplitter Document"),
                suggestedName: "Untitled.dsplt"
            ) { [weak self] url in
                guard let self, let url else {
                    completion(false)
                    return
                }
                self.writeDocument(to: url)
                completion(self.documentError == nil)
            }
        } else if let documentURL {
            writeDocument(to: documentURL)
            completion(documentError == nil)
        } else {
            completion(false)
        }
    }
    func presentMessageAlert(title: String, message: String?, clear: @escaping () -> Void) {
        guard let message, !message.isEmpty, !isPresentingAppKitAlert else { return }
        isPresentingAppKitAlert = true
        DiffsplitterFileAccess.presentMessageAlert(title: title, message: message) { [weak self] in
            clear()
            self?.isPresentingAppKitAlert = false
        }
    }
    func presentAEAKeyPromptIfNeeded() {
        guard let prompt = aeaKeyPrompt, !isPresentingAppKitAlert else { return }
        isPresentingAppKitAlert = true
        let initial = aeaSessionKeys[prompt.path] ?? aeaKeyDraft
        DiffsplitterFileAccess.presentAEAKeyPrompt(initialValue: initial) { [weak self] result in
            guard let self else { return }
            self.aeaKeyPrompt = nil
            self.aeaKeyDraft = ""
            self.isPresentingAppKitAlert = false
            switch result {
            case .decrypt(let draft):
                guard let normalized = DiffsplitterAEA.normalizeKeyValue(draft) else {
                    self.openSkippedContainerAsFileComparison(
                        path: prompt.path,
                        entry: prompt.fallbackEntry
                    )
                    return
                }
                self.aeaSessionKeys[prompt.path] = normalized
                self.expandSelectedNestedContainer(path: prompt.path, fallbackEntry: prompt.fallbackEntry)
            case .metadataOnly:
                self.openSkippedContainerAsFileComparison(
                    path: prompt.path,
                    entry: prompt.fallbackEntry
                )
            }
        }
    }
}
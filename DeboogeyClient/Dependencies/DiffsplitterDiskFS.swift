//
//  DiffsplitterDiskFS.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation

nonisolated enum DiffsplitterDiskFS {
    struct Entry: Sendable, Equatable {
        let path: String
        let isDirectory: Bool
        let size: UInt64
        let fileID: UInt64
    }

    enum DiskFSError: LocalizedError {
        case noFilesystem
        case truncated
        case unsupported
        case notFound
        case readFailed(String)

        var errorDescription: String? {
            switch self {
            case .noFilesystem:
                return L10n.t("No readable HFS+ or APFS volume was found in the disk image.")
            case .truncated:
                return L10n.t("The disk image filesystem is truncated or unreadable.")
            case .unsupported:
                return L10n.t("This disk image filesystem feature is not supported.")
            case .notFound:
                return L10n.t("The file was not found in the disk image.")
            case .readFailed(let detail):
                return L10n.f("Could not read from the disk image: %@", detail)
            }
        }
    }

    final class Volume: @unchecked Sendable {
        enum Kind {
            case hfsPlus(HFSPlusVolume)
            case apfs(APFSVolume)
        }

        let kind: Kind
        let disk: DiffsplitterUDIFDisk
        let partitionOffset: UInt64

        init(kind: Kind, disk: DiffsplitterUDIFDisk, partitionOffset: UInt64) {
            self.kind = kind
            self.disk = disk
            self.partitionOffset = partitionOffset
        }

        func listEntries(maxEntries: Int) throws -> [Entry] {
            switch kind {
            case .hfsPlus(let vol):
                return try vol.listEntries(maxEntries: maxEntries)
            case .apfs(let vol):
                return try vol.listEntries(maxEntries: maxEntries)
            }
        }

        func readFile(path: String) throws -> Data {
            switch kind {
            case .hfsPlus(let vol):
                return try vol.readFile(path: path)
            case .apfs(let vol):
                return try vol.readFile(path: path)
            }
        }
    }

    static func open(image: URL) throws -> Volume {
        let disk = try DiffsplitterUDIFDisk.open(url: image)
        let partitions = try discoverPartitions(disk: disk)
        for part in partitions {
            if let hfs = try? HFSPlusVolume.open(disk: disk, partitionOffset: part.offset) {
                return Volume(kind: .hfsPlus(hfs), disk: disk, partitionOffset: part.offset)
            }
            if let apfs = try? APFSVolume.open(disk: disk, partitionOffset: part.offset) {
                return Volume(kind: .apfs(apfs), disk: disk, partitionOffset: part.offset)
            }
        }

        if let hfs = try? HFSPlusVolume.open(disk: disk, partitionOffset: 0) {
            return Volume(kind: .hfsPlus(hfs), disk: disk, partitionOffset: 0)
        }
        if let apfs = try? APFSVolume.open(disk: disk, partitionOffset: 0) {
            return Volume(kind: .apfs(apfs), disk: disk, partitionOffset: 0)
        }
        throw DiskFSError.noFilesystem
    }

    private struct Partition {
        let offset: UInt64
        let size: UInt64
        let name: String
    }

    private static func discoverPartitions(disk: DiffsplitterUDIFDisk) throws -> [Partition] {
        var result: [Partition] = []
        if let gpt = try? readGPT(disk: disk) {
            result.append(contentsOf: gpt)
        }
        if let apm = try? readAPM(disk: disk) {
            result.append(contentsOf: apm)
        }
        return result
    }

    private static func readGPT(disk: DiffsplitterUDIFDisk) throws -> [Partition] {
        let header = try disk.read(offset: 512, length: 512)
        guard header.starts(with: Data("EFI PART".utf8)) else { return [] }
        let entryLBA = DiffsplitterBinaryIO.readUInt64LE(header, 72)
        let entryCount = Int(DiffsplitterBinaryIO.readUInt32LE(header, 80))
        let entrySize = Int(DiffsplitterBinaryIO.readUInt32LE(header, 84))
        guard entryCount > 0, entryCount < 4096, entrySize >= 128 else { return [] }
        let tableOffset = entryLBA * 512
        let table = try disk.read(offset: tableOffset, length: entryCount * entrySize)
        var partitions: [Partition] = []

        for i in 0..<entryCount {
            let o = i * entrySize
            let typeGUID = table.subdata(in: o..<(o + 16))
            if typeGUID.allSatisfy({ $0 == 0 }) { continue }
            let firstLBA = DiffsplitterBinaryIO.readUInt64LE(table, o + 32)
            let lastLBA = DiffsplitterBinaryIO.readUInt64LE(table, o + 40)
            guard lastLBA >= firstLBA else { continue }
            let nameData = table.subdata(in: (o + 56)..<(o + 128))
            let name = String(data: nameData, encoding: .utf16LittleEndian)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                ?? "partition-\(i)"
            partitions.append(
                Partition(
                    offset: firstLBA * 512,
                    size: (lastLBA - firstLBA + 1) * 512,
                    name: name
                )
            )
        }
        return partitions
    }

    private static func readAPM(disk: DiffsplitterUDIFDisk) throws -> [Partition] {
        let dd = try disk.read(offset: 0, length: 512)

        guard dd.count >= 2, dd[0] == 0x45, dd[1] == 0x52 else { return [] }
        let blockSize = Int(DiffsplitterBinaryIO.readUInt16BE(dd, 2))
        guard blockSize == 512 || blockSize == 2048 else { return [] }
        let first = try disk.read(offset: UInt64(blockSize), length: blockSize)
        guard first.count >= 8, first[0] == 0x50, first[1] == 0x4D else { return [] }
        let mapBlockCount = Int(DiffsplitterBinaryIO.readUInt32BE(first, 4))
        guard mapBlockCount > 0, mapBlockCount < 64 else { return [] }
        var partitions: [Partition] = []
        for i in 0..<mapBlockCount {
            let entry = i == 0 ? first : try disk.read(offset: UInt64((i + 1) * blockSize), length: blockSize)
            guard entry.count >= 48, entry[0] == 0x50, entry[1] == 0x4D else { continue }
            let pyPartStart = DiffsplitterBinaryIO.readUInt32BE(entry, 8)
            let pyPartBlocks = DiffsplitterBinaryIO.readUInt32BE(entry, 12)
            let typeBytes = entry.subdata(in: 48..<80)
            let typeName = String(bytes: typeBytes.prefix(while: { $0 != 0 }), encoding: .macOSRoman)
                ?? String(bytes: typeBytes.prefix(while: { $0 != 0 }), encoding: .ascii)
                ?? ""
            if typeName.contains("HFS") || typeName.contains("Apple_HFS")
                || typeName.contains("APFS") || typeName.contains("Apple_APFS")
                || typeName == "Apple_HFSX" {
                partitions.append(
                    Partition(
                        offset: UInt64(pyPartStart) * UInt64(blockSize),
                        size: UInt64(pyPartBlocks) * UInt64(blockSize),
                        name: typeName
                    )
                )
            }
        }
        return partitions
    }

    final class HFSPlusVolume: @unchecked Sendable {
        private let disk: DiffsplitterUDIFDisk
        private let partitionOffset: UInt64
        private let blockSize: UInt32
        private let catalogFile: ForkData
        private var catalogCache: [Entry]?

        struct ForkData {
            var extents: [(start: UInt32, count: UInt32)]
            var logicalSize: UInt64
        }

        static func open(disk: DiffsplitterUDIFDisk, partitionOffset: UInt64) throws -> HFSPlusVolume {
            let header = try disk.read(offset: partitionOffset + 1024, length: 512)
            guard header.count >= 512 else { throw DiskFSError.truncated }
            let sig = DiffsplitterBinaryIO.readUInt16BE(header, 0)
            guard sig == 0x482B || sig == 0x4858 else { throw DiskFSError.noFilesystem }
            let blockSize = DiffsplitterBinaryIO.readUInt32BE(header, 0x28)
            guard blockSize >= 512, blockSize <= 64 * 1024 else { throw DiskFSError.truncated }

            let catalog = try Self.parseForkData(header, offset: 0x110)
            return HFSPlusVolume(
                disk: disk,
                partitionOffset: partitionOffset,
                blockSize: blockSize,
                catalogFile: catalog
            )
        }

        private init(
            disk: DiffsplitterUDIFDisk,
            partitionOffset: UInt64,
            blockSize: UInt32,
            catalogFile: ForkData
        ) {
            self.disk = disk
            self.partitionOffset = partitionOffset
            self.blockSize = blockSize
            self.catalogFile = catalogFile
        }

        func listEntries(maxEntries: Int) throws -> [Entry] {
            if let catalogCache { return Array(catalogCache.prefix(maxEntries)) }
            var entries: [Entry] = []
            try walkCatalog(nodeOffset: nil, pathPrefix: "", into: &entries, maxEntries: maxEntries)
            catalogCache = entries
            return entries
        }

        func readFile(path: String) throws -> Data {
            try readFileRecord(path: path)
        }

        private func readFileRecord(path: String) throws -> Data {
            var found: Data?
            try enumerateCatalog { rec in
                guard rec.kind == .file, rec.path == path else { return }
                found = try readFork(rec.dataFork)
            }
            guard let found else { throw DiskFSError.notFound }
            return found
        }

        private struct CatalogRec {
            enum Kind { case folder, file }
            let kind: Kind
            let path: String
            let fileID: UInt32
            let dataFork: ForkData
            let size: UInt64
        }

        private func walkCatalog(
            nodeOffset: UInt64?,
            pathPrefix: String,
            into entries: inout [Entry],
            maxEntries: Int
        ) throws {
            try enumerateCatalog { rec in
                guard entries.count < maxEntries else { return }
                entries.append(
                    Entry(
                        path: rec.path,
                        isDirectory: rec.kind == .folder,
                        size: rec.size,
                        fileID: UInt64(rec.fileID)
                    )
                )
            }
        }

        private func enumerateCatalog(_ body: (CatalogRec) throws -> Void) throws {
            let headerNode = try readForkRange(catalogFile, offset: 0, length: 512)
            guard headerNode.count >= 144 else { throw DiskFSError.truncated }
            let nodeSize = Int(DiffsplitterBinaryIO.readUInt16BE(headerNode, 32))
            let rootNode = UInt32(DiffsplitterBinaryIO.readUInt32BE(headerNode, 24))
            let firstLeaf = UInt32(DiffsplitterBinaryIO.readUInt32BE(headerNode, 36))
            guard nodeSize >= 512, nodeSize <= 32 * 1024 else { throw DiskFSError.truncated }
            var nodeNum = firstLeaf != 0 ? firstLeaf : rootNode
            var parentNames: [UInt32: String] = [1: ""]
            parentNames[2] = ""
            var visited = Set<UInt32>()
            while nodeNum != 0 && !visited.contains(nodeNum) {
                try Task.checkCancellation()
                visited.insert(nodeNum)
                let nodeData = try readForkRange(
                    catalogFile,
                    offset: UInt64(nodeNum) * UInt64(nodeSize),
                    length: nodeSize
                )
                guard nodeData.count == nodeSize else { throw DiskFSError.truncated }
                let kind = nodeData[8]
                let numRecords = Int(DiffsplitterBinaryIO.readUInt16BE(nodeData, 10))
                if kind == 0xFF {
                    for i in 0..<numRecords {
                        let recOffset = Int(DiffsplitterBinaryIO.readUInt16BE(nodeData, nodeSize - 2 * (i + 1)))
                        guard recOffset + 2 <= nodeSize else { continue }

                        let keyLen = Int(DiffsplitterBinaryIO.readUInt16BE(nodeData, recOffset))
                        let keyStart = recOffset + 2
                        guard keyStart + keyLen <= nodeSize else { continue }
                        let parentID = DiffsplitterBinaryIO.readUInt32BE(nodeData, keyStart)
                        let nameLen = Int(DiffsplitterBinaryIO.readUInt16BE(nodeData, keyStart + 4))
                        let nameBytesStart = keyStart + 6
                        let nameByteCount = nameLen * 2
                        guard nameBytesStart + nameByteCount <= keyStart + keyLen else { continue }
                        let nameData = nodeData.subdata(in: nameBytesStart..<(nameBytesStart + nameByteCount))
                        let name = String(data: nameData, encoding: .utf16BigEndian) ?? ""
                        let dataStart = keyStart + keyLen
                        let aligned = (dataStart + 1) & ~1
                        guard aligned + 2 <= nodeSize else { continue }
                        let recordType = DiffsplitterBinaryIO.readUInt16BE(nodeData, aligned)
                        let parentPath = parentNames[parentID] ?? ""
                        let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
                        if recordType == 1 {
                            let folderID = DiffsplitterBinaryIO.readUInt32BE(nodeData, aligned + 8)
                            parentNames[folderID] = path
                            try body(
                                CatalogRec(
                                    kind: .folder,
                                    path: path,
                                    fileID: folderID,
                                    dataFork: ForkData(extents: [], logicalSize: 0),
                                    size: 0
                                )
                            )
                        } else if recordType == 2 {
                            let fileID = DiffsplitterBinaryIO.readUInt32BE(nodeData, aligned + 8)

                            let forkOffset = aligned + 0x58
                            guard forkOffset + 80 <= nodeSize else { continue }
                            let fork = try Self.parseForkData(nodeData, offset: forkOffset)
                            try body(
                                CatalogRec(
                                    kind: .file,
                                    path: path,
                                    fileID: fileID,
                                    dataFork: fork,
                                    size: fork.logicalSize
                                )
                            )
                        }
                    }
                    let flink = DiffsplitterBinaryIO.readUInt32BE(nodeData, 0)
                    nodeNum = flink
                } else {
                    break
                }
            }
        }

        private func readFork(_ fork: ForkData) throws -> Data {
            guard fork.logicalSize <= UInt64(256 * 1024 * 1024) else {
                throw DiskFSError.readFailed("file too large")
            }
            return try readForkRange(fork, offset: 0, length: Int(fork.logicalSize))
        }

        private func readForkRange(_ fork: ForkData, offset: UInt64, length: Int) throws -> Data {
            if length == 0 { return Data() }
            var result = Data()
            result.reserveCapacity(length)
            var remaining = length
            var logical = offset
            var extentLogicalBase: UInt64 = 0
            for extent in fork.extents {
                let extentBytes = UInt64(extent.count) * UInt64(blockSize)
                if logical >= extentLogicalBase + extentBytes {
                    extentLogicalBase += extentBytes
                    continue
                }
                let intoExtent = logical - extentLogicalBase
                let canTake = min(UInt64(remaining), extentBytes - intoExtent)
                let absOffset = partitionOffset
                    + UInt64(extent.start) * UInt64(blockSize)
                    + intoExtent
                let chunk = try disk.read(offset: absOffset, length: Int(canTake))
                result.append(chunk)
                remaining -= chunk.count
                logical += UInt64(chunk.count)
                extentLogicalBase += extentBytes
                if remaining == 0 { break }
            }
            if result.count < length {
                throw DiskFSError.readFailed("incomplete fork read")
            }
            return result
        }

        private static func parseForkData(_ data: Data, offset: Int) throws -> ForkData {
            let logicalSize = DiffsplitterBinaryIO.readUInt64BE(data, offset)
            var extents: [(UInt32, UInt32)] = []

            for i in 0..<8 {
                let eo = offset + 16 + i * 8
                guard eo + 8 <= data.count else { break }
                let start = DiffsplitterBinaryIO.readUInt32BE(data, eo)
                let count = DiffsplitterBinaryIO.readUInt32BE(data, eo + 4)
                if count == 0 { break }
                extents.append((start, count))
            }
            return ForkData(extents: extents, logicalSize: logicalSize)
        }
    }

    final class APFSVolume: @unchecked Sendable {
        private let volume: DiffsplitterAPFS.Volume

        static func open(disk: DiffsplitterUDIFDisk, partitionOffset: UInt64) throws -> APFSVolume {
            do {
                let volume = try DiffsplitterAPFS.Volume.open(disk: disk, partitionOffset: partitionOffset)
                return APFSVolume(volume: volume)
            } catch let error as DiffsplitterAPFS.APFSError {
                switch error {
                case .noFilesystem:
                    throw DiskFSError.noFilesystem
                case .truncated:
                    throw DiskFSError.truncated
                case .encrypted, .unsupported:
                    throw DiskFSError.unsupported
                case .notFound:
                    throw DiskFSError.notFound
                case .readFailed(let detail):
                    throw DiskFSError.readFailed(detail)
                }
            }
        }

        private init(volume: DiffsplitterAPFS.Volume) {
            self.volume = volume
        }

        func listEntries(maxEntries: Int) throws -> [Entry] {
            do {
                return try volume.listEntries(maxEntries: maxEntries)
            } catch let error as DiffsplitterAPFS.APFSError {
                throw mapAPFSError(error)
            }
        }

        func readFile(path: String) throws -> Data {
            do {
                return try volume.readFile(path: path)
            } catch let error as DiffsplitterAPFS.APFSError {
                throw mapAPFSError(error)
            }
        }

        private func mapAPFSError(_ error: DiffsplitterAPFS.APFSError) -> DiskFSError {
            switch error {
            case .noFilesystem: return .noFilesystem
            case .truncated: return .truncated
            case .encrypted, .unsupported: return .unsupported
            case .notFound: return .notFound
            case .readFailed(let detail): return .readFailed(detail)
            }
        }
    }
}

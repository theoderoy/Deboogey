//
//  DiffsplitterAPFS.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation
import Compression

nonisolated enum DiffsplitterAPFS {
    enum APFSError: LocalizedError {
        case truncated
        case noFilesystem
        case encrypted
        case notFound
        case unsupported(String)
        case readFailed(String)

        var errorDescription: String? {
            switch self {
            case .truncated:
                return L10n.t("The APFS container is truncated or unreadable.")
            case .noFilesystem:
                return L10n.t("No readable APFS volume was found in the disk image.")
            case .encrypted:
                return L10n.t("Encrypted APFS volumes are not supported.")
            case .notFound:
                return L10n.t("The file was not found in the APFS volume.")
            case .unsupported(let detail):
                return L10n.f("Unsupported APFS feature: %@", detail)
            case .readFailed(let detail):
                return L10n.f("Could not read from the APFS volume: %@", detail)
            }
        }
    }

    final class Volume: @unchecked Sendable {
        private let disk: DiffsplitterUDIFDisk
        private let partitionOffset: UInt64
        private let blockSize: Int
        private let fsRootPaddr: UInt64
        private var oidIndex: [UInt64: UInt64]
        private var catalog: DiffsplitterAPFSFsTree.Catalog?
        private var pathCache: [String: (inode: UInt64, size: UInt64)]?

        fileprivate init(
            disk: DiffsplitterUDIFDisk,
            partitionOffset: UInt64,
            blockSize: Int,
            fsRootPaddr: UInt64,
            oidIndex: [UInt64: UInt64]
        ) {
            self.disk = disk
            self.partitionOffset = partitionOffset
            self.blockSize = blockSize
            self.fsRootPaddr = fsRootPaddr
            self.oidIndex = oidIndex
        }

        static func open(disk: DiffsplitterUDIFDisk, partitionOffset: UInt64) throws -> Volume {
            typealias T = DiffsplitterAPFSTypes
            let nx = try readDisk(disk, offset: partitionOffset, length: 4096)
            guard nx.count >= 64, T.readU32(nx, 32) == T.nxMagic else {
                throw APFSError.noFilesystem
            }
            let blockSize = Int(T.readU32(nx, 36))
            guard blockSize >= 4096, blockSize <= 65_536 else { throw APFSError.truncated }

            let nextXid = T.readU64(nx, 96)
            let containerOmapOID = T.readU64(nx, 160)

            func readBlock(_ paddr: UInt64) throws -> Data {
                let off = partitionOffset + paddr * UInt64(blockSize)
                return try readDisk(disk, offset: off, length: blockSize)
            }

            let comapPhys = try readBlock(containerOmapOID)
            guard let comapObj = T.parseObjPhys(comapPhys),
                  comapObj.typeCode == T.objectTypeOmap
            else { throw APFSError.noFilesystem }
            let comapTreeOID = T.readU64(comapPhys, 48)
            let containerOmap = try DiffsplitterAPFSOMap.walk(
                rootPaddr: comapTreeOID,
                blockSize: blockSize,
                readBlock: readBlock
            )

            var volumeOID: UInt64?

            for i in 0..<8 {
                let oid = T.readU64(nx, 176 + i * 8)
                if oid > 1, oid < (1 << 40) {
                    if DiffsplitterAPFSOMap.resolve(oid: oid, entries: containerOmap, maxXid: nextXid) != nil {
                        volumeOID = oid
                        break
                    }
                }
            }
            if volumeOID == nil {
                for entry in DiffsplitterAPFSOMap.latestByOID(containerOmap).values {
                    let blk = try readBlock(entry.paddr)
                    if T.readU32(blk, 32) == T.apfsMagic {
                        volumeOID = entry.oid
                        break
                    }
                }
            }
            guard let volOID = volumeOID,
                  let volMap = DiffsplitterAPFSOMap.resolve(oid: volOID, entries: containerOmap, maxXid: nextXid)
            else {
                throw APFSError.noFilesystem
            }

            let apsb = try readBlock(volMap.paddr)
            guard T.readU32(apsb, 32) == T.apfsMagic else { throw APFSError.noFilesystem }

            let (rootTreeOID, incompat) = try parseAPSB(apsb)
            if (incompat & T.apfsIncompatEncrypted) != 0 {
                throw APFSError.encrypted
            }

            if hasWrappedVolumeKey(apsb) {
                throw APFSError.encrypted
            }

            let oidIndex = try buildOIDIndex(
                disk: disk,
                partitionOffset: partitionOffset,
                blockSize: blockSize,
                partitionBlocks: estimateBlockCount(disk: disk, partitionOffset: partitionOffset, blockSize: blockSize)
            )

            let fsRootPaddr: UInt64
            if let p = oidIndex[rootTreeOID] {
                fsRootPaddr = p
            } else if let scanned = findFsTreeRoot(oidIndex: oidIndex, readBlock: readBlock) {
                fsRootPaddr = scanned
            } else {
                throw APFSError.noFilesystem
            }

            return Volume(
                disk: disk,
                partitionOffset: partitionOffset,
                blockSize: blockSize,
                fsRootPaddr: fsRootPaddr,
                oidIndex: oidIndex
            )
        }

        func listEntries(maxEntries: Int) throws -> [DiffsplitterDiskFS.Entry] {
            let paths = try ensurePaths(maxEntries: maxEntries)
            return paths.map {
                DiffsplitterDiskFS.Entry(
                    path: $0.path,
                    isDirectory: false,
                    size: $0.size,
                    fileID: $0.inode
                )
            }
        }

        func readFile(path: String) throws -> Data {
            let paths = try ensurePaths(maxEntries: DiffsplitterContainer.maxEntries)
            guard let meta = pathCache?[path] ?? paths.first(where: { $0.path == path }).map({ ($0.inode, $0.size) })
            else {
                throw APFSError.notFound
            }
            let catalog = try ensureCatalog()
            return try readInode(meta.inode, catalog: catalog)
        }

        private func ensureCatalog() throws -> DiffsplitterAPFSFsTree.Catalog {
            if let catalog { return catalog }
            let loaded = try DiffsplitterAPFSFsTree.loadCatalog(
                rootPaddr: fsRootPaddr,
                blockSize: blockSize,
                resolveOID: { [oidIndex] oid in oidIndex[oid] },
                readBlock: { [self] paddr in try self.readBlock(paddr) }
            )
            catalog = loaded
            return loaded
        }

        private func ensurePaths(maxEntries: Int) throws -> [(path: String, inode: UInt64, size: UInt64)] {
            if let pathCache {
                let all = pathCache.map { (path: $0.key, inode: $0.value.inode, size: $0.value.size) }
                    .sorted { $0.path < $1.path }
                return Array(all.prefix(maxEntries))
            }
            let catalog = try ensureCatalog()
            let listed = try DiffsplitterAPFSFsTree.listFilePaths(
                catalog: catalog,
                maxEntries: DiffsplitterContainer.maxEntries
            )
            var cache: [String: (inode: UInt64, size: UInt64)] = [:]
            for item in listed {
                cache[item.path] = (item.inode, item.size)
            }
            pathCache = cache
            return Array(listed.prefix(maxEntries))
        }

        private func readBlock(_ paddr: UInt64) throws -> Data {
            let off = partitionOffset + paddr * UInt64(blockSize)
            return try Self.readDisk(disk, offset: off, length: blockSize)
        }

        private func readInode(_ inode: UInt64, catalog: DiffsplitterAPFSFsTree.Catalog) throws -> Data {
            guard let inodeVal = catalog.inodes[inode] else {
                throw APFSError.notFound
            }
            if let decmpfsVal = catalog.xattrs[inode]?["com.apple.decmpfs"],
               let header = DiffsplitterAPFSFsTree.parseDecmpfsHeader(decmpfsVal) {
                return try decompressDecmpfs(
                    header: header,
                    inode: inode,
                    catalog: catalog
                )
            }
            let privateID = DiffsplitterAPFSFsTree.privateID(fromInode: inodeVal)
            let size: UInt64
            if let ds = DiffsplitterAPFSFsTree.parseDstream(fromInode: inodeVal) {
                size = ds.size
            } else {
                size = DiffsplitterAPFSFsTree.logicalSize(inode: inode, catalog: catalog)
            }
            return try readStream(streamID: privateID, size: size, catalog: catalog)
        }

        private func readStream(
            streamID: UInt64,
            size: UInt64,
            catalog: DiffsplitterAPFSFsTree.Catalog
        ) throws -> Data {
            if size == 0 { return Data() }
            guard size <= UInt64(Int.max) else {
                throw APFSError.unsupported("file too large")
            }
            var out = Data(count: Int(size))
            let extents = catalog.extents[streamID] ?? []
            for (logical, length, phys) in extents {
                try Task.checkCancellation()
                if phys == 0 { continue }
                guard logical < size else { continue }
                let take = min(length, size - logical)
                guard take > 0 else { continue }
                let byteOff = partitionOffset + phys * UInt64(blockSize)
                let chunk = try Self.readDisk(disk, offset: byteOff, length: Int(take))
                let dest = Int(logical)
                let copyCount = min(chunk.count, Int(size) - dest)
                if copyCount > 0 {
                    out.replaceSubrange(dest..<(dest + copyCount), with: chunk.prefix(copyCount))
                }
            }
            return out
        }

        private func decompressDecmpfs(
            header: DiffsplitterAPFSFsTree.DecmpfsHeader,
            inode: UInt64,
            catalog: DiffsplitterAPFSFsTree.Catalog
        ) throws -> Data {
            typealias T = DiffsplitterAPFSTypes
            let usize = header.uncompressedSize
            guard usize <= UInt64(Int.max) else {
                throw APFSError.unsupported("compressed file too large")
            }
            switch header.compressionType {
            case T.decmpfsTypeInlineUncompressed:

                var payload = header.payload
                if payload.first == T.decmpfsUncompressedMarker {
                    payload = payload.dropFirst()
                }
                guard payload.count >= Int(usize) else {
                    throw APFSError.truncated
                }
                return Data(payload.prefix(Int(usize)))

            case T.decmpfsTypeLZBITMAPResource:
                guard let rf = catalog.xattrs[inode]?["com.apple.ResourceFork"],
                      let stream = DiffsplitterAPFSFsTree.resourceForkStreamID(rf)
                else {
                    throw APFSError.unsupported("decmpfs resource fork missing")
                }
                let rsrc = try readStream(streamID: stream.streamID, size: stream.size, catalog: catalog)
                return try decodeLZBITMAPResource(rsrc, uncompressedSize: Int(usize))

            default:
                throw APFSError.unsupported("decmpfs type \(header.compressionType)")
            }
        }

        private func decodeLZBITMAPResource(_ rsrc: Data, uncompressedSize: Int) throws -> Data {
            typealias T = DiffsplitterAPFSTypes
            let chunkU = T.decmpfsChunkUncompressed
            let nChunks = (uncompressedSize + chunkU - 1) / chunkU
            guard rsrc.count >= (nChunks + 1) * 4 else {
                throw APFSError.truncated
            }
            var offsets: [Int] = []
            offsets.reserveCapacity(nChunks + 1)
            for i in 0..<(nChunks + 1) {
                offsets.append(Int(T.readU32(rsrc, i * 4)))
            }
            var out = Data()
            out.reserveCapacity(uncompressedSize)
            for i in 0..<nChunks {
                let expect = min(chunkU, uncompressedSize - i * chunkU)
                let start = offsets[i]
                let end = offsets[i + 1]
                guard start >= 0, end <= rsrc.count, start < end else {
                    throw APFSError.truncated
                }
                let chunk = rsrc.subdata(in: start..<end)
                var decoded = Data(count: expect)
                let n = decoded.withUnsafeMutableBytes { outBuf -> Int in
                    chunk.withUnsafeBytes { inBuf -> Int in
                        guard let outPtr = outBuf.bindMemory(to: UInt8.self).baseAddress,
                              let inPtr = inBuf.bindMemory(to: UInt8.self).baseAddress
                        else { return 0 }
                        return compression_decode_buffer(
                            outPtr, expect,
                            inPtr, chunk.count,
                            nil,
                            COMPRESSION_LZBITMAP
                        )
                    }
                }
                guard n == expect else {
                    throw APFSError.unsupported("LZBITMAP decode failed")
                }
                out.append(decoded)
            }
            return out
        }

        private static func readDisk(_ disk: DiffsplitterUDIFDisk, offset: UInt64, length: Int) throws -> Data {
            do {
                return try disk.read(offset: offset, length: length)
            } catch {
                throw APFSError.readFailed(error.localizedDescription)
            }
        }

        private static func parseAPSB(_ apsb: Data) throws -> (rootTreeOID: UInt64, incompat: UInt64) {
            typealias T = DiffsplitterAPFSTypes
            guard apsb.count >= 160 else { throw APFSError.truncated }
            let incompat = T.readU64(apsb, 56)

            let omapAt128 = T.readU64(apsb, 128)
            let rootAt136 = T.readU64(apsb, 136)
            if omapAt128 > 0, rootAt136 > 0 {
                return (rootAt136, incompat)
            }

            let keyLen = Int(T.readU16(apsb, 114))
            let base = 116 + keyLen
            guard base + 16 <= apsb.count else { throw APFSError.truncated }
            return (T.readU64(apsb, base + 8), incompat)
        }

        private static func hasWrappedVolumeKey(_ apsb: Data) -> Bool {
            typealias T = DiffsplitterAPFSTypes
            guard apsb.count >= 116 else { return false }
            let keyLen = Int(T.readU16(apsb, 114))
            return keyLen > 0
        }

        private static func estimateBlockCount(
            disk: DiffsplitterUDIFDisk,
            partitionOffset: UInt64,
            blockSize: Int
        ) -> UInt64 {
            let remaining = disk.virtualSize > partitionOffset ? disk.virtualSize - partitionOffset : 0
            return remaining / UInt64(blockSize)
        }

        private static func buildOIDIndex(
            disk: DiffsplitterUDIFDisk,
            partitionOffset: UInt64,
            blockSize: Int,
            partitionBlocks: UInt64
        ) throws -> [UInt64: UInt64] {
            typealias T = DiffsplitterAPFSTypes
            var index: [UInt64: (paddr: UInt64, xid: UInt64)] = [:]
            let limit = min(partitionBlocks, 2_000_000)
            for p in 0..<limit {
                try Task.checkCancellation()
                let data = try readDisk(
                    disk,
                    offset: partitionOffset + p * UInt64(blockSize),
                    length: blockSize
                )
                guard let phys = T.parseObjPhys(data) else { continue }
                switch phys.typeCode {
                case T.objectTypeNxSuperblock, T.objectTypeBtree, T.objectTypeBtreeNode,
                     T.objectTypeOmap, T.objectTypeFs:
                    break
                default:
                    continue
                }
                guard phys.oid != 0 else { continue }
                if let existing = index[phys.oid] {
                    if phys.xid >= existing.xid {
                        index[phys.oid] = (p, phys.xid)
                    }
                } else {
                    index[phys.oid] = (p, phys.xid)
                }
            }
            return index.mapValues(\.paddr)
        }

        private static func findFsTreeRoot(
            oidIndex: [UInt64: UInt64],
            readBlock: (UInt64) throws -> Data
        ) -> UInt64? {
            typealias T = DiffsplitterAPFSTypes
            var best: (paddr: UInt64, keys: UInt64)?
            for (_, paddr) in oidIndex {
                guard let data = try? readBlock(paddr),
                      let phys = T.parseObjPhys(data),
                      phys.typeCode == T.objectTypeBtree,
                      phys.subtype == T.objectTypeFstree
                else { continue }
                let flags = T.readU16(data, 32)
                guard (flags & T.btnodeRoot) != 0 else { continue }

                let keyCount = T.readU64(data, data.count - T.btreeInfoSize + 24)
                if best == nil || keyCount > best!.keys {
                    best = (paddr, keyCount)
                }
            }
            return best?.paddr
        }
    }
}

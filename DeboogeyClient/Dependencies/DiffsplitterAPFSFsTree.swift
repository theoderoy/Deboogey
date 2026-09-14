//
//  DiffsplitterAPFSFsTree.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation

nonisolated enum DiffsplitterAPFSFsTree {
    struct DirRec {
        let parent: UInt64
        let name: String
        let fileID: UInt64
        let flags: UInt16

        var isDirectory: Bool {
            (flags & DiffsplitterAPFSTypes.drecTypeMask) == DiffsplitterAPFSTypes.drecTypeDir
        }
    }

    struct Catalog {
        var dirRecs: [DirRec] = []
        var inodes: [UInt64: Data] = [:]

        var extents: [UInt64: [(UInt64, UInt64, UInt64)]] = [:]

        var xattrs: [UInt64: [String: Data]] = [:]
    }

    static func loadCatalog(
        rootPaddr: UInt64,
        blockSize: Int,
        resolveOID: (UInt64) -> UInt64?,
        readBlock: (UInt64) throws -> Data
    ) throws -> Catalog {
        typealias T = DiffsplitterAPFSTypes
        var catalog = Catalog()
        var stack: [UInt64] = [rootPaddr]
        var seen = Set<UInt64>()

        while let paddr = stack.popLast() {
            try Task.checkCancellation()
            if seen.contains(paddr) { continue }
            seen.insert(paddr)
            let data = try readBlock(paddr)
            guard let phys = T.parseObjPhys(data),
                  phys.typeCode == T.objectTypeBtree || phys.typeCode == T.objectTypeBtreeNode
            else { continue }
            let node = try DiffsplitterAPFSBTree.parseNode(data, blockSize: blockSize)
            for entry in node.entries {
                if node.level > 0 {
                    guard entry.value.count >= 8 else { continue }
                    let childOID = T.readU64(entry.value, 0)
                    if let childP = resolveOID(childOID) {
                        stack.append(childP)
                    }
                    continue
                }
                guard entry.key.count >= 8 else { continue }
                let (oid, jType) = T.splitJKey(T.readU64(entry.key, 0))
                switch jType {
                case T.jTypeDirRec:
                    if let rec = parseDirRec(parent: oid, key: entry.key, value: entry.value) {
                        catalog.dirRecs.append(rec)
                    }
                case T.jTypeInode:
                    catalog.inodes[oid] = entry.value
                case T.jTypeFileExtent:
                    let logical = entry.key.count >= 16 ? T.readU64(entry.key, 8) : 0
                    guard entry.value.count >= 16 else { continue }
                    let lenFlags = T.readU64(entry.value, 0)
                    let length = lenFlags & ((1 << 56) - 1)
                    let physBlock = T.readU64(entry.value, 8)
                    catalog.extents[oid, default: []].append((logical, length, physBlock))
                case T.jTypeXattr:
                    if let (name, _) = parseXattrKey(entry.key) {
                        catalog.xattrs[oid, default: [:]][name] = entry.value
                    }
                default:
                    break
                }
            }
        }

        for key in catalog.extents.keys {
            catalog.extents[key]?.sort { $0.0 < $1.0 }
        }
        return catalog
    }

    private static func parseDirRec(parent: UInt64, key: Data, value: Data) -> DirRec? {
        typealias T = DiffsplitterAPFSTypes

        guard key.count >= 12, value.count >= 8 else { return nil }
        let hashLen = T.readU32(key, 8)
        let nameLen = Int(hashLen & 0x3FF)
        guard nameLen > 0, 12 + nameLen <= key.count else { return nil }
        var nameData = key.subdata(in: 12..<(12 + nameLen))
        if nameData.last == 0 {
            nameData = nameData.dropLast()
        }
        guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else { return nil }
        let fileID = T.readU64(value, 0)
        let flags = value.count >= 18 ? T.readU16(value, 16) : 0
        return DirRec(parent: parent, name: name, fileID: fileID, flags: flags)
    }

    private static func parseXattrKey(_ key: Data) -> (String, Int)? {
        typealias T = DiffsplitterAPFSTypes
        guard key.count >= 10 else { return nil }
        let nameLen = Int(T.readU16(key, 8))
        guard nameLen > 0, 10 + nameLen <= key.count else { return nil }
        var nameData = key.subdata(in: 10..<(10 + nameLen))
        if nameData.last == 0 {
            nameData = nameData.dropLast()
        }
        guard let name = String(data: nameData, encoding: .utf8) else { return nil }
        return (name, nameLen)
    }

    static func listFilePaths(catalog: Catalog, maxEntries: Int) throws -> [(path: String, inode: UInt64, size: UInt64)] {
        typealias T = DiffsplitterAPFSTypes
        var children: [UInt64: [DirRec]] = [:]
        for rec in catalog.dirRecs {
            children[rec.parent, default: []].append(rec)
        }

        var results: [(String, UInt64, UInt64)] = []
        var queue: [(UInt64, String)] = [(T.rootInode, "")]
        var head = 0
        var visited = Set<UInt64>()

        while head < queue.count {
            let (ino, prefix) = queue[head]
            head += 1
            try Task.checkCancellation()
            if visited.contains(ino) { continue }
            visited.insert(ino)
            for rec in children[ino] ?? [] {
                let path = prefix.isEmpty ? rec.name : "\(prefix)/\(rec.name)"
                if rec.isDirectory {
                    queue.append((rec.fileID, path))
                } else {
                    let size = logicalSize(inode: rec.fileID, catalog: catalog)
                    results.append((path, rec.fileID, size))
                    if results.count >= maxEntries { return results }
                }
            }
        }
        return results
    }

    static func logicalSize(inode: UInt64, catalog: Catalog) -> UInt64 {
        typealias T = DiffsplitterAPFSTypes
        guard let val = catalog.inodes[inode] else { return 0 }
        if let decmpfs = catalog.xattrs[inode]?["com.apple.decmpfs"],
           let header = parseDecmpfsHeader(decmpfs) {
            return header.uncompressedSize
        }
        if let dstream = parseDstream(fromInode: val) {
            return dstream.size
        }
        if val.count >= T.jInodeValSize {
            return T.readU64(val, 84)
        }
        return 0
    }

    struct Dstream {
        let size: UInt64
        let allocedSize: UInt64
    }

    static func parseDstream(fromInode val: Data) -> Dstream? {
        typealias T = DiffsplitterAPFSTypes
        guard val.count > T.jInodeValSize else { return nil }
        let fields = parseXFields(val)
        guard let raw = fields[T.inoExtTypeDstream], raw.count >= 16 else { return nil }
        return Dstream(size: T.readU64(raw, 0), allocedSize: T.readU64(raw, 8))
    }

    static func privateID(fromInode val: Data) -> UInt64 {
        guard val.count >= 16 else { return 0 }
        return DiffsplitterAPFSTypes.readU64(val, 8)
    }

    static func parseXFields(_ inodeVal: Data) -> [UInt8: Data] {
        typealias T = DiffsplitterAPFSTypes
        guard inodeVal.count >= T.jInodeValSize + 4 else { return [:] }
        let count = Int(T.readU16(inodeVal, T.jInodeValSize))
        var offset = T.jInodeValSize + 4
        var headers: [(UInt8, UInt16)] = []
        for _ in 0..<count {
            guard offset + 4 <= inodeVal.count else { break }
            let type = inodeVal[offset]
            let size = T.readU16(inodeVal, offset + 2)
            headers.append((type, size))
            offset += 4
        }
        while offset % 8 != 0 { offset += 1 }
        var fields: [UInt8: Data] = [:]
        for (type, size) in headers {
            let len = Int(size)
            guard offset + len <= inodeVal.count else { break }
            fields[type] = inodeVal.subdata(in: offset..<(offset + len))
            offset += len
            while offset % 8 != 0 { offset += 1 }
        }
        return fields
    }

    struct DecmpfsHeader {
        let compressionType: UInt32
        let uncompressedSize: UInt64
        let payload: Data
    }

    static func parseDecmpfsHeader(_ xattrVal: Data) -> DecmpfsHeader? {
        typealias T = DiffsplitterAPFSTypes
        guard xattrVal.count >= 4 else { return nil }
        let flags = T.readU16(xattrVal, 0)
        let xlen = Int(T.readU16(xattrVal, 2))
        let body: Data
        if flags == T.xattrDataEmbedded {
            guard 4 + xlen <= xattrVal.count else { return nil }
            body = xattrVal.subdata(in: 4..<(4 + xlen))
        } else {
            body = xattrVal.count > 4 ? xattrVal.subdata(in: 4..<xattrVal.count) : Data()
        }
        guard body.count >= 16,
              body.starts(with: T.decmpfsMagic)
        else { return nil }
        let compressionType = T.readU32(body, 4)
        let uncompressedSize = T.readU64(body, 8)
        let payload = body.count > 16 ? body.subdata(in: 16..<body.count) : Data()
        return DecmpfsHeader(
            compressionType: compressionType,
            uncompressedSize: uncompressedSize,
            payload: payload
        )
    }

    static func resourceForkStreamID(_ xattrVal: Data) -> (streamID: UInt64, size: UInt64)? {
        typealias T = DiffsplitterAPFSTypes
        guard xattrVal.count >= 4 else { return nil }
        let flags = T.readU16(xattrVal, 0)
        let xlen = Int(T.readU16(xattrVal, 2))
        guard flags == T.xattrDataStream, 4 + xlen <= xattrVal.count, xlen >= 16 else { return nil }
        let payload = xattrVal.subdata(in: 4..<(4 + xlen))
        return (T.readU64(payload, 0), T.readU64(payload, 8))
    }
}

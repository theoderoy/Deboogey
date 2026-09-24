//
//  DiffsplitterAPFSBTree.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation

nonisolated enum DiffsplitterAPFSBTree {
    struct Entry {
        let key: Data
        let value: Data
    }

    struct Node {
        let flags: UInt16
        let level: UInt16
        let entries: [Entry]

        var isRoot: Bool { (flags & DiffsplitterAPFSTypes.btnodeRoot) != 0 }
        var isLeaf: Bool { level == 0 }
        var isFixed: Bool { (flags & DiffsplitterAPFSTypes.btnodeFixed) != 0 }
    }

    static func parseNode(_ data: Data, blockSize: Int) throws -> Node {
        typealias T = DiffsplitterAPFSTypes
        guard data.count >= T.btnHeaderSize else {
            throw DiffsplitterAPFS.APFSError.truncated
        }
        guard let phys = T.parseObjPhys(data),
              phys.typeCode == T.objectTypeBtree || phys.typeCode == T.objectTypeBtreeNode
        else {
            throw DiffsplitterAPFS.APFSError.truncated
        }

        let flags = T.readU16(data, 32)
        let level = T.readU16(data, 34)
        let nkeys = Int(T.readU32(data, 36))
        let tableOff = Int(T.readU16(data, 40))
        let tableLen = Int(T.readU16(data, 42))
        let isRoot = (flags & T.btnodeRoot) != 0
        let isFixed = (flags & T.btnodeFixed) != 0

        let nodeSize = isRoot ? (blockSize - T.btreeInfoSize) : blockSize
        guard nodeSize > T.btnHeaderSize, data.count >= blockSize || data.count >= nodeSize else {
            throw DiffsplitterAPFS.APFSError.truncated
        }

        let dataBase = 56
        let toc = dataBase + tableOff
        let keyBase = tableOff + tableLen

        var keySize = 0
        var valSize = 0
        if isFixed {
            if isRoot, blockSize >= T.btreeInfoSize {
                let infoOff = blockSize - T.btreeInfoSize
                keySize = Int(T.readU32(data, infoOff + 8))
                valSize = Int(T.readU32(data, infoOff + 12))
            }
            if keySize == 0 { keySize = 16 }
            if valSize == 0 { valSize = 16 }
        }

        var entries: [Entry] = []
        entries.reserveCapacity(nkeys)

        for i in 0..<nkeys {
            if isFixed {
                let loc = toc + i * 4
                guard loc + 4 <= data.count else { break }
                let kOff = Int(T.readU16(data, loc))
                let vOff = Int(T.readU16(data, loc + 2))
                let keyPos = dataBase + keyBase + kOff
                let valueLen = level > 0 ? 8 : valSize
                let valuePos = nodeSize - vOff
                guard keyPos >= 0, keyPos + keySize <= data.count,
                      valuePos >= 0, valuePos + valueLen <= data.count
                else { continue }
                let key = data.subdata(in: keyPos..<(keyPos + keySize))
                let value = data.subdata(in: valuePos..<(valuePos + valueLen))
                entries.append(Entry(key: key, value: value))
            } else {
                let loc = toc + i * 8
                guard loc + 8 <= data.count else { break }
                let kOff = Int(T.readU16(data, loc))
                let kLen = Int(T.readU16(data, loc + 2))
                let vOff = Int(T.readU16(data, loc + 4))
                let vLen = Int(T.readU16(data, loc + 6))
                let keyPos = dataBase + keyBase + kOff
                let valuePos = nodeSize - vOff
                guard kLen >= 0, vLen >= 0,
                      keyPos >= 0, keyPos + kLen <= data.count,
                      valuePos >= 0, valuePos + vLen <= data.count
                else { continue }
                let key = data.subdata(in: keyPos..<(keyPos + kLen))
                let value = data.subdata(in: valuePos..<(valuePos + vLen))
                entries.append(Entry(key: key, value: value))
            }
        }

        return Node(flags: flags, level: level, entries: entries)
    }
}

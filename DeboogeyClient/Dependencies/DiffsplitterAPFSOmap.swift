//
//  DiffsplitterAPFSOmap.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation

nonisolated enum DiffsplitterAPFSOMap {
    struct Entry {
        let oid: UInt64
        let xid: UInt64
        let flags: UInt32
        let size: UInt32
        let paddr: UInt64
    }

    static func walk(
        rootPaddr: UInt64,
        blockSize: Int,
        readBlock: (UInt64) throws -> Data
    ) throws -> [Entry] {
        typealias T = DiffsplitterAPFSTypes
        var stack: [UInt64] = [rootPaddr]
        var seen = Set<UInt64>()
        var leaves: [Entry] = []

        while let paddr = stack.popLast() {
            try Task.checkCancellation()
            if seen.contains(paddr) { continue }
            seen.insert(paddr)
            let data = try readBlock(paddr)
            let node = try DiffsplitterAPFSBTree.parseNode(data, blockSize: blockSize)
            for entry in node.entries {
                guard entry.key.count >= 16 else { continue }
                let oid = T.readU64(entry.key, 0)
                let xid = T.readU64(entry.key, 8)
                if node.level > 0 {
                    guard entry.value.count >= 8 else { continue }
                    stack.append(T.readU64(entry.value, 0))
                } else {
                    guard entry.value.count >= 16 else { continue }
                    leaves.append(
                        Entry(
                            oid: oid,
                            xid: xid,
                            flags: T.readU32(entry.value, 0),
                            size: T.readU32(entry.value, 4),
                            paddr: T.readU64(entry.value, 8)
                        )
                    )
                }
            }
        }
        return leaves
    }

    static func resolve(
        oid: UInt64,
        entries: [Entry],
        maxXid: UInt64
    ) -> Entry? {
        let candidates = entries.filter { $0.oid == oid && (maxXid == 0 || $0.xid <= maxXid) }
        return candidates.max(by: { $0.xid < $1.xid })
    }

    static func latestByOID(_ entries: [Entry]) -> [UInt64: Entry] {
        var map: [UInt64: Entry] = [:]
        for entry in entries {
            if let existing = map[entry.oid] {
                if entry.xid >= existing.xid {
                    map[entry.oid] = entry
                }
            } else {
                map[entry.oid] = entry
            }
        }
        return map
    }
}

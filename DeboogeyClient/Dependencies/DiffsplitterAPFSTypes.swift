//
//  DiffsplitterAPFSTypes.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation

nonisolated enum DiffsplitterAPFSTypes {
    static let nxMagic: UInt32 = 0x4253_584E
    static let apfsMagic: UInt32 = 0x4253_5041

    static let objTypeMask: UInt32 = 0x0000_FFFF
    static let objTypeFlagsMask: UInt32 = 0xFFFF_0000
    static let objPhysical: UInt32 = 0x4000_0000

    static let objectTypeNxSuperblock: UInt32 = 0x1
    static let objectTypeBtree: UInt32 = 0x2
    static let objectTypeBtreeNode: UInt32 = 0x3
    static let objectTypeOmap: UInt32 = 0xB
    static let objectTypeFs: UInt32 = 0xD

    static let objectTypeFstree: UInt32 = 0xE
    static let objectTypeBlockrefTree: UInt32 = 0xF

    static let btnodeRoot: UInt16 = 0x1
    static let btnodeLeaf: UInt16 = 0x2
    static let btnodeFixed: UInt16 = 0x4

    static let btreeInfoSize = 40
    static let objPhysSize = 32
    static let btnHeaderSize = 56

    static let jTypeInode: UInt8 = 3
    static let jTypeXattr: UInt8 = 4
    static let jTypeFileExtent: UInt8 = 8
    static let jTypeDirRec: UInt8 = 9

    static let drecTypeMask: UInt16 = 0x000F
    static let drecTypeDir: UInt16 = 4

    static let inoExtTypeName: UInt8 = 4
    static let inoExtTypeDstream: UInt8 = 8

    static let xattrDataStream: UInt16 = 1
    static let xattrDataEmbedded: UInt16 = 2

    static let rootInode: UInt64 = 2

    static let apfsIncompatCaseInsensitive: UInt64 = 0x1
    static let apfsIncompatSealedVolume: UInt64 = 0x20
    static let apfsIncompatEncrypted: UInt64 = 0x2

    static let decmpfsMagic = Data("fpmc".utf8)
    static let decmpfsUncompressedMarker: UInt8 = 0xCC

    static let decmpfsTypeInlineUncompressed: UInt32 = 9
    static let decmpfsTypeLZBITMAPResource: UInt32 = 14

    static let decmpfsChunkUncompressed = 65_536

    static let jInodeValSize = 92

    struct ObjPhys {
        let oid: UInt64
        let xid: UInt64
        let type: UInt32
        let subtype: UInt32

        var typeCode: UInt32 { type & objTypeMask }
        var isPhysical: Bool { (type & objPhysical) != 0 }
    }

    static func parseObjPhys(_ data: Data, offset: Int = 0) -> ObjPhys? {
        guard offset + objPhysSize <= data.count else { return nil }
        return ObjPhys(
            oid: readU64(data, offset + 8),
            xid: readU64(data, offset + 16),
            type: readU32(data, offset + 24),
            subtype: readU32(data, offset + 28)
        )
    }

    static func splitJKey(_ value: UInt64) -> (oid: UInt64, type: UInt8) {
        (value & ((1 << 60) - 1), UInt8(value >> 60))
    }

    static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        DiffsplitterBinaryIO.readUInt16LE(data, offset)
    }

    static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        DiffsplitterBinaryIO.readUInt32LE(data, offset)
    }

    static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        DiffsplitterBinaryIO.readUInt64LE(data, offset)
    }
}

//
//  DiffsplitterXAR.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation
import Compression

nonisolated enum DiffsplitterXAR {
    struct Entry: Sendable, Equatable {
        let name: String
        let type: EntryType
        let dataOffset: UInt64?
        let compressedLength: UInt64?
        let uncompressedSize: UInt64?
        let encoding: Encoding
        let mode: UInt16?
    }

    enum EntryType: String, Sendable {
        case file
        case directory
        case other
    }

    enum Encoding: Sendable, Equatable {
        case store
        case gzip
        case bzip2
        case lzma
        case xz
        case unknown(String)
    }

    enum XARError: LocalizedError {
        case truncated
        case invalidMagic
        case unsupportedVersion(UInt16)
        case tocInflateFailed
        case tocParseFailed
        case memberNotFound
        case unsupportedEncoding(String)
        case extractFailed(String)

        var errorDescription: String? {
            switch self {
            case .truncated:
                return L10n.t("The XAR archive is truncated or unreadable.")
            case .invalidMagic:
                return L10n.t("The file is not a valid XAR archive.")
            case .unsupportedVersion(let v):
                return L10n.f("Unsupported XAR version: %d", Int(v))
            case .tocInflateFailed:
                return L10n.t("Could not decompress the XAR table of contents.")
            case .tocParseFailed:
                return L10n.t("Could not parse the XAR table of contents.")
            case .memberNotFound:
                return L10n.t("The requested XAR member was not found.")
            case .unsupportedEncoding(let name):
                return L10n.f("Unsupported XAR compression: %@", name)
            case .extractFailed(let detail):
                return L10n.f("Could not extract from the XAR archive: %@", detail)
            }
        }
    }

    private static let magic = Data("xar!".utf8)

    static func looksLike(_ data: Data) -> Bool {
        data.count >= 4 && data.starts(with: magic)
    }

    static func looksLikeFile(at url: URL) -> Bool {
        DiffsplitterBinaryIO.fileMatchesMagic(at: url, magic: magic)
    }

    static func listEntries(archive: URL) throws -> [Entry] {
        let toc = try loadTOC(archive: archive)
        return toc.entries
    }

    static func expand(archive: URL, into destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let toc = try loadTOC(archive: archive)
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        let heapBase = toc.heapOffset
        for entry in toc.entries {
            try Task.checkCancellation()
            let outURL = destination.appendingPathComponent(entry.name)
            switch entry.type {
            case .directory:
                try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
            case .file:
                try FileManager.default.createDirectory(
                    at: outURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard let offset = entry.dataOffset,
                      let compressed = entry.compressedLength,
                      let uncompressed = entry.uncompressedSize else {
                    FileManager.default.createFile(atPath: outURL.path, contents: Data())
                    continue
                }
                try extractMember(
                    handle: handle,
                    heapBase: heapBase,
                    offset: offset,
                    compressedLength: compressed,
                    uncompressedSize: uncompressed,
                    encoding: entry.encoding,
                    to: outURL
                )
            case .other:
                continue
            }
        }
    }

    static func extractMember(
        archive: URL,
        memberPath: String,
        to destination: URL
    ) throws {
        let toc = try loadTOC(archive: archive)
        guard let entry = toc.entries.first(where: { $0.name == memberPath && $0.type == .file }) else {
            throw XARError.memberNotFound
        }
        guard let offset = entry.dataOffset,
              let compressed = entry.compressedLength,
              let uncompressed = entry.uncompressedSize else {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: destination.path, contents: Data())
            return
        }
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try extractMember(
            handle: handle,
            heapBase: toc.heapOffset,
            offset: offset,
            compressedLength: compressed,
            uncompressedSize: uncompressed,
            encoding: entry.encoding,
            to: destination
        )
    }

    private struct TOC {
        let heapOffset: UInt64
        let entries: [Entry]
    }

    private static func loadTOC(archive: URL) throws -> TOC {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        guard let headerBytes = try handle.read(upToCount: 28), headerBytes.count == 28 else {
            throw XARError.truncated
        }
        guard headerBytes.starts(with: magic) else { throw XARError.invalidMagic }
        let headerSize = DiffsplitterBinaryIO.readUInt16BE(headerBytes, 4)
        let version = DiffsplitterBinaryIO.readUInt16BE(headerBytes, 6)
        guard version == 1 else { throw XARError.unsupportedVersion(version) }
        let tocCompressed = DiffsplitterBinaryIO.readUInt64BE(headerBytes, 8)
        let tocUncompressed = DiffsplitterBinaryIO.readUInt64BE(headerBytes, 16)
        guard tocCompressed > 0, tocUncompressed > 0, tocUncompressed < 64 * 1024 * 1024 else {
            throw XARError.truncated
        }
        let heapOffset = UInt64(headerSize) + tocCompressed
        try handle.seek(toOffset: UInt64(headerSize))
        guard let compressedTOC = try handle.read(upToCount: Int(tocCompressed)),
              compressedTOC.count == Int(tocCompressed) else {
            throw XARError.truncated
        }
        let tocData = try inflateZlib(compressedTOC, expectedSize: Int(tocUncompressed))
        guard let tocXML = String(data: tocData, encoding: .utf8)
                ?? String(data: tocData, encoding: .isoLatin1) else {
            throw XARError.tocParseFailed
        }
        let entries = try parseTOCXML(tocXML)
        return TOC(heapOffset: heapOffset, entries: entries)
    }

    private static func parseTOCXML(_ xml: String) throws -> [Entry] {
        guard let data = xml.data(using: .utf8) else { throw XARError.tocParseFailed }
        let parser = TOCParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { throw XARError.tocParseFailed }
        return parser.entries
    }

    private final class TOCParser: NSObject, XMLParserDelegate {
        private struct Frame {
            var nameComponents: [String]
            var explicitName: String?
            var type: EntryType
            var dataOffset: UInt64?
            var compressedLength: UInt64?
            var uncompressedSize: UInt64?
            var encoding: Encoding
            var mode: UInt16?
            var inData: Bool
            var currentText: String
        }

        private var stack: [Frame] = []
        private var pathStack: [String] = []
        private(set) var entries: [Entry] = []
        private var currentElement = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            currentElement = elementName
            if elementName == "file" {
                let attrName = attributeDict["name"]
                stack.append(
                    Frame(
                        nameComponents: pathStack,
                        explicitName: attrName,
                        type: .file,
                        dataOffset: nil,
                        compressedLength: nil,
                        uncompressedSize: nil,
                        encoding: .store,
                        mode: nil,
                        inData: false,
                        currentText: ""
                    )
                )

                pathStack.append(attrName ?? "")
            } else if elementName == "data", !stack.isEmpty {
                stack[stack.count - 1].inData = true
                if let style = attributeDict["style"] {
                    stack[stack.count - 1].encoding = encoding(from: style)
                }
            } else if elementName == "encoding", !stack.isEmpty, stack[stack.count - 1].inData {
                if let style = attributeDict["style"] {
                    stack[stack.count - 1].encoding = encoding(from: style)
                }
                stack[stack.count - 1].currentText = ""
            } else if !stack.isEmpty {
                stack[stack.count - 1].currentText = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard !stack.isEmpty else { return }
            let text = stack[stack.count - 1].currentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            defer {
                if !stack.isEmpty {
                    stack[stack.count - 1].currentText = ""
                }
            }
            switch elementName {
            case "name":
                if !text.isEmpty {
                    stack[stack.count - 1].explicitName = text
                    if !pathStack.isEmpty {
                        pathStack[pathStack.count - 1] = text
                    }
                }
            case "type":
                switch text {
                case "directory":
                    stack[stack.count - 1].type = .directory
                case "file":
                    stack[stack.count - 1].type = .file
                default:
                    stack[stack.count - 1].type = .other
                }
            case "offset" where stack[stack.count - 1].inData:
                stack[stack.count - 1].dataOffset = UInt64(text)
            case "length" where stack[stack.count - 1].inData:
                stack[stack.count - 1].compressedLength = UInt64(text)
            case "size" where stack[stack.count - 1].inData:
                stack[stack.count - 1].uncompressedSize = UInt64(text)
            case "encoding" where stack[stack.count - 1].inData:
                if !text.isEmpty {
                    stack[stack.count - 1].encoding = encoding(from: text)
                }
            case "mode":
                if text.hasPrefix("0"), let value = UInt16(text, radix: 8) {
                    stack[stack.count - 1].mode = value
                } else if let value = UInt16(text) {
                    stack[stack.count - 1].mode = value
                }
            case "data":
                stack[stack.count - 1].inData = false
            case "file":
                let frame = stack.removeLast()
                let leaf = frame.explicitName ?? pathStack.last ?? ""
                var components = frame.nameComponents
                if components.isEmpty || components.last?.isEmpty == true {
                    if !components.isEmpty { components.removeLast() }
                    if !leaf.isEmpty { components.append(leaf) }
                } else if let last = pathStack.last, !last.isEmpty {
                    components = Array(pathStack.dropLast()) + [last]
                }
                let name = components.filter { !$0.isEmpty }.joined(separator: "/")
                if !name.isEmpty {
                    entries.append(
                        Entry(
                            name: name,
                            type: frame.type,
                            dataOffset: frame.dataOffset,
                            compressedLength: frame.compressedLength,
                            uncompressedSize: frame.uncompressedSize,
                            encoding: frame.encoding,
                            mode: frame.mode
                        )
                    )
                }
                if !pathStack.isEmpty {
                    pathStack.removeLast()
                }
            default:
                break
            }
        }

        private func encoding(from style: String) -> Encoding {
            let lower = style.lowercased()
            if lower.contains("gzip") || lower.contains("application/x-gzip") {
                return .gzip
            }
            if lower.contains("bzip2") {
                return .bzip2
            }
            if lower.contains("xz") {
                return .xz
            }
            if lower.contains("lzma") {
                return .lzma
            }
            if lower.contains("octet-stream") || lower.isEmpty {
                return .store
            }
            return .unknown(style)
        }
    }

    private static func extractMember(
        handle: FileHandle,
        heapBase: UInt64,
        offset: UInt64,
        compressedLength: UInt64,
        uncompressedSize: UInt64,
        encoding: Encoding,
        to destination: URL
    ) throws {
        try handle.seek(toOffset: heapBase + offset)
        guard compressedLength <= UInt64(Int.max),
              let compressed = try handle.read(upToCount: Int(compressedLength)),
              compressed.count == Int(compressedLength) else {
            throw XARError.truncated
        }
        let plain: Data
        switch encoding {
        case .store:
            plain = compressed
        case .gzip:
            plain = try inflateGzipOrZlib(compressed, expectedSize: Int(uncompressedSize))
        case .lzma, .xz:
            plain = try decompressLZMA(compressed, expectedSize: Int(uncompressedSize))
        case .bzip2:
            throw XARError.unsupportedEncoding("bzip2")
        case .unknown(let name):
            throw XARError.unsupportedEncoding(name)
        }
        try plain.write(to: destination, options: .atomic)
    }

    private static func inflateZlib(_ data: Data, expectedSize: Int) throws -> Data {
        try inflateBuffer(data, windowBits: 15, expectedSize: expectedSize)
    }

    private static func inflateGzipOrZlib(_ data: Data, expectedSize: Int) throws -> Data {
        if let out = try? inflateBuffer(data, windowBits: 15 + 32, expectedSize: expectedSize) {
            return out
        }
        return try inflateBuffer(data, windowBits: 15, expectedSize: expectedSize)
    }

    private static func inflateBuffer(_ data: Data, windowBits: Int32, expectedSize: Int) throws -> Data {
        do {
            return try DiffsplitterBinaryIO.inflateZlib(
                data,
                windowBits: windowBits,
                initialCapacity: max(expectedSize, 1),
                growBy: max(64 * 1024, expectedSize / 4)
            )
        } catch {
            throw XARError.tocInflateFailed
        }
    }

    private static func decompressLZMA(_ data: Data, expectedSize: Int) throws -> Data {
        let dstSize = max(expectedSize, data.count)
        var destination = Data(count: dstSize)
        let written: Int = try destination.withUnsafeMutableBytes { dst in
            try data.withUnsafeBytes { src in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else {
                    throw XARError.extractFailed("lzma buffer")
                }
                let n = compression_decode_buffer(
                    dstBase,
                    dst.count,
                    srcBase,
                    src.count,
                    nil,
                    COMPRESSION_LZMA
                )
                if n == 0 { throw XARError.extractFailed("lzma") }
                return n
            }
        }
        destination.count = written
        return destination
    }
}

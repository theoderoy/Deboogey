//
//  DeboogeyDocumentLifecycle.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 10/11/2026.
//

import Foundation

enum DeboogeyDocumentKind: String {
    case loum
    case dsplt
    case dspltx
    case dspltb

    static func resolve(for url: URL) -> DeboogeyDocumentKind? {
        if let fromExtension = fromExtension(url.pathExtension) {
            return fromExtension
        }
        return fromContents(of: url)
    }

    static func fromExtension(_ ext: String) -> DeboogeyDocumentKind? {
        switch ext.lowercased() {
        case "loum": return .loum
        case "dsplt": return .dsplt
        case "dspltx": return .dspltx
        case "dspltb": return .dspltb
        default: return nil
        }
    }

    static func fromContents(of url: URL) -> DeboogeyDocumentKind? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 64)) ?? Data()
        guard !prefix.isEmpty else { return nil }

        if prefix.starts(with: Array("AA01".utf8)) || prefix.starts(with: Array("YAA1".utf8)) {
            return .dspltb
        }

        guard let text = String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            text.first == "{"
        else {
            return nil
        }
        let sample: String
        if let more = try? Data(contentsOf: url, options: [.mappedIfSafe]),
           let full = String(data: more.prefix(4096), encoding: .utf8) {
            sample = full
        } else {
            sample = text
        }
        if sample.contains("\"rows\"") {
            return .dspltx
        }
        if sample.contains("\"sourceApplication\"") || sample.contains("\"draftedValues\"") {
            return .loum
        }
        if sample.contains("\"leftPath\"")
            || sample.contains("\"rightPath\"")
            || sample.contains("\"leftBookmark\"")
            || sample.contains("\"comparisonKind\"") {
            return .dsplt
        }
        return nil
    }

    var pathExtension: String { rawValue }
}

enum DeboogeyDurableStore {
    private static let folderName = "DocumentImports"

    static var rootURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support
            .appendingPathComponent("Deboogey", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func isStoreURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let root = rootURL.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    static func makeDestination(preferredFilename: String) throws -> URL {
        let directory = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(
            DeboogeyAppDocuments.sanitizedFilename(preferredFilename)
        )
    }

    static func persist(data: Data, preferredFilename: String) throws -> URL {
        let destination = try makeDestination(preferredFilename: preferredFilename)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func persistCopy(of url: URL) throws -> URL {
        let preferred = preferredFilename(for: url)
        let destination = try makeDestination(preferredFilename: preferred)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: url, to: destination)
        return destination
    }

    private static func preferredFilename(for url: URL) -> String {
        let name = url.lastPathComponent
        if !url.pathExtension.isEmpty {
            return name
        }
        if let kind = DeboogeyDocumentKind.fromContents(of: url) {
            return name.appending(".\(kind.pathExtension)")
        }
        return name
    }
}

enum DeboogeySecurityScopedBookmark {
    static func create(for url: URL, relativeTo documentURL: URL?) -> Data? {
#if os(macOS)
        let options: URL.BookmarkCreationOptions = [
            .withSecurityScope,
            .securityScopeAllowOnlyReadAccess
        ]
        return try? url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: documentURL
        )
#else
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
#endif
    }

    static func createPreferringRelative(for url: URL, relativeTo documentURL: URL?) -> Data? {
        if let documentURL, let data = create(for: url, relativeTo: documentURL) {
            return data
        }
        return create(for: url, relativeTo: nil)
    }

    static func resolve(_ data: Data, relativeTo documentURL: URL?) -> URL? {
        var stale = false
#if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
#else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
#endif
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: documentURL,
            bookmarkDataIsStale: &stale
        ), !stale else {
            return nil
        }
        return url
    }
}

enum DeboogeyDocumentLifecycle {
    static func prepareForOpening(_ url: URL) throws -> URL {
        let kind = DeboogeyDocumentKind.resolve(for: url)
#if os(iOS)
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        switch kind {
        case .dsplt:
            return try prepareLinkedDiffsplitterDocument(at: url)
        case .loum, .dspltx, .dspltb, .none:
            return try materializeSelfContained(url, kind: kind)
        }
#else
        if kind == .dspltb, !DeboogeyDurableStore.isStoreURL(url) {
            return try DeboogeySecurityScopedAccess.withAccess(to: url) { scoped in
                try DeboogeyDurableStore.persistCopy(of: scoped)
            }
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
#endif
    }

    static func persistForOpen(data: Data, preferredFilename: String) throws -> URL {
        try DeboogeyDurableStore.persist(data: data, preferredFilename: preferredFilename)
    }

    static func prepareSideItem(_ url: URL) throws -> URL {
#if os(iOS)
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url
        }
        if accessed || isTransientImportLocation(url) || !isInsideAppContainer(url) {
            return try DeboogeyDurableStore.persistCopy(of: url)
        }
        return url.standardizedFileURL
#else
        return url
#endif
    }

    static func durableCopy(of url: URL) throws -> URL {
        try DeboogeyDurableStore.persistCopy(of: url)
    }

    static func relativePathIfCoLocated(sideURL: URL, documentURL: URL) -> String? {
        let parent = documentURL.deletingLastPathComponent().standardizedFileURL
        let side = sideURL.standardizedFileURL
        let parentPath = parent.path
        let sidePath = side.path
        guard sidePath == parentPath || sidePath.hasPrefix(parentPath + "/") else {
            return nil
        }
        if sidePath == parentPath { return nil }
        let relative = String(sidePath.dropFirst(parentPath.count + 1))
        return relative.isEmpty ? nil : relative
    }

    static func resolveLinkedURL(
        path: String?,
        relativePath: String?,
        bookmark: Data?,
        relativeTo documentURL: URL
    ) -> URL? {
        if let bookmark, let url = DeboogeySecurityScopedBookmark.resolve(bookmark, relativeTo: documentURL) {
            return url
        }
        if let relativePath {
            let candidate = documentURL
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath)
            if isReadableItem(at: candidate) {
                return candidate.standardizedFileURL
            }
        }
        if let path {
            let absolute = URL(fileURLWithPath: path)
            if isReadableItem(at: absolute) {
                return absolute.standardizedFileURL
            }
            let basename = (path as NSString).lastPathComponent
            let sibling = documentURL
                .deletingLastPathComponent()
                .appendingPathComponent(basename)
            if isReadableItem(at: sibling) {
                return sibling.standardizedFileURL
            }
#if os(iOS)
            let documentsSibling = DeboogeyAppDocuments.rootURL.appendingPathComponent(basename)
            if isReadableItem(at: documentsSibling) {
                return documentsSibling.standardizedFileURL
            }
#endif
        }
        return nil
    }

#if os(iOS)
    private static func prepareLinkedDiffsplitterDocument(at url: URL) throws -> URL {
        let original = url.standardizedFileURL
        let document = try DiffsplitterDocument.read(from: original)
        let left = resolveLinkedURL(
            path: document.leftPath,
            relativePath: document.leftRelativePath,
            bookmark: document.leftBookmark,
            relativeTo: original
        )
        let right = resolveLinkedURL(
            path: document.rightPath,
            relativePath: document.rightRelativePath,
            bookmark: document.rightBookmark,
            relativeTo: original
        )

        let preparedLeft = try materializeSideIfNeeded(left)
        let preparedRight = try materializeSideIfNeeded(right)

        let rewritten = DiffsplitterDocument(
            leftPath: preparedLeft?.path ?? document.leftPath,
            rightPath: preparedRight?.path ?? document.rightPath,
            leftBookmark: bookmarkForSide(preparedLeft, fallback: left, relativeTo: original)
                ?? document.leftBookmark,
            rightBookmark: bookmarkForSide(preparedRight, fallback: right, relativeTo: original)
                ?? document.rightBookmark,
            leftRelativePath: nil,
            rightRelativePath: nil,
            comparisonKind: document.comparisonKind,
            ignoreWhitespace: document.ignoreWhitespace,
            selectedRelativePath: document.selectedRelativePath
        )
        return try DeboogeyDurableStore.persist(
            data: try rewritten.encoded(),
            preferredFilename: original.lastPathComponent
        )
    }

    private static func materializeSideIfNeeded(_ url: URL?) throws -> URL? {
        guard let url else { return nil }
        if isInsideAppContainer(url), !isTransientImportLocation(url) {
            return url.standardizedFileURL
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url.standardizedFileURL
        }
        return try DeboogeyDurableStore.persistCopy(of: url)
    }

    private static func bookmarkForSide(
        _ prepared: URL?,
        fallback: URL?,
        relativeTo documentURL: URL
    ) -> Data? {
        guard let url = prepared ?? fallback else { return nil }
        return DeboogeySecurityScopedBookmark.createPreferringRelative(
            for: url,
            relativeTo: documentURL
        )
    }

    private static func materializeSelfContained(
        _ url: URL,
        kind: DeboogeyDocumentKind?
    ) throws -> URL {
        if DeboogeyDurableStore.isStoreURL(url) {
            return url.standardizedFileURL
        }
        if isInsideAppContainer(url), !isTransientImportLocation(url) {
            if kind == .dspltb {
                return try DeboogeyDurableStore.persistCopy(of: url)
            }
            return url.standardizedFileURL
        }
        return try DeboogeyDurableStore.persistCopy(of: url)
    }
#endif

    private static func isReadableItem(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue || FileManager.default.isReadableFile(atPath: url.path)
        }
        return false
    }

    static func isInsideAppContainer(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/")
    }

    static func isTransientImportLocation(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/Inbox/")
            || path.contains("/tmp/")
            || path.contains("/Temp/")
            || path.contains("/TemporaryItems/")
    }
}

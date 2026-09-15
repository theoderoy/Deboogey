//
//  DeboogeyAppDocuments.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 15/09/2026.
//

import Foundation

enum DeboogeyAppDocuments {
    private static let maxFilenameUTF8ByteCount = 255
    private static let invalidFilenameCharacters = CharacterSet(charactersIn: "/:\\")
        .union(.newlines)
        .union(.controlCharacters)

    static var rootURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func sanitizedFilename(_ preferredFilename: String, fallback: String = "Untitled") -> String {
        let flattened = preferredFilename
            .components(separatedBy: invalidFilenameCharacters)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (flattened as NSString).pathExtension
        var stem = (flattened as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while stem.hasSuffix(".") {
            stem.removeLast()
        }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.isEmpty { stem = fallback }
        let reserved = ext.isEmpty ? 0 : ext.utf8.count + 1
        let truncated = truncateUTF8(stem, maxBytes: max(1, maxFilenameUTF8ByteCount - reserved))
        let finalStem = truncated.isEmpty ? fallback : truncated
        return ext.isEmpty ? finalStem : "\(finalStem).\(ext)"
    }

    static func uniqueURL(preferredFilename: String) -> URL {
        let directory = rootURL
        let preferred = sanitizedFilename(preferredFilename)
        let ext = (preferred as NSString).pathExtension
        let reserved = ext.isEmpty ? 0 : ext.utf8.count + 1
        let base = (preferred as NSString).deletingPathExtension
        let stem = base.isEmpty ? "Untitled" : base

        func url(forStem candidate: String) -> URL {
            ext.isEmpty
                ? directory.appendingPathComponent(candidate)
                : directory.appendingPathComponent(candidate).appendingPathExtension(ext)
        }

        var candidate = url(forStem: stem)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = " \(index)"
            let truncated = truncateUTF8(
                stem,
                maxBytes: max(1, maxFilenameUTF8ByteCount - reserved - suffix.utf8.count)
            )
            candidate = url(forStem: "\(truncated.isEmpty ? "Untitled" : truncated)\(suffix)")
            index += 1
        }
        return candidate
    }

    private static func truncateUTF8(_ string: String, maxBytes: Int) -> String {
        guard string.utf8.count > maxBytes else { return string }
        var end = string.endIndex
        while end > string.startIndex, string[..<end].utf8.count > maxBytes {
            end = string.index(before: end)
        }
        return String(string[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

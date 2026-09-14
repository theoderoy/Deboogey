//
//  DiffsplitterXIP.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation

nonisolated enum DiffsplitterXIP {
    enum XIPError: LocalizedError {
        case notXIP
        case missingContent
        case expandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notXIP:
                return L10n.t("The file is not a readable XIP archive.")
            case .missingContent:
                return L10n.t("The XIP archive has no Content payload.")
            case .expandFailed(let detail):
                return L10n.f("Could not expand the XIP archive: %@", detail)
            }
        }
    }

    static func expand(archive: URL, into destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let stage = destination.appendingPathComponent(".xip-stage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        do {
            try DiffsplitterXAR.expand(archive: archive, into: stage)
        } catch let error as DiffsplitterXAR.XARError {
            throw XIPError.expandFailed(error.localizedDescription)
        }

        let contentURL = findContent(in: stage)
        if let contentURL {
            try expandContent(contentURL, into: destination)

            let metadata = stage.appendingPathComponent("Metadata")
            if FileManager.default.fileExists(atPath: metadata.path) {
                let destMeta = destination.appendingPathComponent("Metadata")
                try? FileManager.default.removeItem(at: destMeta)
                try? FileManager.default.copyItem(at: metadata, to: destMeta)
            }
            return
        }

        try moveChildren(from: stage, to: destination)
    }

    private static func findContent(in root: URL) -> URL? {
        let candidates = [
            root.appendingPathComponent("Content"),
            root.appendingPathComponent("Content.gz")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "Content" || url.lastPathComponent == "Content.gz" {
                return url
            }
        }
        return nil
    }

    private static func expandContent(_ contentURL: URL, into destination: URL) throws {
        let data = try Data(contentsOf: contentURL, options: [.mappedIfSafe])
        do {
            if DiffsplitterPBZX.looksLike(data) {
                let decoded = try DiffsplitterPBZX.decode(data: data)
                if DiffsplitterCPIO.looksLike(decoded) {
                    try DiffsplitterCPIO.expand(data: decoded, into: destination)
                    return
                }
                let out = destination.appendingPathComponent("Content.payload")
                try decoded.write(to: out, options: .atomic)
                return
            }
            if DiffsplitterCPIO.looksLike(data) {
                try DiffsplitterCPIO.expand(data: data, into: destination)
                return
            }
            let out = destination.appendingPathComponent(contentURL.lastPathComponent)
            try data.write(to: out, options: .atomic)
        } catch let error as DiffsplitterPBZX.PBZXError {
            throw XIPError.expandFailed(error.localizedDescription)
        } catch let error as DiffsplitterCPIO.CPIOError {
            throw XIPError.expandFailed(error.localizedDescription)
        } catch let error as XIPError {
            throw error
        } catch {
            throw XIPError.expandFailed(error.localizedDescription)
        }
    }

    private static func moveChildren(from stage: URL, to destination: URL) throws {
        let children = try FileManager.default.contentsOfDirectory(
            at: stage,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for child in children {
            let dest = destination.appendingPathComponent(child.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: child, to: dest)
        }
    }
}

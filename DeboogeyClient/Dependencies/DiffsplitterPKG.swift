//
//  DiffsplitterPKG.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 14/09/2026.
//

import Foundation

nonisolated enum DiffsplitterPKG {
    enum PKGError: LocalizedError {
        case notPKG
        case expandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notPKG:
                return L10n.t("The file is not a readable PKG package.")
            case .expandFailed(let detail):
                return L10n.f("Could not expand the package: %@", detail)
            }
        }
    }

    static func expand(package: URL, into destination: URL) throws {
        do {
            if DiffsplitterXAR.looksLikeFile(at: package) {
                try DiffsplitterXAR.expand(archive: package, into: destination)
            } else {
                throw PKGError.notPKG
            }
        } catch let error as DiffsplitterXAR.XARError {
            throw PKGError.expandFailed(error.localizedDescription)
        } catch let error as PKGError {
            throw error
        } catch {
            throw PKGError.expandFailed(error.localizedDescription)
        }

        try maybeExpandPayloadArchives(in: destination)
    }

    private static func maybeExpandPayloadArchives(in root: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var payloadURLs: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "Payload" {
                payloadURLs.append(url)
            }
        }
        for payload in payloadURLs {
            try Task.checkCancellation()
            do {
                try expandPayloadIfNeeded(payload)
            } catch {
                continue
            }
        }
    }

    private static func expandPayloadIfNeeded(_ payload: URL) throws {
        let data = try Data(contentsOf: payload, options: [.mappedIfSafe])
        let outDir = payload.deletingLastPathComponent().appendingPathComponent("PayloadContents", isDirectory: true)
        if DiffsplitterPBZX.looksLike(data) {
            let decoded = try DiffsplitterPBZX.decode(data: data)
            if DiffsplitterCPIO.looksLike(decoded) {
                try DiffsplitterCPIO.expand(data: decoded, into: outDir)
            }
            return
        }
        if looksLikeGzip(data) {
            let inflated = try inflateGzip(data)
            if DiffsplitterCPIO.looksLike(inflated) {
                try DiffsplitterCPIO.expand(data: inflated, into: outDir)
            }
            return
        }
        if DiffsplitterCPIO.looksLike(data) {
            try DiffsplitterCPIO.expand(data: data, into: outDir)
        }
    }

    private static func looksLikeGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x1F && data[1] == 0x8B
    }

    private static func inflateGzip(_ data: Data) throws -> Data {
        do {
            return try DiffsplitterBinaryIO.inflateZlib(
                data,
                windowBits: 15 + 32,
                initialCapacity: max(data.count * 4, 64 * 1024),
                growBy: 256 * 1024
            )
        } catch {
            throw PKGError.expandFailed("gzip")
        }
    }
}

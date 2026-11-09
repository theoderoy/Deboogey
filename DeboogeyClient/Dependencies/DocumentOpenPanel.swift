//
//  DocumentOpenPanel.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

enum DocumentOpenPanel {
#if canImport(AppKit)
    static let deboogeyDocumentTypes: [UTType] = [
        .loupeMachineDocument,
        .diffsplitterDocument,
        .diffsplitterXDocument,
    ]

    static func choose(
        title: String,
        contentTypes: [UTType],
        open: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            open(url)
        }
    }

    static func chooseDeboogeyDocument(
        openLoupe: @escaping (URL) -> Void,
        openDiffsplitter: @escaping (URL) -> Void
    ) {
        choose(
            title: L10n.t("Open"),
            contentTypes: deboogeyDocumentTypes
        ) { url in
            route(url, openLoupe: openLoupe, openDiffsplitter: openDiffsplitter)
        }
    }

    static func route(
        _ url: URL,
        openLoupe: (URL) -> Void,
        openDiffsplitter: (URL) -> Void
    ) {
        switch url.pathExtension.lowercased() {
        case "loum":
            openLoupe(url)
        case "dsplt", "dspltx":
            openDiffsplitter(url)
        default:
            break
        }
    }
#endif
}

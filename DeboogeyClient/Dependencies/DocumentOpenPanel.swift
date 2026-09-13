//
//  DocumentOpenPanel.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import AppKit
import UniformTypeIdentifiers

enum DocumentOpenPanel {
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
}

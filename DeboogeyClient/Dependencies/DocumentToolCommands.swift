//
//  DocumentToolCommands.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import SwiftUI

struct DocumentToolCommandSet: Commands {
    let createLoupeDocument: () -> Void
    let openLoupeDocument: () -> Void
    let createDiffsplitterDocument: () -> Void
    let openDiffsplitterDocument: () -> Void
    let openMain: () -> Void
    @ObservedObject private var saveBridge = DocumentSaveDispatcherBridge.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.t("New Window"), action: openMain)
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Button(L10n.t("New Loupe Machine Document")) {
                createLoupeDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.t("Open Loupe Machine Document…")) {
                openLoupeDocument()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(L10n.t("New Diffsplitter Document")) {
                createDiffsplitterDocument()
            }

            Button(L10n.t("Open Diffsplitter Document…")) {
                openDiffsplitterDocument()
            }

            Divider()

            Button(L10n.t("Save")) { DocumentSaveDispatcher.save(saveAs: false) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!saveBridge.canSave)

            Button(L10n.t("Save As…")) { DocumentSaveDispatcher.save(saveAs: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!saveBridge.canSave)

            Button(L10n.t("Export DiffsplitterX Document…")) {
                DocumentSaveDispatcher.exportDiffsplitterX()
            }
            .disabled(!saveBridge.canExportDiffsplitterX)
        }
    }
}

struct ExternalDocumentHandler: ViewModifier {
    let openLoupe: (URL) -> Void
    let openDiffsplitter: (URL) -> Void

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            let ext = url.pathExtension.lowercased()
            if ext == "loum" {
                openLoupe(url)
            } else if ext == "dsplt" || ext == "dspltx" {
                openDiffsplitter(url)
            }
        }
    }
}

@available(macOS 13.0, *)
struct ExternalDocumentWindowHandler: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.modifier(ExternalDocumentHandler(
            openLoupe: { LoupeMachineNavigation.open(documentAt: $0, using: openWindow) },
            openDiffsplitter: { DiffsplitterNavigation.open(documentAt: $0, using: openWindow) }
        ))
    }
}

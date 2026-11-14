//
//  DocumentToolCommands.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import SwiftUI

#if os(macOS)
struct DocumentToolCommandSet: Commands {
    let createLoupeDocument: () -> Void
    let createDiffsplitterDocument: () -> Void
    let openDocument: () -> Void
    let openMain: () -> Void
    @ObservedObject private var saveBridge = DocumentSaveDispatcherBridge.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.t("New Window"), action: openMain)
                .keyboardShortcut("n", modifiers: .command)

            Button(L10n.t("New Loupe Machine Document"), action: createLoupeDocument)
                .keyboardShortcut("1", modifiers: .command)

            Button(L10n.t("New Diffsplitter Document"), action: createDiffsplitterDocument)
                .keyboardShortcut("2", modifiers: .command)

            Divider()

            Button(L10n.t("Open…"), action: openDocument)
                .keyboardShortcut("o", modifiers: .command)

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

            Button(L10n.t("Export Diffsplitter Batch…")) {
                DocumentSaveDispatcher.exportBatch()
            }
            .disabled(!saveBridge.canExportBatch)
        }
    }
}

struct LegacyDocumentToolCommands: Commands {
    let openMain: () -> Void

    var body: some Commands {
        DocumentToolCommandSet(
            createLoupeDocument: { LoupeMachineNavigation.openLegacy(documentAt: nil) },
            createDiffsplitterDocument: { DiffsplitterNavigation.openLegacy(documentAt: nil) },
            openDocument: {
                DocumentOpenPanel.chooseDeboogeyDocument(
                    openLoupe: { LegacyDocumentRoutes.openLoupe($0) },
                    openDiffsplitter: { LegacyDocumentRoutes.openDiffsplitter($0) }
                )
            },
            openMain: openMain
        )
    }
}

@MainActor
enum LegacyDocumentRoutes {
    static func openLoupe(_ url: URL) {
        LoupeMachineNavigation.openLegacy(documentAt: url)
    }

    static func openDiffsplitter(_ url: URL) {
        DiffsplitterNavigation.openLegacy(documentAt: url)
    }
}

@available(macOS 13.0, *)
@MainActor
enum DocumentWindowRoutes {
    static func openLoupe(_ url: URL, using openWindow: OpenWindowAction) {
        LoupeMachineNavigation.open(documentAt: url, using: openWindow)
    }

    static func openDiffsplitter(_ url: URL, using openWindow: OpenWindowAction) {
        DiffsplitterNavigation.open(documentAt: url, using: openWindow)
    }
}

struct ExternalDocumentHandler: ViewModifier {
    let openLoupe: (URL) -> Void
    let openDiffsplitter: (URL) -> Void

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            let prepared = (try? DeboogeyDocumentLifecycle.prepareForOpening(url)) ?? url
            DocumentOpenPanel.route(
                prepared,
                openLoupe: openLoupe,
                openDiffsplitter: openDiffsplitter
            )
        }
    }
}

@available(macOS 13.0, *)
struct ExternalDocumentWindowHandler: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.modifier(ExternalDocumentHandler(
            openLoupe: { DocumentWindowRoutes.openLoupe($0, using: openWindow) },
            openDiffsplitter: { DocumentWindowRoutes.openDiffsplitter($0, using: openWindow) }
        ))
    }
}
#endif

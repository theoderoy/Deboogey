//
//  LoupeMachineDocument.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 28/07/2026.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI
import AppKit

extension UTType {
    static let loupeMachineDocument = UTType(exportedAs: "theoderoy.Deboogey.LoupeMachine", conformingTo: .json)
}

struct LoupeMachineDocument: Codable {
    static let currentFormatVersion = 1

    struct Flag: Codable {
        let name: String
        let value: String
        let source: LoupeFlag.Source?
        let keyPath: [String]?
        let backingFilePath: String?
    }

    let formatVersion: Int
    let sourceApplication: String?
    let sourceApplicationBookmark: Data?
    let flags: [Flag]
    let draftedValues: [String: String]

    init(
        sourceApplication: String?,
        sourceApplicationBookmark: Data? = nil,
        flags: [LoupeFlag],
        draftedValues: [String: String]
    ) {
        formatVersion = Self.currentFormatVersion
        self.sourceApplication = sourceApplication
        self.sourceApplicationBookmark = sourceApplicationBookmark
        self.flags = flags.map {
            Flag(
                name: $0.name,
                value: $0.value,
                source: $0.source,
                keyPath: $0.keyPath,
                backingFilePath: $0.backingFilePath
            )
        }
        self.draftedValues = draftedValues
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func read(from url: URL) throws -> LoupeMachineDocument {
        let document = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard document.formatVersion == currentFormatVersion else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSDebugDescriptionErrorKey: "Unsupported Loupe Machine document version."
            ])
        }
        return document
    }
}

struct LoupeMachineWindowRequest: Codable, Hashable {
    enum Action: String, Codable, Hashable {
        case create
        case open
        case importApplication
    }

    let id: UUID
    let action: Action
    let documentURL: URL?

    init(action: Action, documentURL: URL? = nil) {
        id = UUID()
        self.action = action
        self.documentURL = documentURL
    }
}

@MainActor
enum LoupeMachineNavigation {
    static let windowID = "deboogey-loupe"

    static func openLegacy(documentAt url: URL?) {
        LoupeMachineWindowController.open(LoupeMachineWindowRequest(
            action: url == nil ? .create : .open,
            documentURL: url
        ))
    }

    static func importApplicationLegacy() {
        LoupeMachineWindowController.open(LoupeMachineWindowRequest(action: .importApplication))
    }

    static func chooseDocumentLegacy() {
        chooseDocument { url in openLegacy(documentAt: url) }
    }

    @available(macOS 13.0, *)
    static func open(documentAt url: URL?, using openWindow: OpenWindowAction) {
        let request = LoupeMachineWindowRequest(
            action: url == nil ? .create : .open,
            documentURL: url
        )
        openWindow(id: windowID, value: request)
    }

    @available(macOS 13.0, *)
    static func importApplication(using openWindow: OpenWindowAction) {
        openWindow(
            id: windowID,
            value: LoupeMachineWindowRequest(action: .importApplication)
        )
    }

    @available(macOS 13.0, *)
    static func chooseDocument(using openWindow: OpenWindowAction) {
        chooseDocument { url in open(documentAt: url, using: openWindow) }
    }

    private static func chooseDocument(open: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = L10n.t("Open Loupe Machine Document")
        panel.allowedContentTypes = [.loupeMachineDocument]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            open(url)
        }
    }
}

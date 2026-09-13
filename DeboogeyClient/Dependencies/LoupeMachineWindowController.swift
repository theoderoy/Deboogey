//
//  LoupeMachineWindowController.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 30/07/2026.
//

import AppKit
import SwiftUI

@MainActor
final class LoupeMachineWindowController: NSWindowController {
    private static var openWindows: [UUID: LoupeMachineWindowController] = [:]

    private let requestID: UUID
    private var closeObserver: NSObjectProtocol?

    private init(request: LoupeMachineWindowRequest) {
        requestID = request.id
        let window = ToolDocumentWindowHosting.makeWindow(
            title: L10n.t("Loupe Machine"),
            sizing: AppWindowSizing.loupeMachine,
            bridgeToolbars: false,
            rootView: LoupeMachineView(request: request)
        )
        super.init(window: window)
        closeObserver = ToolDocumentWindowHosting.observeClose(of: window) { [weak self] in
            self?.windowDidClose()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func open(_ request: LoupeMachineWindowRequest) {
        let controller = LoupeMachineWindowController(request: request)
        openWindows[request.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func windowDidClose() {
        Self.openWindows.removeValue(forKey: requestID)
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
    }
}

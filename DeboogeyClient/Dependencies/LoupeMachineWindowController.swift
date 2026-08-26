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

        let content = LoupeMachineView(request: request)
            .environment(\.locale, L10n.locale)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = L10n.t("Loupe Machine")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        let sizing = AppWindowSizing.loupeMachine
        window.setContentSize(sizing.defaultSize)
        window.minSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: sizing.minimumSize)
        ).size
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowDidClose()
            }
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

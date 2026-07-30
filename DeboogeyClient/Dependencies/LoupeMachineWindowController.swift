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

#if !DEBOOGEY_MCE
@MainActor
final class DeboogeyWindowController: NSWindowController, NSWindowDelegate {
    enum Kind: Hashable {
        case main
        case cocoaDebugMenu
        case skyLightDiagnostics
    }

    private static var openWindows: [Kind: DeboogeyWindowController] = [:]
    private let kind: Kind

    private init(kind: Kind, sipSatisfied: Bool) {
        self.kind = kind

        let window: NSWindow
        switch kind {
        case .main:
            let content = RootView()
                .environment(\.sipSatisfied, sipSatisfied)
                .environment(\.locale, L10n.locale)
            window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "Deboogey"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

        case .cocoaDebugMenu:
            let content = NavigationView {
                DeboogeyCDMLauncherView { arguments in
                    EntityTracker.shared.record(source: .deboogeyCDM, arguments: arguments)
                }
            }
            .environment(\.locale, L10n.locale)
            window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = L10n.t("Cocoa Debug Menu")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 650))

        case .skyLightDiagnostics:
            let content = NavigationView {
                DeboogeySDLauncherView { argument in
                    EntityTracker.shared.record(source: .wsOverlay, arguments: [argument])
                }
            }
            .environment(\.locale, L10n.locale)
            window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = L10n.t("SkyLight Diagnostics")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 540))
        }

        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func open(_ kind: Kind, sipSatisfied: Bool) {
        let controller = openWindows[kind] ?? DeboogeyWindowController(
            kind: kind,
            sipSatisfied: sipSatisfied
        )
        openWindows[kind] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openWindows.removeValue(forKey: kind)
    }
}
#endif

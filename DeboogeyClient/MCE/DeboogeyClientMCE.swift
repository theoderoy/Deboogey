//
//  DeboogeyClientMCE.swift
//  DeboogeyClientMCE
//
//  Created by Théo De Roy on 30/07/2026.
//


import AppKit
import SwiftUI

@MainActor
private final class MCEAboutWindowController: NSWindowController {
    static let shared = MCEAboutWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.title = L10n.t("About Deboogey")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MCEAboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.t("About Deboogey")) { MCEAboutWindowController.shared.show() }
        }
    }
}

private struct MCELegacyCommands: Commands {
    @ObservedObject private var router = LoupeMachineCommandRouter.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.t("New Loupe Machine Document")) {
                LoupeMachineNavigation.openLegacy(documentAt: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.t("Open Loupe Machine Document…")) {
                LoupeMachineNavigation.chooseDocumentLegacy()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button(L10n.t("Save")) { router.save(saveAs: false) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!router.canSave)
            Button(L10n.t("Save As…")) { router.save(saveAs: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!router.canSave)
        }
        CommandGroup(after: .windowArrangement) {
            Button(L10n.t("Loupe Machine")) {
                LoupeMachineNavigation.openLegacy(documentAt: nil)
            }
        }
    }
}

@available(macOS 13.0, *)
private struct MCELoupeCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var router = LoupeMachineCommandRouter.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.t("New Loupe Machine Document")) {
                LoupeMachineNavigation.open(documentAt: nil, using: openWindow)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.t("Open Loupe Machine Document…")) {
                LoupeMachineNavigation.chooseDocument(using: openWindow)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button(L10n.t("Save")) { router.save(saveAs: false) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!router.canSave)
            Button(L10n.t("Save As…")) { router.save(saveAs: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!router.canSave)
        }
        CommandGroup(after: .windowArrangement) {
            Button(L10n.t("Loupe Machine")) {
                LoupeMachineNavigation.open(documentAt: nil, using: openWindow)
            }
        }
    }
}

@available(macOS 13.0, *)
private struct MCELoupeScene: Scene {
    var body: some Scene {
        WindowGroup(
            L10n.t("Loupe Machine"),
            id: LoupeMachineNavigation.windowID,
            for: LoupeMachineWindowRequest.self
        ) { request in
            NavigationStack {
                if let request = request.wrappedValue {
                    LoupeMachineView(request: request)
                }
            }
            .environment(\.locale, L10n.locale)
        }
        .commands {
            MCELoupeCommands()
        }
        .defaultSize(
            width: AppWindowSizing.loupeMachine.defaultSize.width,
            height: AppWindowSizing.loupeMachine.defaultSize.height
        )
        .windowResizability(.contentMinSize)
    }
}

@available(macOS 13.0, *)
private struct MCEEntityTrackerScene: Scene {
    var body: some Scene {
        Window(L10n.t("Entity Tracker"), id: "entity-tracker") {
            NavigationStack {
                EntityTrackerView()
            }
            .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .defaultSize(width: 560, height: 480)
        .windowResizability(.contentSize)
    }
}

@available(macOS 14.0, *)
private struct MCEConfigurationModern: Scene {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(L10n.t("Settings"), id: "settings") {
            ConfigurationRootView()
                .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.t("Configuration"), systemImage: "gear") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .defaultSize(
            width: AppWindowSizing.Configuration.modern.defaultSize.width,
            height: AppWindowSizing.Configuration.modern.defaultSize.height
        )
        .windowResizability(.contentMinSize)
    }
}

@available(macOS 13.0, *)
private struct MCEExternalDocumentHandler: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.pathExtension.lowercased() == "loum" else { return }
            LoupeMachineNavigation.open(documentAt: url, using: openWindow)
        }
    }
}

private struct MCELegacyExternalDocumentHandler: ViewModifier {
    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.pathExtension.lowercased() == "loum" else { return }
            LoupeMachineNavigation.openLegacy(documentAt: url)
        }
    }
}

private struct MCERootContentView: View {
    @ViewBuilder
    var body: some View {
        if #available(macOS 13.0, *) {
            RootView().modifier(MCEExternalDocumentHandler())
        } else {
            RootView().modifier(MCELegacyExternalDocumentHandler())
        }
    }
}

@main
struct DeboogeyClientMCE: App {
    init() {
        PersistentVariables.registerDefaults()
        EntityTracker.shared.performConfiguredAutoRemoval()
    }

    var body: some Scene {
        WindowGroup {
            MCERootContentView()
                .environment(\.locale, L10n.locale)
        }
        .commands {
            MCEAboutCommands()
            MCELegacyCommands()
        }

        Settings {
            ConfigurationRootView()
                .environment(\.locale, L10n.locale)
        }

        if #available(macOS 14.0, *) {
            MCEConfigurationModern()
        }

        if #available(macOS 13.0, *) {
            MCELoupeScene()
            MCEEntityTrackerScene()
        }
    }
}

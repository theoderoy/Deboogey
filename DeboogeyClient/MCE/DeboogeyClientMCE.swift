//
//  DeboogeyClientMCE.swift
//  DeboogeyClientMCE
//
//  Created by Théo De Roy on 30/07/2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)

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

@MainActor
private final class MCEWindowController: NSWindowController, NSWindowDelegate {
    enum Kind: Hashable {
        case main
    }

    private static var openWindows: [Kind: MCEWindowController] = [:]
    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind

        let window: NSWindow
        switch kind {
        case .main:
            let content = RootView()
                .environment(\.locale, L10n.locale)
            window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "Deboogey"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        }

        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    static func open(_ kind: Kind) {
        let controller = openWindows[kind] ?? MCEWindowController(kind: kind)
        openWindows[kind] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openWindows.removeValue(forKey: kind)
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
    var body: some Commands {
        DocumentToolCommandSet(
            createLoupeDocument: { LoupeMachineNavigation.openLegacy(documentAt: nil) },
            openLoupeDocument: LoupeMachineNavigation.chooseDocumentLegacy,
            createDiffsplitterDocument: { DiffsplitterNavigation.openLegacy(documentAt: nil) },
            openDiffsplitterDocument: DiffsplitterNavigation.chooseDocumentLegacy,
            openMain: { MCEWindowController.open(.main) }
        )
    }
}

@available(macOS 13.0, *)
private struct MCELoupeCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        DocumentToolCommandSet(
            createLoupeDocument: { LoupeMachineNavigation.open(documentAt: nil, using: openWindow) },
            openLoupeDocument: { LoupeMachineNavigation.chooseDocument(using: openWindow) },
            createDiffsplitterDocument: { DiffsplitterNavigation.open(documentAt: nil, using: openWindow) },
            openDiffsplitterDocument: { DiffsplitterNavigation.chooseDocument(using: openWindow) },
            openMain: { MCEWindowController.open(.main) }
        )
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
private struct MCEDiffsplitterScene: Scene {
    var body: some Scene {
        WindowGroup(
            L10n.t("Diffsplitter"),
            id: DiffsplitterNavigation.windowID,
            for: DiffsplitterWindowRequest.self
        ) { request in
            Group {
                if let request = request.wrappedValue {
                    DiffsplitterView(request: request)
                }
            }
            .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .defaultSize(
            width: AppWindowSizing.diffsplitter.defaultSize.width,
            height: AppWindowSizing.diffsplitter.defaultSize.height
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
        .defaultSize(width: AppWindowSizing.entityTracker.defaultSize.width, height: AppWindowSizing.entityTracker.defaultSize.height)
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

private struct MCERootContentView: View {
    @ViewBuilder
    var body: some View {
        if #available(macOS 13.0, *) {
            RootView().modifier(ExternalDocumentWindowHandler())
        } else {
            RootView().modifier(ExternalDocumentHandler(
                openLoupe: { LoupeMachineNavigation.openLegacy(documentAt: $0) },
                openDiffsplitter: { DiffsplitterNavigation.openLegacy(documentAt: $0) }
            ))
        }
    }
}

private struct MCELegacyRootScene: Scene {
    var body: some Scene {
        WindowGroup {
            MCERootContentView()
                .environment(\.locale, L10n.locale)
        }
        .commands {
            MCEAboutCommands()
            MCELegacyCommands()
            LegacyWindowLauncherCommands(openMain: { MCEWindowController.open(.main) })
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
        MCELegacyRootScene()

        Settings {
            ConfigurationRootView()
                .environment(\.locale, L10n.locale)
        }

        if #available(macOS 14.0, *) {
            MCEConfigurationModern()
        }

        if #available(macOS 13.0, *) {
            MCELoupeScene()
            MCEDiffsplitterScene()
            MCEEntityTrackerScene()
        }
    }
}

#elseif os(iOS)

import Metal
import UIKit

enum MCEIOSFeatureSupport {
    enum DiffsplitterBlocker {
        case phone
        case chip
    }

    static var diffsplitter: Bool {
        diffsplitterBlocker == nil
    }

    static var diffsplitterBlocker: DiffsplitterBlocker? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return .phone }
        #if targetEnvironment(simulator)
        return nil
        #else
        guard let device = MTLCreateSystemDefaultDevice(),
              device.supportsFamily(.apple7) else { return .chip }
        return nil
        #endif
    }
}

enum MCEIOSRoute: Hashable {
    case loupe(LoupeMachineWindowRequest)
    case diffsplitter(DiffsplitterWindowRequest)
}

@main
struct DeboogeyClientMCE: App {
    @State private var path = NavigationPath()

    init() {
        PersistentVariables.registerDefaults()
        EntityTracker.shared.performConfiguredAutoRemoval()
        if MCEIOSFeatureSupport.diffsplitter {
            DiffsplitterContinuedProcessing.registerAtLaunch()
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                RootView()
                    .navigationDestination(for: MCEIOSRoute.self) { route in
                        switch route {
                        case .loupe(let request):
                            LoupeMachineView(request: request)
                        case .diffsplitter(let request):
                            if MCEIOSFeatureSupport.diffsplitter {
                                DiffsplitterView(request: request)
                            } else {
                                EmptyView()
                            }
                        }
                    }
            }
            .environment(\.locale, L10n.locale)
            .environment(\.mceIOSNavigate) { route in
                path.append(route)
            }
            .onOpenURL { url in
                let ext = url.pathExtension.lowercased()
                let route: MCEIOSRoute?
                switch ext {
                case "loum":
                    route = .loupe(LoupeMachineWindowRequest(action: .open, documentURL: url))
                case "dsplt", "dspltx":
                    guard MCEIOSFeatureSupport.diffsplitter else { return }
                    route = .diffsplitter(DiffsplitterWindowRequest(action: .open, documentURL: url))
                default:
                    return
                }
                _ = url.startAccessingSecurityScopedResource()
                if let route { path.append(route) }
            }
        }
    }
}

private struct MCEIOSNavigateKey: EnvironmentKey {
    static let defaultValue: (MCEIOSRoute) -> Void = { _ in }
}

extension EnvironmentValues {
    var mceIOSNavigate: (MCEIOSRoute) -> Void {
        get { self[MCEIOSNavigateKey.self] }
        set { self[MCEIOSNavigateKey.self] = newValue }
    }
}

#endif

//
//  Root.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI
import AppKit

public private(set) var isSIPSatisfied: Bool = true

@MainActor
private final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.title = L10n.t("About Deboogey")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.t("About Deboogey")) {
                AboutWindowController.shared.show()
            }
        }
    }
}

private struct UpgradeCommands: Commands {
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    @ObservedObject var upgradeChecker = UpgradeChecker.shared
    
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if #available(macOS 13.0, *) {
                Button(
                    upgradeChecker.upgradeAvailable ? L10n.f("Upgrade to %@", upgradeChecker.formattedLatestVersion) : L10n.t("Check for Upgrades..."),
                    systemImage: networkMonitor.isConnected ? "network" : "network.slash"
                ) { 
                    UpgradeChecker.shared.requestManualCheck() 
                }
                .disabled(!networkMonitor.isConnected)
                
                if !networkMonitor.isConnected {
                    Text(L10n.t("Network connection required"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(upgradeChecker.upgradeAvailable ? L10n.f("Upgrade to %@", upgradeChecker.formattedLatestVersion) : L10n.t("Check for Upgrades...")) {
                    UpgradeChecker.shared.requestManualCheck() 
                }
                .disabled(!networkMonitor.isConnected)
                
                if !networkMonitor.isConnected {
                    Text(L10n.t("Network connection required"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

@available(macOS 13.0, *)
private struct LoupeMachineCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        LoupeMachineCommandSet(
            createDocument: { LoupeMachineNavigation.open(documentAt: nil, using: openWindow) },
            openDocument: { LoupeMachineNavigation.chooseDocument(using: openWindow) }
        )
    }
}

private struct LoupeMachineLegacyCommands: Commands {
    var body: some Commands {
        LoupeMachineCommandSet(
            createDocument: { LoupeMachineNavigation.openLegacy(documentAt: nil) },
            openDocument: LoupeMachineNavigation.chooseDocumentLegacy
        )
    }
}

private struct LoupeMachineCommandSet: Commands {
    let createDocument: () -> Void
    let openDocument: () -> Void
    @ObservedObject private var router = LoupeMachineCommandRouter.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.t("New Loupe Machine Document")) {
                createDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.t("Open Loupe Machine Document…")) {
                openDocument()
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
    }
}

private struct SceneSwitcher: Scene {
    let sipSatisfied: Bool

    @SceneBuilder
    var body: some Scene {
        ConfigurationLegacy()

        if #available(macOS 14.0, *) {
            ConfigurationModern()
        }

        if #available(macOS 13.0, *) {
            DeboogeyLoupeScene()
            DeboogeyCDMLauncherScene()
            EntityTrackerScene()
        }

        if #available(macOS 13.0, *),
           !DebugVariables.isMarketplaceCandidateEditionBuild {
            DeboogeySDLauncherScene(sipSatisfied: sipSatisfied)
        }
    }
}

@available(macOS 13.0, *)
private struct DeboogeyLoupeScene: Scene {
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
            LoupeMachineCommands()
        }
        .defaultSize(
            width: AppWindowSizing.loupeMachine.defaultSize.width,
            height: AppWindowSizing.loupeMachine.defaultSize.height
        )
        .windowResizability(.contentMinSize)
    }
}

@available(macOS 13.0, *)
private struct DeboogeyCDMLauncherScene: Scene {
    var body: some Scene {
        Window(L10n.t("Cocoa Debug Menu"), id: "deboogey-cdm-launcher") {
            NavigationStack {
                DeboogeyCDMLauncherView { arguments in
                    EntityTracker.shared.record(source: .deboogeyCDM, arguments: arguments)
                }
            }
            .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .defaultSize(width: 520, height: 650)
        .windowResizability(.contentSize)
    }
}

@available(macOS 13.0, *)
private struct DeboogeySDLauncherScene: Scene {
    let sipSatisfied: Bool

    var body: some Scene {
        Window(L10n.t("SkyLight Diagnostics"), id: "deboogey-sd-launcher") {
            NavigationStack {
                if sipSatisfied {
                    VStack(spacing: 12) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 48, weight: .thin))
                            .foregroundColor(.secondary)
                        Text(L10n.t("SkyLight Diagnostics"))
                            .font(.headline)
                        Text(L10n.t("System write-dependent features have been disabled."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                } else {
                    DeboogeySDLauncherView { argument in
                        EntityTracker.shared.record(source: .wsOverlay, arguments: [argument])
                    }
                }
            }
            .environment(\.locale, L10n.locale)
        }
        .commandsRemoved()
        .defaultSize(width: 520, height: 540)
        .windowResizability(.contentSize)
    }
}

@available(macOS 13.0, *)
private struct EntityTrackerScene: Scene {
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

@available(macOS 13.0, *)
struct ConfigurationModern: Scene {
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

struct ConfigurationLegacy: Scene {
    var body: some Scene {
        Settings {
            ConfigurationRootView()
                .environment(\.locale, L10n.locale)
        }
    }
}

@main
struct Root: App {
    @State private var sipSatisfied: Bool = true

    init() {
        csrutilChecker.refreshSIPStatus()
        self._sipSatisfied = State(
            initialValue: DebugVariables.pseudoSystemIntegrityProtection ? false : isSIPSatisfied
        )
        print("csrutil: \(isSIPSatisfied)")

        PersistentVariables.registerDefaults()
        EntityTracker.shared.performConfiguredAutoRemoval()
    }

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environment(\.sipSatisfied, sipSatisfied)
                .environment(\.locale, L10n.locale)
        }
        .commands {
            AboutCommands()
            if !DebugVariables.isMarketplaceCandidateEditionBuild {
                UpgradeCommands()
            }
            if #available(macOS 13.0, *) {
                WindowLauncherCommands(
                    openMain: {
                        DeboogeyWindowController.open(.main, sipSatisfied: sipSatisfied)
                    },
                    includesCocoaDebugMenu: true,
                    includesSkyLightDiagnostics: !DebugVariables.isMarketplaceCandidateEditionBuild,
                    skyLightDiagnosticsDisabled: sipSatisfied
                )
            } else {
                LoupeMachineLegacyCommands()
                LegacyWindowLauncherCommands(
                    openMain: {
                        DeboogeyWindowController.open(.main, sipSatisfied: sipSatisfied)
                    },
                    openCocoaDebugMenu: {
                        DeboogeyWindowController.open(.cocoaDebugMenu, sipSatisfied: sipSatisfied)
                    },
                    openSkyLightDiagnostics: DebugVariables.isMarketplaceCandidateEditionBuild
                        ? nil
                        : {
                            DeboogeyWindowController.open(
                                .skyLightDiagnostics,
                                sipSatisfied: sipSatisfied
                            )
                        },
                    skyLightDiagnosticsDisabled: sipSatisfied
                )
            }
        }

        SceneSwitcher(sipSatisfied: sipSatisfied)
    }
}

@available(macOS 13.0, *)
private struct LoupeMachineExternalDocumentHandler: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.pathExtension.lowercased() == "loum" else { return }
            LoupeMachineNavigation.open(documentAt: url, using: openWindow)
        }
    }
}

private struct LoupeMachineLegacyExternalDocumentHandler: ViewModifier {
    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.pathExtension.lowercased() == "loum" else { return }
            LoupeMachineNavigation.openLegacy(documentAt: url)
        }
    }
}

private struct RootContentView: View {
    @ViewBuilder
    var body: some View {
        if #available(macOS 13.0, *) {
            RootView().modifier(LoupeMachineExternalDocumentHandler())
        } else {
            RootView().modifier(LoupeMachineLegacyExternalDocumentHandler())
        }
    }
}

private struct SIPSatisfiedKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var sipSatisfied: Bool {
        get { self[SIPSatisfiedKey.self] }
        set { self[SIPSatisfiedKey.self] = newValue }
    }
}


private enum csrutilChecker {
    static func refreshSIPStatus() {
        let path = "/usr/bin/csrutil"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            isSIPSatisfied = true
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["status"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            isSIPSatisfied = true
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.lowercased() else {
            isSIPSatisfied = true
            return
        }

        if !output.contains("enabled") && output.contains("disabled") {
            isSIPSatisfied = false
            return
        }

        if output.contains("debugging restrictions: disabled") {
            isSIPSatisfied = false
            return
        }
        isSIPSatisfied = true
    }
}

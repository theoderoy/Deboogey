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
        window.sizeToFittingContentAndCenter()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.sizeToFittingContentAndCenter()
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

    private var upgradeTitle: String {
        upgradeChecker.upgradeAvailable
            ? L10n.f("Upgrade to %@", upgradeChecker.formattedLatestVersion)
            : L10n.t("Check for Upgrades...")
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if !DebugVariables.areUpdatesDisabled {
                Group {
                    if #available(macOS 13.0, *) {
                        Button(
                            upgradeTitle,
                            systemImage: networkMonitor.isConnected ? "network" : "network.slash"
                        ) {
                            UpgradeChecker.shared.requestManualCheck()
                        }
                    } else {
                        Button(upgradeTitle) {
                            UpgradeChecker.shared.requestManualCheck()
                        }
                    }
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

private struct LoupeMachineLegacyCommands: Commands {
    var body: some Commands {
        DocumentToolCommandSet(
            createLoupeDocument: { LoupeMachineNavigation.openLegacy(documentAt: nil) },
            openLoupeDocument: LoupeMachineNavigation.chooseDocumentLegacy,
            createDiffsplitterDocument: { DiffsplitterNavigation.openLegacy(documentAt: nil) },
            openDiffsplitterDocument: DiffsplitterNavigation.chooseDocumentLegacy,
            openMain: DeboogeyWindowController.openMain
        )
    }
}

private struct SceneSwitcher: Scene {
    let sipSatisfied: Bool

    @SceneBuilder
    var body: some Scene {
        ConfigurationLegacy()
            .commands {
                RootPrimaryWindowCommands(sipSatisfied: sipSatisfied)
            }

        if #available(macOS 14.0, *) {
            ConfigurationModern()
        }

        if #available(macOS 13.0, *) {
            DeboogeyLoupeScene()
            DeboogeyDiffsplitterScene()
            DeboogeyCDMLauncherScene()
            EntityTrackerScene()
        }

        if #available(macOS 13.0, *),
           !DebugVariables.isMarketplaceCandidateEditionBuild {
            DeboogeySDLauncherScene(sipSatisfied: sipSatisfied)
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

        PersistentVariables.registerDefaults()
        EntityTracker.shared.performConfiguredAutoRemoval()
        DeboogeyLegacyRootLaunch.openIfNeeded(DeboogeyWindowController.openMain)
    }

    var body: some Scene {
        if #available(macOS 13.0, *) {
            DeboogeyRootWindowScene {
                DeboogeyRootContentView()
                    .environment(\.sipSatisfied, sipSatisfied)
                    .environment(\.locale, L10n.locale)
            }
        }
        SceneSwitcher(sipSatisfied: sipSatisfied)
    }
}

private struct RootPrimaryWindowCommands: Commands {
    let sipSatisfied: Bool

    var body: some Commands {
        AboutCommands()
#if !DEBOOGEY_MCE
        UpgradeCommands()
#endif
        LoupeMachineLegacyCommands()
        LegacyWindowLauncherCommands(
            openMain: DeboogeyWindowController.openMain,
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

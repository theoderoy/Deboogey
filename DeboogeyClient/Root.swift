//
//  Root.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/10/2025.
//

import SwiftUI
import AppKit

public private(set) var isSIPSatisfied: Bool = true

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

private struct SceneSwitcher: Scene {
    let sipSatisfied: Bool

    @SceneBuilder
    var body: some Scene {
        ConfigurationLegacy()

        if #available(macOS 14.0, *) {
            ConfigurationModern()
        }

        if #available(macOS 13.0, *) {
            DeboogeyCDMLauncherScene()
            DeboogeySDLauncherScene(sipSatisfied: sipSatisfied)
            EntityTrackerScene()
        }
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
private struct WindowLauncherCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let sipSatisfied: Bool

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(L10n.t("Cocoa Debug Menu"), systemImage: "wrench.and.screwdriver") {
                openWindow(id: "deboogey-cdm-launcher")
            }

            Button(L10n.t("SkyLight Diagnostics"), systemImage: "macwindow") {
                openWindow(id: "deboogey-sd-launcher")
            }
            .disabled(sipSatisfied)
        }
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
        if UserDefaults.standard.bool(forKey: "deboogey.entityTracker.autoDeleteEnabled") {
            let scope = UserDefaults.standard.string(forKey: "deboogey.entityTracker.autoDeleteScope") ?? "ephemerals"
            let trigger = UserDefaults.standard.string(forKey: "deboogey.entityTracker.autoDeleteTrigger") ?? "login"

            let shouldDelete: Bool
            if trigger == "launch" {
                shouldDelete = true
            } else {
                let sessionKey = "deboogey.entityTracker.lastKnownSessionID"
                let currentSession = loginSessionID()
                let storedSession = UserDefaults.standard.string(forKey: sessionKey)
                
                if currentSession != storedSession {
                    UserDefaults.standard.set(currentSession, forKey: sessionKey)
                    shouldDelete = true
                } else {
                    shouldDelete = false
                }
            }

            if shouldDelete {
                switch scope {
                case "ephemerals": EntityTracker.shared.removeEphemerals()
                case "all":        EntityTracker.shared.removeAll()
                default: break
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.sipSatisfied, sipSatisfied)
                .environment(\.locale, L10n.locale)
        }
        .commands {
            UpgradeCommands()
            if #available(macOS 13.0, *) {
                WindowLauncherCommands(sipSatisfied: sipSatisfied)
            } else {
                EmptyCommands()
            }
        }

        SceneSwitcher(sipSatisfied: sipSatisfied)
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

private func loginSessionID() -> String {
    var mib = [CTL_KERN, KERN_BOOTTIME]
    var bootTime = timeval()
    var size = MemoryLayout<timeval>.size
    
    let bootTimestamp: Int
    if sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 {
        bootTimestamp = bootTime.tv_sec
    } else {
        // Extremely unlikely to instate, but let's not abandon ship guys.
        bootTimestamp = Int(Date().timeIntervalSince1970)
    }

    let uid = getuid()
    let processSession = getsid(0)
    return "\(bootTimestamp)-\(uid)-\(processSession)"
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
